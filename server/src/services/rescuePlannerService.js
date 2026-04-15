/**
 * 急救规划引擎
 * 综合地理编码、路径规划、医疗信息，生成完整的救援方案
 */

const {
  reverseGeocode,
  searchNearbyHospitalsWithAMap,
  searchHospitalsByKeywordWithAMap,
  searchNearbyRescueTeamsWithAMap,
  searchRescueTeamsByKeywordWithAMap,
} = require('./geocodingService');
const { calculateRoute, batchCalculateRoutes, calculateStraightDistance } = require('./routingService');
const { rankSosList } = require('../utils/priorityEngine');

// ============================================================================
// 🔑 配置区域
// ============================================================================

/**
 * 【可选】默认医院位置（当未指定时使用）
 * 格式：{ name: '医院名称', lng: 经度, lat: 纬度 }
 * 建议：根据实际部署地区修改为当地主要医院
 */
const DEFAULT_HOSPITALS = [];
const DEFAULT_RESCUE_TEAMS = [];

/**
 * 【可选】最大并发路径计算数
 */
const MAX_ROUTE_CONCURRENCY = parseInt(process.env.MAX_ROUTE_CONCURRENCY) || 5;

/**
 * 【可选】是否启用详细日志
 */
const DEBUG_MODE = process.env.DEBUG_RESCUE_PLANNER === 'true';

// ============================================================================
// 核心功能
// ============================================================================

/**
 * 生成单个求救者的完整救援计划
 * @param {Object} sosRecord - SOS记录对象（需包含 priority 字段）
 * @param {Array} [hospitals] - 候选医院列表 [{name, lng, lat}, ...]
 * @param {Object} [options] - 可选参数
 * @param {boolean} [options.includeFullSteps=true] - 是否包含完整导航步骤
 * @param {number} [options.maxNearbyHospitals=3] - 最多返回几个附近医院
 * @returns {Promise<Object>} 救援计划对象
 */
async function generateSingleRescuePlan(sosRecord, hospitals = null, options = {}) {
  const startTime = Date.now();
  
  if (DEBUG_MODE) {
    console.log(`[RescuePlanner] 开始生成救援计划: ${sosRecord.senderMac}`);
  }
  
  const {
    includeFullSteps = true,
    maxNearbyHospitals = 3,
  } = options;
  
  const [lng, lat] = sosRecord.location.coordinates;
  
  try {
    // ==========================================================================
    // 1. 获取详细地址信息
    // ==========================================================================
    let addressInfo = null;
    try {
      addressInfo = await reverseGeocode(lng, lat);
      if (DEBUG_MODE) {
        console.log(`[RescuePlanner] ✓ 地址解析成功: ${addressInfo.formattedAddress}`);
      }
    } catch (err) {
      console.warn(`[RescuePlanner] ⚠ 地址解析失败: ${err.message}`);
      addressInfo = {
        formattedAddress: '地址解析失败',
        addressComponent: {},
        pois: [],
      };
    }
    
    // ==========================================================================
    // 2. 计算到各医院的路线，找出最近的
    // ==========================================================================
    const patientAge = parsePatientAge(sosRecord?.medicalProfile?.age);
    const hospitalList = rankHospitalsForPatient(
      hospitals || await resolveCandidateHospitalsAdaptive(lng, lat, addressInfo, DEFAULT_HOSPITALS),
      sosRecord,
    );
    const hospitalDistances = [];
    
    for (const hospital of hospitalList) {
      try {
        const route = await calculateRoute(
          lng, lat,
          hospital.lng, hospital.lat,
          { strategy: '0' } // 速度优先
        );
        
        hospitalDistances.push({
          ...hospital,
          emergencyScore: getEmergencyHospitalScore(hospital?.institutionName || hospital?.name || '', hospital?.type || ''),
          strongSignal: hasStrongEmergencySignal(hospital?.institutionName || hospital?.name || '', hospital?.type || ''),
          specialtyPenalty: getHospitalSpecialtyPenalty(hospital?.institutionName || hospital?.name || '', patientAge),
          distance: route.distance,
          duration: route.duration,
          route: includeFullSteps ? route : {
            distance: route.distance,
            duration: route.duration,
            tolls: route.tolls,
            overview: route.overview,
          },
        });
      } catch (err) {
        console.warn(`[RescuePlanner] ⚠ 到医院 ${hospital.name} 的路径规划失败:`, err.message);
        // 降级：使用直线距离估算
        const straightDist = calculateStraightDistance(lng, lat, hospital.lng, hospital.lat);
        hospitalDistances.push({
          ...hospital,
          emergencyScore: getEmergencyHospitalScore(hospital?.institutionName || hospital?.name || '', hospital?.type || ''),
          strongSignal: hasStrongEmergencySignal(hospital?.institutionName || hospital?.name || '', hospital?.type || ''),
          specialtyPenalty: getHospitalSpecialtyPenalty(hospital?.institutionName || hospital?.name || '', patientAge),
          distance: straightDist,
          duration: Math.round(straightDist / 500 * 60), // 假设平均时速30km/h
          error: err.message,
        });
      }
    }
    
    // 按距离排序
    hospitalDistances.sort(compareHospitalsForDispatch);
    const nearestHospital = hospitalDistances[0];
    
    if (DEBUG_MODE && nearestHospital) {
      console.log(`[RescuePlanner] ✓ 最近医院: ${nearestHospital.name} (${(nearestHospital.distance / 1000).toFixed(2)}km)`);
    }
    
    // ==========================================================================
    // 3. 提取医疗档案关键信息
    // ==========================================================================
    const medicalProfile = sosRecord.medicalProfile || {};
    const criticalInfo = [];
    
    if (medicalProfile.medicalHistory && medicalProfile.medicalHistory !== '无') {
      criticalInfo.push(`病史: ${medicalProfile.medicalHistory}`);
    }
    if (medicalProfile.allergies && medicalProfile.allergies !== '无') {
      criticalInfo.push(`⚠️ 过敏: ${medicalProfile.allergies}`);
    }
    if (medicalProfile.emergencyContact) {
      criticalInfo.push(`紧急联系人: ${medicalProfile.emergencyContact}`);
    }
    if (medicalProfile.name) {
      criticalInfo.push(`姓名: ${medicalProfile.name}${medicalProfile.age ? ` (${medicalProfile.age}岁)` : ''}`);
    }
    
    // ==========================================================================
    // 4. 生成AI建议
    // ==========================================================================
    const aiRecommendations = generateAiRecommendations(sosRecord, addressInfo, nearestHospital);
    
    // ==========================================================================
    // 5. 组装最终救援计划
    // ==========================================================================
    const plan = {
      senderMac: sosRecord.senderMac,
      generatedAt: new Date().toISOString(),
      
      // 优先级信息
      priority: sosRecord.priority || {
        score: 0,
        severityLevel: 'unknown',
        elapsedMin: 0,
        breakdown: [],
      },
      
      // 位置信息
      location: {
        coordinates: [lng, lat],
        address: addressInfo.formattedAddress,
        detailed: addressInfo.addressComponent,
        nearbyLandmarks: addressInfo.pois || [],
        nearbyRoads: addressInfo.roads || [],
      },
      
      // 医疗信息
      medical: {
        bloodType: sosRecord.bloodType,
        bloodTypeName: getBloodTypeName(sosRecord.bloodType),
        profile: medicalProfile,
        criticalNotes: criticalInfo,
      },
      
      // 救援路线
      route: nearestHospital?.route ? {
        toHospital: nearestHospital.name,
        sourceCoordinates: [lng, lat],
        destinationCoordinates: [nearestHospital.lng, nearestHospital.lat],
        destinationMeta: {
          name: nearestHospital.name,
          address: nearestHospital.address || '',
          type: nearestHospital.type || '',
          source: nearestHospital.source || '',
        },
        distanceMeters: nearestHospital.route.distance,
        distanceKm: (nearestHospital.route.distance / 1000).toFixed(2),
        estimatedTimeSeconds: nearestHospital.route.duration,
        estimatedTimeMinutes: Math.ceil(nearestHospital.route.duration / 60),
        tolls: nearestHospital.route.tolls,
        trafficLights: nearestHospital.route.trafficLights,
        keySteps: (nearestHospital.route.steps || []).slice(0, 5).map(s => s.instruction),
        fullSteps: includeFullSteps ? nearestHospital.route.steps : undefined,
      } : null,
      
      // 推荐医院列表
      recommendedHospitals: hospitalDistances.slice(0, maxNearbyHospitals).map(h => ({
        name: h.name,
        location: [h.lng, h.lat],
        address: h.address || '',
        type: h.type || '',
        source: h.source || '',
        distanceMeters: h.distance,
        distanceKm: (h.distance / 1000).toFixed(2),
        estimatedTimeMinutes: Math.ceil(h.duration / 60),
        emergencyScore: h.emergencyScore,
        strongSignal: !!h.strongSignal,
        specialtyPenalty: h.specialtyPenalty || 0,
        hasError: !!h.error,
      })),
      
      // AI建议
      aiRecommendations,
      
      // 元数据
      metadata: {
        generationTimeMs: Date.now() - startTime,
        provider: addressInfo.provider || 'unknown',
      },
    };
    
    if (DEBUG_MODE) {
      console.log(`[RescuePlanner] ✓ 救援计划生成完成 (耗时 ${plan.metadata.generationTimeMs}ms)`);
    }
    
    return plan;
  } catch (err) {
    console.error('[RescuePlanner] ✗ 生成救援计划失败:', err);
    throw new Error(`救援计划生成失败: ${err.message}`);
  }
}

/**
 * 批量救援计划优化（贪心算法简化版TSP）
 * @param {Array} sosRecords - SOS记录数组
 * @param {Object} origin - 出发点 {lng, lat, name}
 * @param {Object} [options] - 可选参数
 * @param {string} [options.optimizationStrategy='efficiency'] - 优化策略 ('efficiency' | 'urgency' | 'distance')
 * @returns {Promise<Object>} 优化后的救援序列
 */
async function generateNearestRescueTeamPlan(sosRecord, rescueTeams = null, options = {}) {
  const startTime = Date.now();
  const {
    includeFullSteps = true,
    maxNearbyTeams = 3,
  } = options;

  const [lng, lat] = sosRecord.location.coordinates;

  try {
    let addressInfo = null;
    try {
      addressInfo = await reverseGeocode(lng, lat);
    } catch (err) {
      console.warn(`[RescuePlanner] rescue-team reverse geocode failed: ${err.message}`);
      addressInfo = {
        formattedAddress: '',
        addressComponent: {},
        pois: [],
      };
    }

    const teamList = prioritizeRescueTeams(
      rescueTeams || await resolveCandidateRescueTeamsAdaptive(lng, lat, addressInfo, DEFAULT_RESCUE_TEAMS),
      sosRecord,
    );

    const teamRoutes = [];
    for (const team of teamList) {
      try {
        const route = await calculateRoute(team.lng, team.lat, lng, lat, { strategy: '0' });
        teamRoutes.push({
          ...team,
          rescueScore: getRescueTeamScore(team?.name || '', team?.type || '', sosRecord),
          strongSignal: hasStrongRescueSignal(team?.name || '', team?.type || ''),
          distance: route.distance,
          duration: route.duration,
          route: includeFullSteps ? route : {
            distance: route.distance,
            duration: route.duration,
            tolls: route.tolls,
            overview: route.overview,
          },
        });
      } catch (err) {
        const straightDist = calculateStraightDistance(team.lng, team.lat, lng, lat);
        teamRoutes.push({
          ...team,
          rescueScore: getRescueTeamScore(team?.name || '', team?.type || '', sosRecord),
          strongSignal: hasStrongRescueSignal(team?.name || '', team?.type || ''),
          distance: straightDist,
          duration: Math.round(straightDist / 500 * 60),
          error: err.message,
        });
      }
    }

    teamRoutes.sort(compareRescueTeamsForDispatch);
    const nearestTeam = teamRoutes[0];
    const medicalProfile = sosRecord.medicalProfile || {};

    return {
      senderMac: sosRecord.senderMac,
      generatedAt: new Date().toISOString(),
      priority: sosRecord.priority || {
        score: 0,
        severityLevel: 'unknown',
        elapsedMin: 0,
        breakdown: [],
      },
      location: {
        coordinates: [lng, lat],
        address: addressInfo.formattedAddress,
        detailed: addressInfo.addressComponent,
        nearbyLandmarks: addressInfo.pois || [],
      },
      medical: {
        bloodType: sosRecord.bloodType,
        bloodTypeName: getBloodTypeName(sosRecord.bloodType),
        profile: medicalProfile,
      },
      route: nearestTeam?.route ? {
        fromTeam: nearestTeam.name,
        sourceCoordinates: [nearestTeam.lng, nearestTeam.lat],
        destinationCoordinates: [lng, lat],
        sourceMeta: {
          name: nearestTeam.name,
          address: nearestTeam.address || '',
          type: nearestTeam.type || '',
          source: nearestTeam.source || '',
        },
        destinationMeta: {
          name: medicalProfile.name || sosRecord.senderMac,
          address: addressInfo.formattedAddress || '',
          type: 'victim',
          source: 'sos_record',
        },
        distanceMeters: nearestTeam.route.distance,
        distanceKm: (nearestTeam.route.distance / 1000).toFixed(2),
        estimatedTimeSeconds: nearestTeam.route.duration,
        estimatedTimeMinutes: Math.ceil(nearestTeam.route.duration / 60),
        tolls: nearestTeam.route.tolls,
        trafficLights: nearestTeam.route.trafficLights,
        keySteps: (nearestTeam.route.steps || []).slice(0, 5).map((s) => s.instruction),
        fullSteps: includeFullSteps ? nearestTeam.route.steps : undefined,
      } : null,
      recommendedRescueTeams: teamRoutes.slice(0, maxNearbyTeams).map((team) => ({
        name: team.name,
        location: [team.lng, team.lat],
        address: team.address || '',
        type: team.type || '',
        source: team.source || '',
        distanceMeters: team.distance,
        distanceKm: (team.distance / 1000).toFixed(2),
        estimatedTimeMinutes: Math.ceil(team.duration / 60),
        rescueScore: team.rescueScore,
        strongSignal: !!team.strongSignal,
        hasError: !!team.error,
      })),
      dispatchRecommendations: buildRescueDispatchRecommendations(sosRecord, nearestTeam, addressInfo),
      metadata: {
        generationTimeMs: Date.now() - startTime,
        provider: addressInfo.provider || 'unknown',
      },
    };
  } catch (err) {
    console.error('[RescuePlanner] rescue team plan failed:', err);
    throw new Error(`rescue team plan failed: ${err.message}`);
  }
}

async function optimizeBatchRescue(sosRecords, origin, options = {}) {
  const startTime = Date.now();
  
  const {
    optimizationStrategy = 'efficiency', // efficiency=性价比, urgency=紧急度, distance=最短路径
  } = options;
  
  if (!sosRecords || sosRecords.length === 0) {
    throw new Error('求救记录列表不能为空');
  }
  
  if (!origin || !origin.lng || !origin.lat) {
    throw new Error('出发点坐标无效');
  }
  
  try {
    // ==========================================================================
    // 1. 重新计算所有记录的优先级
    // ==========================================================================
    const ranked = rankSosList(sosRecords);
    
    // ==========================================================================
    // 2. 批量计算到各目标的路线
    // ==========================================================================
    const destinations = ranked.map(record => ({
      mac: record.senderMac,
      lng: record.location.coordinates[0],
      lat: record.location.coordinates[1],
      priority: record.priority,
      medicalProfile: record.medicalProfile,
    }));
    
    if (DEBUG_MODE) {
      console.log(`[RescuePlanner] 开始批量路径计算 (${destinations.length}个目标)...`);
    }
    
    const targetsWithRoutes = await batchCalculateRoutes(
      origin,
      destinations,
      MAX_ROUTE_CONCURRENCY
    );
    
    // ==========================================================================
    // 3. 根据策略排序
    // ==========================================================================
    let sortedTargets;
    
    switch (optimizationStrategy) {
      case 'efficiency':
        // 性价比 = 优先级分数 / 距离(km)
        sortedTargets = targetsWithRoutes
          .filter(t => t.success && t.route)
          .sort((a, b) => {
            const efficiencyA = (a.priority?.score || 0) / ((a.route.distance || 1) / 1000);
            const efficiencyB = (b.priority?.score || 0) / ((b.route.distance || 1) / 1000);
            return efficiencyB - efficiencyA;
          });
        break;
        
      case 'urgency':
        // 纯紧急度优先
        sortedTargets = targetsWithRoutes
          .filter(t => t.success)
          .sort((a, b) => (b.priority?.score || 0) - (a.priority?.score || 0));
        break;
        
      case 'distance':
        // 最短路径优先（适合集中救援）
        sortedTargets = targetsWithRoutes
          .filter(t => t.success && t.route)
          .sort((a, b) => (a.route.distance || Infinity) - (b.route.distance || Infinity));
        break;
        
      default:
        throw new Error(`未知的优化策略: ${optimizationStrategy}`);
    }
    
    // ==========================================================================
    // 4. 生成优化序列
    // ==========================================================================
    const sequence = sortedTargets.map((target, idx) => ({
      order: idx + 1,
      mac: target.mac,
      priority: target.priority,
      medicalSummary: summarizeMedicalInfo(target.medicalProfile),
      location: {
        lng: target.lng,
        lat: target.lat,
      },
      route: target.route ? {
        distanceKm: (target.route.distance / 1000).toFixed(2),
        estimatedTimeMin: Math.ceil(target.route.duration / 60),
        tolls: target.route.tolls,
      } : null,
      cumulativeTimeMin: sortedTargets
        .slice(0, idx + 1)
        .reduce((sum, t) => sum + Math.ceil((t.route?.duration || 0) / 60), 0),
    }));
    
    const totalTimeMin = sequence.reduce((sum, item) => 
      sum + Math.ceil((item.route?.estimatedTimeMin || 0)), 0);
    
    const result = {
      optimizationStrategy,
      totalTargets: sequence.length,
      failedTargets: targetsWithRoutes.filter(t => !t.success).length,
      estimatedTotalTimeMin: totalTimeMin,
      origin: {
        name: origin.name || '出发点',
        lng: origin.lng,
        lat: origin.lat,
      },
      sequence,
      summary: generateBatchSummary(sequence),
      metadata: {
        generationTimeMs: Date.now() - startTime,
        algorithm: 'greedy_tsp_approximation',
      },
    };
    
    if (DEBUG_MODE) {
      console.log(`[RescuePlanner] ✓ 批量优化完成 (耗时 ${result.metadata.generationTimeMs}ms)`);
    }
    
    return result;
  } catch (err) {
    console.error('[RescuePlanner] ✗ 批量优化失败:', err);
    throw new Error(`批量救援优化失败: ${err.message}`);
  }
}

// ============================================================================
// 辅助函数
// ============================================================================

/**
 * 生成AI建议文本
 */
function generateAiRecommendations(sosRecord, addressInfo, nearestHospital) {
  const recommendations = [];
  const priority = sosRecord.priority || {};
  const medical = sosRecord.medicalProfile || {};
  
  // 基于严重程度
  if (priority.severityLevel === 'critical') {
    recommendations.push(' 危重级别：建议立即派遣救护车，优先开通绿色通道');
    recommendations.push('📞 提前通知医院急诊科准备抢救设备');
  } else if (priority.severityLevel === 'urgent') {
    recommendations.push('🟠 紧急级别：建议在30分钟内到达现场');
  } else if (priority.severityLevel === 'warning') {
    recommendations.push('🟡 注意级别：建议在1小时内处理');
  }
  
  // 基于病史
  if (medical.medicalHistory) {
    const history = medical.medicalHistory.toLowerCase();
    if (history.includes('心脏病') || history.includes('心脏')) {
      recommendations.push('💊 患者有心脏病史，请携带除颤仪(AED)和硝酸甘油');
    }
    if (history.includes('糖尿病')) {
      recommendations.push('🩸 患者有糖尿病史，请准备葡萄糖注射液和血糖仪');
    }
    if (history.includes('高血压')) {
      recommendations.push('🫀 患者有高血压史，避免剧烈移动，监测血压');
    }
    if (history.includes('哮喘') || history.includes('呼吸')) {
      recommendations.push('🌬️ 患者有呼吸系统疾病，请携带氧气瓶和支气管扩张剂');
    }
  }
  
  // 基于过敏
  if (medical.allergies && medical.allergies !== '无') {
    recommendations.push(`⚠️ 过敏警示：严禁使用含"${medical.allergies}"成分的药物`);
  }
  
  // 基于血型
  if (sosRecord.bloodType >= 0) {
    const bloodTypes = ['A型', 'B型', 'AB型', 'O型'];
    recommendations.push(`🩸 血型：${bloodTypes[sosRecord.bloodType]}，如需输血请提前准备`);
  }
  
  // 基于位置
  if (addressInfo?.pois?.some(p => p.type?.includes('医院'))) {
    recommendations.push('🏥 附近有医疗机构，可考虑就近送医或请求支援');
  }
  
  // 基于等待时间
  if (priority.elapsedMin > 60) {
    recommendations.push(`⏰ 已等待${priority.elapsedMin}分钟，情况可能恶化，需加速救援`);
  } else if (priority.elapsedMin > 30) {
    recommendations.push(`⏱️ 已等待${priority.elapsedMin}分钟，建议优先处理`);
  }
  
  // 基于路线
  if (nearestHospital?.route) {
    const timeMin = Math.ceil(nearestHospital.route.duration / 60);
    if (timeMin > 30) {
      recommendations.push(`🛣️ 路程较远(${timeMin}分钟)，建议途中持续监护生命体征`);
    }
    if (nearestHospital.route.tolls > 0) {
      recommendations.push(`💰 预计过路费¥${nearestHospital.route.tolls}，可申请应急报销`);
    }
  }
  
  // 默认建议
  if (recommendations.length === 0) {
    recommendations.push('✅ 按标准流程执行救援，保持通讯畅通');
  }
  
  return recommendations;
}

/**
 * 获取血型名称
 */
function getBloodTypeName(bloodTypeCode) {
  const types = {
    '-1': '未知',
    '0': 'A型',
    '1': 'B型',
    '2': 'AB型',
    '3': 'O型',
  };
  return types[String(bloodTypeCode)] || '未知';
}

/**
 * 简化医疗信息摘要
 */
function summarizeMedicalInfo(profile) {
  if (!profile) return null;
  
  const parts = [];
  if (profile.name) parts.push(profile.name);
  if (profile.age) parts.push(`${profile.age}岁`);
  if (profile.medicalHistory && profile.medicalHistory !== '无') {
    parts.push(`病史:${profile.medicalHistory}`);
  }
  if (profile.allergies && profile.allergies !== '无') {
    parts.push(`过敏:${profile.allergies}`);
  }
  
  return parts.join(' | ') || '无详细信息';
}

/**
 * 生成批量救援摘要
 */
async function resolveCandidateHospitals(lng, lat, addressInfo, fallbackHospitals = []) {
  let nearbyHospitals = [];

  try {
    nearbyHospitals = await searchNearbyHospitalsWithAMap(lng, lat, {
      radius: 8000,
      pageSize: 15,
      keywords: '医院 急救中心 医疗中心',
    });
  } catch (err) {
    if (DEBUG_MODE) {
      console.warn(`[RescuePlanner] hospital search fallback: ${err.message}`);
    }
  }

  return buildCandidateHospitals(addressInfo, fallbackHospitals, nearbyHospitals);
}

function buildCandidateHospitals(addressInfo, fallbackHospitals = [], searchedHospitals = []) {
  const nearbyHospitals = Array.isArray(searchedHospitals) && searchedHospitals.length > 0
    ? searchedHospitals
        .filter((poi) => isUsableHospitalCandidate(poi))
        .map((poi) => normalizeHospitalCandidate(poi, 'search_api'))
        .filter(Boolean)
    : Array.isArray(addressInfo?.pois)
    ? addressInfo.pois
        .filter((poi) => isUsableHospitalCandidate(poi))
        .filter((poi) => Array.isArray(poi.location) && poi.location.length === 2)
        .map((poi) => normalizeHospitalCandidate(poi, 'nearby_poi'))
        .filter(Boolean)
    : [];

  const sanitizedFallbacks = (Array.isArray(fallbackHospitals) ? fallbackHospitals : [])
    .filter((hospital) => hospital?.name !== '市第一人民医院');

  const merged = [...nearbyHospitals, ...sanitizedFallbacks];
  const deduped = [];
  const seen = new Set();

  for (const hospital of merged) {
    if (!hospital || typeof hospital.lng !== 'number' || typeof hospital.lat !== 'number') {
      continue;
    }

    const key = `${hospital.name || ''}:${hospital.lng.toFixed(5)},${hospital.lat.toFixed(5)}`;
    if (seen.has(key)) {
      continue;
    }

    seen.add(key);
    deduped.push(hospital);
  }

  return deduped;
}

function normalizeHospitalCandidate(poi, source = 'nearby_poi') {
  const location = Array.isArray(poi?.location) ? poi.location : [];
  const lng = Number(location[0] ?? poi?.lng);
  const lat = Number(location[1] ?? poi?.lat);
  const displayName = simplifyHospitalName(poi?.name || '');
  const canonicalName = extractHospitalInstitutionName(poi?.name || '', poi?.type || '');

  if (!Number.isFinite(lng) || !Number.isFinite(lat) || !canonicalName) {
    return null;
  }

  return {
    name: displayName || canonicalName,
    institutionName: canonicalName,
    lng,
    lat,
    source,
    approxDistance: poi?.distance ?? poi?.approxDistance ?? null,
    address: poi?.address || '',
    type: poi?.type || '',
  };
}

function simplifyHospitalName(name) {
  const text = String(name || '').trim();
  if (!text) {
    return '';
  }

  return text
    .split('/')[0]
    .replace(/[（(].*$/, '')
    .trim();
}

function extractHospitalInstitutionName(name, type = '') {
  const text = simplifyHospitalName(name);
  const typeText = String(type || '');

  if (!text) {
    return '';
  }

  const patterns = [
    /.*?(?:大学(?:附属)?(?:第[一二三四五六七八九十0-9]+)?医院)/,
    /.*?(?:医学院(?:附属)?(?:第[一二三四五六七八九十0-9]+)?医院)/,
    /.*?(?:第[一二三四五六七八九十0-9]+人民医院)/,
    /.*?(?:人民医院)/,
    /.*?(?:中心医院)/,
    /.*?(?:总医院)/,
    /.*?(?:附属医院)/,
    /.*?(?:妇幼保健院)/,
    /.*?(?:中医院)/,
    /.*?(?:儿童医院)/,
    /.*?(?:肿瘤医院)/,
    /.*?(?:胸科医院)/,
    /.*?(?:精神卫生中心)/,
    /.*?(?:急救中心)/,
    /.*?(?:医疗中心)/,
  ];

  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (match?.[0]) {
      return match[0];
    }
  }

  const humanHospitalType = /综合医院|三级甲等医院|三级医院|专科医院|急救中心|医疗中心/.test(typeText);
  if (humanHospitalType && text.includes('医院')) {
    const genericMatch = text.match(/.*?医院/);
    return genericMatch?.[0] || text;
  }

  return '';
}

function isHospitalPoi(poi) {
  if (!poi) {
    return false;
  }

  const name = String(poi.name || '');
  const type = String(poi.type || '');
  const typeCode = String(poi.typeCode || '');

  return (
    name.includes('医院')
    || name.includes('急救中心')
    || name.includes('医疗中心')
    || type.includes('医院')
    || type.includes('医疗保健服务')
    || typeCode.startsWith('0901')
  );
}

function isUsableHospitalCandidate(poi) {
  if (!isHospitalPoi(poi)) {
    return false;
  }

  const name = String(poi?.name || '');
  const type = String(poi?.type || '');
  return getEmergencyHospitalScore(name, type) > 20;
}

function isMainHospitalEntityName(name, type = '') {
  const text = simplifyHospitalName(name);
  const typeText = String(type || '');

  if (!text || !extractHospitalInstitutionName(text, typeText)) {
    return false;
  }

  const exactPatterns = [
    /.*(?:大学(?:附属)?(?:第[一二三四五六七八九十0-9]+)?医院)(?:院区|分院|[东南西北]区)?$/,
    /.*(?:医学院(?:附属)?(?:第[一二三四五六七八九十0-9]+)?医院)(?:院区|分院|[东南西北]区)?$/,
    /.*(?:第[一二三四五六七八九十0-9]+人民医院)(?:院区|分院|[东南西北]区)?$/,
    /.*(?:人民医院|中心医院|总医院|附属医院|妇幼保健院|中医院|儿童医院|肿瘤医院|胸科医院|精神卫生中心|急救中心|医疗中心)(?:院区|分院|[东南西北]区)?$/,
  ];

  if (exactPatterns.some((pattern) => pattern.test(text))) {
    return true;
  }

  const humanHospitalType = /综合医院|三级甲等医院|三级医院|专科医院|急救中心|医疗中心/.test(typeText);
  return humanHospitalType && /.*医院(?:院区|分院|[东南西北]区)?$/.test(text);
}

function isClearlyNonEmergencyHospital(name, type = '') {
  const text = `${simplifyHospitalName(name)} ${String(type || '')}`;
  return /美容|整形|宠物|口腔门诊|门诊部|诊所|体检|健康管理|养生|美容医院|医疗美容|宠物医院/.test(text);
}

function hasStrongEmergencySignal(name, type = '') {
  const text = simplifyHospitalName(name);
  const typeText = String(type || '');

  return (
    /三级甲等医院|三级医院|急救中心/.test(typeText)
    || /大学.*附属.*医院|医学院.*附属.*医院|人民医院|中心医院|总医院/.test(text)
    || /省.*医院|市.*医院/.test(text)
  );
}

function getWeakGenericHospitalPenalty(name, type = '') {
  const text = simplifyHospitalName(name);
  const typeText = String(type || '');
  const prefix = text.replace(/医院.*$/, '').trim();
  const hasWeakGenericName = text.endsWith('医院') && prefix.length <= 3;
  const hasOnlyGenericType = /综合医院/.test(typeText) && !hasStrongEmergencySignal(text, typeText);

  if (hasWeakGenericName && hasOnlyGenericType) {
    return 95;
  }

  if (hasWeakGenericName) {
    return 55;
  }

  if (hasOnlyGenericType) {
    return 35;
  }

  return 0;
}

function getEmergencyHospitalScore(name, type = '') {
  const text = simplifyHospitalName(name);
  const typeText = String(type || '');

  if (!text || !extractHospitalInstitutionName(text, typeText)) {
    return Number.NEGATIVE_INFINITY;
  }

  if (isClearlyNonEmergencyHospital(text, typeText)) {
    return Number.NEGATIVE_INFINITY;
  }

  let score = 0;

  if (/三级甲等医院|三级医院/.test(typeText)) {
    score += 180;
  }
  if (/急救中心/.test(typeText)) {
    score += 170;
  }
  if (/综合医院/.test(typeText)) {
    score += 35;
  }
  if (/大学.*附属.*医院|医学院.*附属.*医院|人民医院|中心医院|总医院/.test(text)) {
    score += 140;
  }
  if (/省.*医院|市.*医院/.test(text)) {
    score += 90;
  }
  if (/院区|分院|西区|东区|南区|北区/.test(text)) {
    score += 20;
  }
  if (/专科医院/.test(typeText)) {
    score -= 40;
  }
  if (/妇幼保健院|儿童医院/.test(text)) {
    score -= 20;
  }
  if (/街道|社区/.test(text)) {
    score -= 20;
  }

  score -= getWeakGenericHospitalPenalty(text, typeText);

  return score;
}

async function resolveCandidateHospitalsAdaptive(lng, lat, addressInfo, fallbackHospitals = []) {
  const searchPlans = [
    {
      keywords: [
        '\u4e09\u7ea7\u7532\u7b49\u533b\u9662',
        '\u7efc\u5408\u533b\u9662',
        '\u4eba\u6c11\u533b\u9662',
        '\u4e2d\u5fc3\u533b\u9662',
        '\u9644\u5c5e\u533b\u9662',
        '\u603b\u533b\u9662',
      ],
      radii: [10000, 30000, 50000],
    },
  ];

  let nearbyHospitals = [];

  for (const plan of searchPlans) {
    for (const radius of plan.radii) {
      try {
        const result = await searchNearbyHospitalsWithAMap(lng, lat, {
          radius,
          pageSize: 20,
          keywords: plan.keywords,
        });

        if (Array.isArray(result) && result.length > 0) {
          nearbyHospitals = mergeHospitalCandidates(nearbyHospitals, result);
          if (nearbyHospitals.filter((item) => isUsableHospitalCandidate(item)).length >= 3) {
            break;
          }
        }
      } catch (err) {
        if (DEBUG_MODE) {
          console.warn(`[RescuePlanner] adaptive hospital search: ${err.message}`);
        }
      }
    }

    if (nearbyHospitals.filter((item) => isUsableHospitalCandidate(item)).length > 0) {
      break;
    }
  }

  if (nearbyHospitals.filter((item) => isUsableHospitalCandidate(item)).length < 3) {
    try {
      const keywordHospitals = await searchHospitalsByKeywordWithAMap(lng, lat, {
        district: addressInfo?.addressComponent?.district || '',
        city: addressInfo?.addressComponent?.city || addressInfo?.addressComponent?.province || '',
        pageSize: 10,
        maxPages: 2,
        maxDistanceMeters: 50000,
        keywords: [
          '\u4e09\u7ea7\u7532\u7b49\u533b\u9662',
          '\u4eba\u6c11\u533b\u9662',
          '\u4e2d\u5fc3\u533b\u9662',
          '\u9644\u5c5e\u533b\u9662',
          '\u603b\u533b\u9662',
          '\u7efc\u5408\u533b\u9662',
          '\u6025\u6551\u4e2d\u5fc3',
        ],
      });

      if (Array.isArray(keywordHospitals) && keywordHospitals.length > 0) {
        nearbyHospitals = mergeHospitalCandidates(nearbyHospitals, keywordHospitals);
      }
    } catch (err) {
      if (DEBUG_MODE) {
        console.warn(`[RescuePlanner] keyword hospital search: ${err.message}`);
      }
    }
  }

  return buildCandidateHospitals(
    addressInfo,
    fallbackHospitals,
    prioritizeMajorHospitals(nearbyHospitals),
  );
}

function mergeHospitalCandidates(existing, incoming) {
  const merged = [...(Array.isArray(existing) ? existing : [])];
  const seen = new Set(
    merged.map((item) => `${item.name || ''}:${item.location?.[0] || item.lng}:${item.location?.[1] || item.lat}`),
  );

  for (const item of Array.isArray(incoming) ? incoming : []) {
    const key = `${item.name || ''}:${item.location?.[0] || item.lng}:${item.location?.[1] || item.lat}`;
    if (seen.has(key)) {
      continue;
    }

    seen.add(key);
    merged.push(item);
  }

  return merged;
}

function prioritizeMajorHospitals(hospitals) {
  const scored = [...(Array.isArray(hospitals) ? hospitals : [])]
    .map((hospital) => ({
      ...hospital,
      emergencyScore: getEmergencyHospitalScore(
        hospital?.institutionName || hospital?.name || '',
        hospital?.type || '',
      ),
      strongSignal: hasStrongEmergencySignal(
        hospital?.institutionName || hospital?.name || '',
        hospital?.type || '',
      ),
    }))
    .filter((hospital) => Number.isFinite(hospital.emergencyScore) && hospital.emergencyScore > 20);

  const strong = scored.filter((hospital) => hospital.strongSignal || hospital.emergencyScore >= 120);
  const usable = strong.length > 0 ? strong : scored.filter((hospital) => hospital.emergencyScore > 0);
  const pool = usable.length > 0 ? usable : scored;

  return pool.sort((a, b) => {
    if (a.strongSignal !== b.strongSignal) {
      return Number(b.strongSignal) - Number(a.strongSignal);
    }

    if (a.emergencyScore !== b.emergencyScore) {
      return b.emergencyScore - a.emergencyScore;
    }

    return (a?.distance || a?.approxDistance || Infinity) - (b?.distance || b?.approxDistance || Infinity);
  });
}

function rankHospitalsForPatient(hospitals, sosRecord) {
  const age = parsePatientAge(sosRecord?.medicalProfile?.age);

  return [...(Array.isArray(hospitals) ? hospitals : [])].sort((a, b) => {
    return compareHospitalsForDispatch(
      {
        ...a,
        emergencyScore: getEmergencyHospitalScore(a?.institutionName || a?.name || '', a?.type || ''),
        strongSignal: hasStrongEmergencySignal(a?.institutionName || a?.name || '', a?.type || ''),
        specialtyPenalty: getHospitalSpecialtyPenalty(a?.institutionName || a?.name || '', age),
      },
      {
        ...b,
        emergencyScore: getEmergencyHospitalScore(b?.institutionName || b?.name || '', b?.type || ''),
        strongSignal: hasStrongEmergencySignal(b?.institutionName || b?.name || '', b?.type || ''),
        specialtyPenalty: getHospitalSpecialtyPenalty(b?.institutionName || b?.name || '', age),
      },
    );
  });
}

function parsePatientAge(ageValue) {
  const match = String(ageValue || '').match(/\d+/);
  return match ? Number(match[0]) : null;
}

function getHospitalSpecialtyPenalty(name, age) {
  const text = String(name || '');
  const isChildHospital = text.includes('\u513f\u7ae5\u533b\u9662');
  const isWomenChildrenHospital = text.includes('\u5987\u5e7c\u4fdd\u5065\u9662');

  if (age == null) {
    if (isChildHospital) {
      return 120;
    }
    if (isWomenChildrenHospital) {
      return 25;
    }
    return 0;
  }

  if (age >= 16 && isChildHospital) {
    return 180;
  }

  if (age >= 16 && isWomenChildrenHospital) {
    return 35;
  }

  if (age < 16 && isChildHospital) {
    return -80;
  }

  if (age < 16 && isWomenChildrenHospital) {
    return -15;
  }

  return 0;
}

function compareHospitalsForDispatch(a, b) {
  const aStrong = !!a?.strongSignal;
  const bStrong = !!b?.strongSignal;
  const aScore = Number.isFinite(a?.emergencyScore) ? a.emergencyScore : Number.NEGATIVE_INFINITY;
  const bScore = Number.isFinite(b?.emergencyScore) ? b.emergencyScore : Number.NEGATIVE_INFINITY;
  const aPenalty = Number.isFinite(a?.specialtyPenalty) ? a.specialtyPenalty : 0;
  const bPenalty = Number.isFinite(b?.specialtyPenalty) ? b.specialtyPenalty : 0;
  const aHasError = !!a?.error;
  const bHasError = !!b?.error;
  const aDistance = a?.distance ?? a?.approxDistance ?? Infinity;
  const bDistance = b?.distance ?? b?.approxDistance ?? Infinity;

  if (aStrong !== bStrong) {
    return Number(bStrong) - Number(aStrong);
  }

  if (aScore !== bScore) {
    return bScore - aScore;
  }

  if (aPenalty !== bPenalty) {
    return aPenalty - bPenalty;
  }

  if (aHasError !== bHasError) {
    return Number(aHasError) - Number(bHasError);
  }

  return aDistance - bDistance;
}

function isUsableRescueTeamCandidate(poi = {}) {
  const text = `${String(poi?.name || '').trim()} ${String(poi?.type || '').trim()}`;
  if (!text.trim()) {
    return false;
  }

  if (/美容|宠物|汽修|洗车|汽车维修|汽车救援|拖车|轮胎|保养|口腔门诊|诊所|药店|体检|健康管理/.test(text)) {
    return false;
  }

  return /120急救中心|急救中心|急救站|消防救援站|消防站|派出所|公安局|应急救援|医院急诊|急诊科/.test(text);
}

function normalizeRescueTeamCandidate(poi, source = 'search_api') {
  const location = Array.isArray(poi?.location) ? poi.location : [];
  const lng = Number(location[0] ?? poi?.lng);
  const lat = Number(location[1] ?? poi?.lat);
  const name = String(poi?.name || '').trim();

  if (!Number.isFinite(lng) || !Number.isFinite(lat) || !name) {
    return null;
  }

  return {
    name,
    lng,
    lat,
    source,
    approxDistance: poi?.distance ?? poi?.approxDistance ?? null,
    address: poi?.address || '',
    type: poi?.type || '',
  };
}

function hasStrongRescueSignal(name, type = '') {
  const text = `${String(name || '').trim()} ${String(type || '').trim()}`;
  return /120急救中心|急救中心|急救站|消防救援站|消防站|派出所|公安局/.test(text);
}

function getRescueTeamScore(name, type = '', sosRecord = {}) {
  const text = `${String(name || '').trim()} ${String(type || '').trim()}`;
  if (!text.trim() || !isUsableRescueTeamCandidate({ name, type })) {
    return Number.NEGATIVE_INFINITY;
  }

  let score = 0;
  if (/120急救中心|急救中心|急救站/.test(text)) score += 240;
  if (/消防救援站|消防站/.test(text)) score += 220;
  if (/派出所|公安局/.test(text)) score += 180;
  if (/应急救援/.test(text)) score += 160;
  if (/医院急诊|急诊科/.test(text)) score += 130;
  if (/三级甲等医院|三级医院/.test(text)) score += 60;

  const severity = sosRecord?.priority?.severityLevel || '';
  if (severity === 'critical' && /120急救中心|急救中心|急救站|医院急诊|急诊科/.test(text)) {
    score += 70;
  }
  if (severity === 'critical' && /消防救援站|消防站/.test(text)) {
    score += 35;
  }

  return score;
}

function compareRescueTeamsForDispatch(a, b) {
  const aStrong = !!a?.strongSignal;
  const bStrong = !!b?.strongSignal;
  const aScore = Number.isFinite(a?.rescueScore) ? a.rescueScore : Number.NEGATIVE_INFINITY;
  const bScore = Number.isFinite(b?.rescueScore) ? b.rescueScore : Number.NEGATIVE_INFINITY;
  const aHasError = !!a?.error;
  const bHasError = !!b?.error;
  const aDistance = a?.distance ?? a?.approxDistance ?? Infinity;
  const bDistance = b?.distance ?? b?.approxDistance ?? Infinity;

  if (aStrong !== bStrong) {
    return Number(bStrong) - Number(aStrong);
  }
  if (aScore !== bScore) {
    return bScore - aScore;
  }
  if (aHasError !== bHasError) {
    return Number(aHasError) - Number(bHasError);
  }
  return aDistance - bDistance;
}

function prioritizeRescueTeams(teams, sosRecord) {
  return [...(Array.isArray(teams) ? teams : [])]
    .map((team) => ({
      ...team,
      rescueScore: getRescueTeamScore(team?.name || '', team?.type || '', sosRecord),
      strongSignal: hasStrongRescueSignal(team?.name || '', team?.type || ''),
    }))
    .filter((team) => Number.isFinite(team.rescueScore) && team.rescueScore > 0)
    .sort(compareRescueTeamsForDispatch);
}

function mergeRescueTeamCandidates(primaryTeams = [], fallbackTeams = []) {
  const merged = [];
  const seen = new Set();

  for (const team of [...primaryTeams, ...fallbackTeams]) {
    if (!team || typeof team.lng !== 'number' || typeof team.lat !== 'number') {
      continue;
    }
    const key = `${team.name || ''}:${team.lng.toFixed(5)},${team.lat.toFixed(5)}`;
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    merged.push(team);
  }

  return merged;
}

async function resolveCandidateRescueTeamsAdaptive(lng, lat, addressInfo, fallbackTeams = []) {
  const searchPlans = [
    {
      keywords: [
        '\u0031\u0032\u0030\u6025\u6551\u4e2d\u5fc3',
        '\u6025\u6551\u4e2d\u5fc3',
        '\u6025\u6551\u7ad9',
        '\u6d88\u9632\u6551\u63f4\u7ad9',
        '\u6d88\u9632\u7ad9',
        '\u6d3e\u51fa\u6240',
        '\u516c\u5b89\u5c40',
      ],
      radii: [10000, 30000, 50000],
    },
    {
      keywords: [
        '\u5e94\u6025\u6551\u63f4',
        '\u533b\u9662\u6025\u8bca',
      ],
      radii: [10000, 30000, 50000],
    },
  ];

  let nearbyTeams = [];
  for (const plan of searchPlans) {
    for (const radius of plan.radii) {
      try {
        const result = await searchNearbyRescueTeamsWithAMap(lng, lat, {
          radius,
          pageSize: 20,
          keywords: plan.keywords,
        });

        const normalized = result
          .filter((poi) => isUsableRescueTeamCandidate(poi))
          .map((poi) => normalizeRescueTeamCandidate(poi, 'nearby_api'))
          .filter(Boolean);

        nearbyTeams = mergeRescueTeamCandidates(nearbyTeams, normalized);
        if (nearbyTeams.length >= 6) {
          break;
        }
      } catch (err) {
        console.warn(`[RescuePlanner] nearby rescue team search failed (${radius}m): ${err.message}`);
      }
    }
    if (nearbyTeams.length >= 6) {
      break;
    }
  }

  let keywordTeams = [];
  try {
    const result = await searchRescueTeamsByKeywordWithAMap(lng, lat, {
      district: addressInfo?.addressComponent?.district || '',
      city: addressInfo?.addressComponent?.city || addressInfo?.addressComponent?.province || '',
      pageSize: 10,
      maxPages: 2,
      maxDistanceMeters: 50000,
    });
    keywordTeams = result
      .filter((poi) => isUsableRescueTeamCandidate(poi))
      .map((poi) => normalizeRescueTeamCandidate(poi, 'search_api'))
      .filter(Boolean);
  } catch (err) {
    console.warn(`[RescuePlanner] keyword rescue team search failed: ${err.message}`);
  }

  const sanitizedFallbacks = (Array.isArray(fallbackTeams) ? fallbackTeams : [])
    .map((team) => normalizeRescueTeamCandidate(team, 'manual'))
    .filter(Boolean);

  return mergeRescueTeamCandidates(nearbyTeams, [...keywordTeams, ...sanitizedFallbacks]);
}

function buildRescueDispatchRecommendations(sosRecord, nearestTeam, addressInfo) {
  const lines = [];
  if (nearestTeam?.name) {
    lines.push(`优先由${nearestTeam.name}赶赴现场。`);
  }
  if (addressInfo?.formattedAddress) {
    lines.push(`目标位置：${addressInfo.formattedAddress}。`);
  }
  if ((sosRecord?.priority?.severityLevel || '') === 'critical') {
    lines.push('当前对象为 critical，建议立即出动并同步上报指挥席。');
  }
  return lines;
}

function generateBatchSummary(sequence) {
  const severityCounts = {
    critical: 0,
    urgent: 0,
    warning: 0,
    normal: 0,
  };
  
  sequence.forEach(item => {
    const level = item.priority?.severityLevel || 'normal';
    if (severityCounts.hasOwnProperty(level)) {
      severityCounts[level]++;
    }
  });
  
  return {
    severityDistribution: severityCounts,
    averageDistanceKm: (sequence.reduce((sum, item) => 
      sum + parseFloat(item.route?.distanceKm || 0), 0) / sequence.length).toFixed(2),
    criticalFirst: sequence.findIndex(item => item.priority?.severityLevel === 'critical') + 1,
  };
}

module.exports = {
  generateSingleRescuePlan,
  generateNearestRescueTeamPlan,
  optimizeBatchRescue,
  generateAiRecommendations,
  getBloodTypeName,
};
