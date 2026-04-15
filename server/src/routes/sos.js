const express = require('express');
const router = express.Router();
const SosRecord = require('../models/SosRecord');
const socketService = require('../socket');
const { rankSosList, detectRiskAreas } = require('../utils/priorityEngine');
const { generateSituationReport, answerQuestion } = require('../services/llmService');
const { generateSingleRescuePlan, generateNearestRescueTeamPlan, optimizeBatchRescue } = require('../services/rescuePlannerService');
const {
  reverseGeocode,
  searchNearbyHospitalsWithAMap,
  searchHospitalsByKeywordWithAMap,
  searchNearbyRescueTeamsWithAMap,
  searchRescueTeamsByKeywordWithAMap,
} = require('../services/geocodingService');
const { wgs84ToGcj02 } = require('../utils/coordTransform');

// 去重时间容差：10 分钟（毫秒）
const DEDUP_WINDOW_MS = 10 * 60 * 1000;

/**
 * POST /api/sos/sync
 *
 * "数据骡子"恢复网络后批量上传暂存的 SOS 信号。
 *
 * 请求体示例：
 * {
 *   "muleId": "AA:BB:CC:DD:EE:FF",        // 骡子自身 MAC
 *   "records": [
 *     {
 *       "senderMac": "11:22:33:44:55:66",
 *       "longitude": 116.3974,
 *       "latitude":  39.9093,
 *       "bloodType": 0,
 *       "timestamp": "2024-06-15T08:30:00.000Z",
 *       "medicalProfile": {              // 可选：个人医疗档案
 *         "name": "张三",
 *         "age": "28",
 *         "bloodTypeDetail": 3,
 *         "medicalHistory": "无重大疾病",
 *         "allergies": "青霉素",
 *         "emergencyContact": "138-XXXX-1234"
 *       }
 *     },
 *     ...
 *   ]
 * }
 *
 * 响应体：
 * {
 *   "created": 3,    // 新插入条数
 *   "merged":  2,    // 已存在、仅追加骡子 ID 的条数
 *   "invalid": 1,    // 解析/校验失败条数
 *   "details": [...]  // 每条记录的处理结果
 * }
 */
router.post('/sync', async (req, res) => {
  const { muleId, records } = req.body;

  // ── 基础校验 ──────────────────────────────────────────────
  if (!muleId || typeof muleId !== 'string') {
    return res.status(400).json({ error: 'muleId 为必填字符串' });
  }
  if (!Array.isArray(records) || records.length === 0) {
    return res.status(400).json({ error: 'records 必须为非空数组' });
  }
  if (records.length > 1000) {
    return res.status(400).json({ error: '单次上传不得超过 1000 条' });
  }

  const normalizedMuleId = muleId.toUpperCase().trim();
  const details = [];
  let created = 0, merged = 0, invalid = 0;

  // ── 逐条处理（串行保证同一批次内不会互相重复插入）──────────
  for (const raw of records) {
    try {
      const record = normalizeRecord(raw);   // 标准化并校验字段
      const medicalProfile = raw.medicalProfile || {}; // 提取医疗档案
      const result = await upsertSosRecord(record, normalizedMuleId, medicalProfile);

      if (result.action === 'created') {
        created++;
        // 立刻广播新 SOS 到前端大屏
        socketService.broadcastNewSos(result.doc);
      } else {
        merged++;
      }

      details.push({
        senderMac: record.senderMac,
        action: result.action,
        id: result.doc._id,
      });
    } catch (err) {
      invalid++;
      details.push({ raw, action: 'invalid', reason: err.message });
    }
  }

  return res.status(200).json({ created, merged, invalid, details });
});

/**
 * GET /api/sos/active
 *
 * 返回所有 status === 'active' 的求救点，供大屏初次渲染地图使用。
 * 按 timestamp 降序（最新的排在前面）。
 */
router.get('/active', async (req, res) => {
  try {
    const activeSos = await SosRecord.find({ status: 'active' })
      .sort({ timestamp: -1 })
      .lean({ virtuals: true }); // lean 提升读性能，virtuals:true 保留 confidence

    return res.status(200).json({
      count: activeSos.length,
      data: activeSos,
    });
  } catch (err) {
    console.error('[GET /active]', err);
    return res.status(500).json({ error: '服务器内部错误' });
  }
});

/**
 * GET /api/sos/hourly-stats
 *
 * 返回过去 12 小时每小时的 SOS 信号数量，供大屏趋势折线图使用。
 * 返回数组长度为 12，索引 0 = 11 小时前，索引 11 = 当前小时。
 */
router.get('/hourly-stats', async (req, res) => {
  try {
    const now = new Date();
    const twelveHoursAgo = new Date(now.getTime() - 12 * 60 * 60 * 1000);

    // MongoDB 聚合：按小时分组统计
    const pipeline = [
      { $match: { timestamp: { $gte: twelveHoursAgo, $lte: now } } },
      {
        $group: {
          _id: {
            $dateToString: { format: '%Y-%m-%d %H', date: '$timestamp' },
          },
          count: { $sum: 1 },
        },
      },
      { $sort: { _id: 1 } },
    ];

    const aggResult = await SosRecord.aggregate(pipeline);

    // 构建 12 个连续小时的映射
    const hourMap = {};
    for (let i = 0; i < 12; i++) {
      const h = new Date(now.getTime() - (11 - i) * 60 * 60 * 1000);
      const key = `${h.getFullYear()}-${String(h.getMonth() + 1).padStart(2, '0')}-${String(h.getDate()).padStart(2, '0')} ${String(h.getHours()).padStart(2, '0')}`;
      hourMap[key] = 0;
    }

    // 填入聚合结果
    for (const row of aggResult) {
      if (hourMap.hasOwnProperty(row._id)) {
        hourMap[row._id] = row.count;
      }
    }

    // 转为数组（索引 0 = 11 小时前，索引 11 = 当前小时）
    const hourlyData = Object.values(hourMap);

    return res.status(200).json({ data: hourlyData });
  } catch (err) {
    console.error('[GET /hourly-stats]', err);
    return res.status(500).json({ error: '服务器内部错误' });
  }
});

/**
 * GET /api/sos/ai/priorities
 *
 * AI辅助决策 - 获取按优先级排序的求救列表
 * 返回带有优先级评分、严重等级、等待时长的完整排序列表
 */
router.get('/ai/priorities', async (req, res) => {
  try {
    const activeSos = await SosRecord.find({ status: 'active' })
      .sort({ timestamp: -1 })
      .lean({ virtuals: true });

    const ranked = rankSosList(activeSos);

    // 统计各级别数量
    const summary = {
      total: ranked.length,
      critical: ranked.filter(r => r.priority.severityLevel === 'critical').length,
      urgent: ranked.filter(r => r.priority.severityLevel === 'urgent').length,
      warning: ranked.filter(r => r.priority.severityLevel === 'warning').length,
      normal: ranked.filter(r => r.priority.severityLevel === 'normal').length,
    };

    return res.status(200).json({ data: ranked, summary });
  } catch (err) {
    console.error('[GET /ai/priorities]', err);
    return res.status(500).json({ error: '服务器内部错误' });
  }
});

/**
 * GET /api/sos/ai/risk-areas
 *
 * AI辅助决策 - 检测风险聚集区域
 * 返回基于地理聚类的风险区域列表
 */
router.get('/ai/risk-areas', async (req, res) => {
  try {
    const activeSos = await SosRecord.find({ status: 'active' })
      .lean({ virtuals: true });

    const riskAreas = detectRiskAreas(activeSos, {
      radiusKm: 5,
      minCount: 3,
      timeWindowMin: 60,
    });

    return res.status(200).json({ data: riskAreas });
  } catch (err) {
    console.error('[GET /ai/risk-areas]', err);
    return res.status(500).json({ error: '服务器内部错误' });
  }
});

/**
 * GET /api/sos/ai/situation-report
 *
 * AI辅助决策 - 生成态势摘要
 * 返回结构化的灾情概况，可用于LLM生成自然语言摘要
 */
router.get('/ai/situation-report', async (req, res) => {
  try {
    const activeSos = await SosRecord.find({ status: 'active' })
      .lean({ virtuals: true });

    const ranked = rankSosList(activeSos);

    // 基本信息
    const total = ranked.length;
    const criticalMembers = ranked.filter(r => r.priority.severityLevel === 'critical');
    const urgentMembers = ranked.filter(r => r.priority.severityLevel === 'urgent');

    // 血型分布
    const bloodDist = {};
    ranked.forEach(r => {
      const bt = String(r.bloodType ?? -1);
      bloodDist[bt] = (bloodDist[bt] || 0) + 1;
    });

    // 地理分布（按省份粗略统计）
    const provinceDist = {};
    ranked.forEach(r => {
      const lng = r.location.coordinates[0];
      const lat = r.location.coordinates[1];
      const province = coordsToProvince(lng, lat);
      provinceDist[province] = (provinceDist[province] || 0) + 1;
    });

    // 按数量排序
    const sortedProvinces = Object.entries(provinceDist)
      .sort((a, b) => b[1] - a[1])
      .map(([name, count]) => ({ name, count }));

    // 等待时间最长的前5名
    const longestWaiting = ranked
      .filter(r => r.priority.elapsedMin > 0)
      .sort((a, b) => b.priority.elapsedMin - a.priority.elapsedMin)
      .slice(0, 5)
      .map(r => ({
        mac: r.senderMac,
        elapsedMin: r.priority.elapsedMin,
        severityLevel: r.priority.severityLevel,
        medicalHistory: r.medicalProfile?.medicalHistory || '无',
        allergies: r.medicalProfile?.allergies || '无',
      }));

    return res.status(200).json({
      data: {
        total,
        criticalCount: criticalMembers.length,
        urgentCount: urgentMembers.length,
        bloodDistribution: bloodDist,
        provinceDistribution: sortedProvinces,
        longestWaiting,
        topPriorities: ranked.slice(0, 5).map(r => ({
          mac: r.senderMac,
          score: r.priority.score,
          severityLevel: r.priority.severityLevel,
          breakdown: r.priority.breakdown,
          medicalHistory: r.medicalProfile?.medicalHistory || '无',
          allergies: r.medicalProfile?.allergies || '无',
          elapsedMin: r.priority.elapsedMin,
          location: r.location.coordinates,
        })),
      },
    });
  } catch (err) {
    console.error('[GET /ai/situation-report]', err);
    return res.status(500).json({ error: '服务器内部错误' });
  }
});

/**
 * POST /api/sos/ai/generate-report
 * 使用 LLM 生成自然语言态势摘要
 */
router.post('/ai/generate-report', async (req, res) => {
  try {
    const { reportData } = req.body;
    if (!reportData) {
      return res.status(400).json({ error: '缺少 reportData 参数' });
    }
    const summary = await generateSituationReport(reportData);
    return res.status(200).json({ data: { summary } });
  } catch (err) {
    console.error('[POST /ai/generate-report]', err);
    return res.status(500).json({ error: err.message });
  }
});

/**
 * POST /api/sos/ai/chat
 * 智能问答接口
 */
router.post('/ai/chat', async (req, res) => {
  try {
    const { question, contextData, chatHistory, intentHint, targetMac } = req.body;
    if (!question) {
      return res.status(400).json({ error: '缺少 question 参数' });
    }
    const activeSos = await SosRecord.find({ status: 'active' })
      .sort({ timestamp: -1 })
      .lean({ virtuals: true });
    const ranked = rankSosList(activeSos);
    const chatContext = await buildChatContext(question, ranked, {
      ...(contextData || {}),
      chatHistory: Array.isArray(chatHistory) ? chatHistory : [],
      intentHint: typeof intentHint === 'string' ? intentHint : '',
      targetMac: typeof targetMac === 'string' ? targetMac : '',
    });
    const answer = await answerQuestion(question, chatContext);
    return res.status(200).json({ data: { answer, routeOverlay: buildRouteOverlay(chatContext) } });
  } catch (err) {
    console.error('[POST /ai/chat]', err);
    return res.status(500).json({ error: err.message });
  }
});

router.get('/ai/debug-hospitals/:mac', async (req, res) => {
  try {
    const { mac } = req.params;
    const sosRecord = await SosRecord.findOne({
      senderMac: mac.toUpperCase(),
      status: 'active',
    }).lean({ virtuals: true });

    if (!sosRecord) {
      return res.status(404).json({ error: '未找到活跃求救记录' });
    }

    const [lng, lat] = sosRecord.location?.coordinates || [];
    if (!Number.isFinite(lng) || !Number.isFinite(lat)) {
      return res.status(400).json({ error: '求救记录缺少有效坐标' });
    }

    const address = await reverseGeocode(lng, lat);
    const searchPlans = [
      {
        label: 'major',
        keywords: [
          '\u4eba\u6c11\u533b\u9662',
          '\u4e2d\u5fc3\u533b\u9662',
          '\u9644\u5c5e\u533b\u9662',
          '\u603b\u533b\u9662',
          '\u4e09\u7532\u533b\u9662',
        ],
        radii: [8000, 15000, 30000, 50000],
      },
      {
        label: 'generic',
        keywords: [
          '\u533b\u9662',
          '\u6025\u6551\u4e2d\u5fc3',
          '\u533b\u7597\u4e2d\u5fc3',
        ],
        radii: [8000, 15000, 30000, 50000],
      },
    ];

    const probes = [];
    for (const plan of searchPlans) {
      for (const radius of plan.radii) {
        for (const keyword of plan.keywords) {
          try {
            const pois = await searchNearbyHospitalsWithAMap(lng, lat, {
              radius,
              pageSize: 10,
              keywords: [keyword],
            });

            probes.push({
              group: plan.label,
              keyword,
              radius,
              count: pois.length,
              hospitals: pois.slice(0, 5).map((poi) => ({
                name: poi.name,
                distance: poi.distance,
                type: poi.type,
                address: poi.address,
                location: poi.location,
              })),
            });
          } catch (error) {
            probes.push({
              group: plan.label,
              keyword,
              radius,
              error: error.message,
            });
          }
        }
      }
    }

    const keywordProbes = [];
    const keywordSearchTerms = [
      '\u4e09\u7ea7\u7532\u7b49\u533b\u9662',
      '\u4eba\u6c11\u533b\u9662',
      '\u4e2d\u5fc3\u533b\u9662',
      '\u9644\u5c5e\u533b\u9662',
      '\u603b\u533b\u9662',
      '\u7efc\u5408\u533b\u9662',
      '\u6025\u6551\u4e2d\u5fc3',
    ];
    try {
      const pois = await searchHospitalsByKeywordWithAMap(lng, lat, {
        district: address?.addressComponent?.district || '',
        city: address?.addressComponent?.city || address?.addressComponent?.province || '',
        pageSize: 10,
        maxPages: 2,
        maxDistanceMeters: 50000,
        keywords: keywordSearchTerms,
      });

      keywordProbes.push({
        count: pois.length,
        hospitals: pois.slice(0, 10).map((poi) => ({
          name: poi.name,
          approxDistance: poi.approxDistance,
          type: poi.type,
          address: poi.address,
          location: poi.location,
        })),
      });
    } catch (error) {
      keywordProbes.push({
        error: error.message,
      });
    }

    const ranked = rankSosList([sosRecord]);
    sosRecord.priority = ranked[0]?.priority || null;
    const plan = await generateSingleRescuePlan(sosRecord);
    const routeAnchorDebug = buildRouteAnchorDebug(plan);

    return res.status(200).json({
      data: {
        mac: sosRecord.senderMac,
        coordinates: [lng, lat],
        address: {
          formattedAddress: address?.formattedAddress || '',
          addressComponent: address?.addressComponent || {},
          pois: (address?.pois || []).slice(0, 5),
        },
        probes,
        keywordProbes,
        routeAnchorDebug,
        finalPlan: {
          route: plan.route,
          recommendedHospitals: plan.recommendedHospitals,
        },
      },
    });
  } catch (err) {
    console.error('[GET /ai/debug-hospitals]', err);
    return res.status(500).json({ error: err.message });
  }
});

router.get('/ai/debug-rescue-teams/:mac', async (req, res) => {
  try {
    const { mac } = req.params;
    const sosRecord = await SosRecord.findOne({
      senderMac: mac.toUpperCase(),
      status: 'active',
    }).lean({ virtuals: true });

    if (!sosRecord) {
      return res.status(404).json({ error: 'active sos record not found' });
    }

    const [lng, lat] = sosRecord.location?.coordinates || [];
    if (!Number.isFinite(lng) || !Number.isFinite(lat)) {
      return res.status(400).json({ error: 'invalid sos coordinates' });
    }

    const address = await reverseGeocode(lng, lat);
    const searchPlans = [
      {
        label: 'primary_rescue',
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
        label: 'fallback_rescue',
        keywords: [
          '\u5e94\u6025\u6551\u63f4',
          '\u533b\u9662\u6025\u8bca',
          '\u6025\u8bca\u79d1',
        ],
        radii: [10000, 30000, 50000],
      },
    ];

    const probes = [];
    for (const plan of searchPlans) {
      for (const radius of plan.radii) {
        for (const keyword of plan.keywords) {
          try {
            const pois = await searchNearbyRescueTeamsWithAMap(lng, lat, {
              radius,
              pageSize: 10,
              keywords: [keyword],
            });

            probes.push({
              group: plan.label,
              keyword,
              radius,
              count: pois.length,
              rescueTeams: pois.slice(0, 5).map((poi) => ({
                name: poi.name,
                distance: poi.distance,
                type: poi.type,
                address: poi.address,
                location: poi.location,
              })),
            });
          } catch (error) {
            probes.push({
              group: plan.label,
              keyword,
              radius,
              error: error.message,
            });
          }
        }
      }
    }

    const keywordProbes = [];
    const keywordSearchTerms = [
      '\u0031\u0032\u0030\u6025\u6551\u4e2d\u5fc3',
      '\u6025\u6551\u4e2d\u5fc3',
      '\u6025\u6551\u7ad9',
      '\u6d88\u9632\u6551\u63f4\u7ad9',
      '\u6d88\u9632\u7ad9',
      '\u6d3e\u51fa\u6240',
      '\u516c\u5b89\u5c40',
      '\u5e94\u6025\u6551\u63f4',
      '\u533b\u9662\u6025\u8bca',
      '\u6025\u8bca\u79d1',
    ];
    try {
      const pois = await searchRescueTeamsByKeywordWithAMap(lng, lat, {
        district: address?.addressComponent?.district || '',
        city: address?.addressComponent?.city || address?.addressComponent?.province || '',
        pageSize: 10,
        maxPages: 2,
        maxDistanceMeters: 50000,
        keywords: keywordSearchTerms,
      });

      keywordProbes.push({
        count: pois.length,
        rescueTeams: pois.slice(0, 10).map((poi) => ({
          name: poi.name,
          approxDistance: poi.approxDistance,
          type: poi.type,
          address: poi.address,
          location: poi.location,
        })),
      });
    } catch (error) {
      keywordProbes.push({
        error: error.message,
      });
    }

    const ranked = rankSosList([sosRecord]);
    sosRecord.priority = ranked[0]?.priority || null;
    const plan = await generateNearestRescueTeamPlan(sosRecord);
    const routeAnchorDebug = buildRescueRouteAnchorDebug(plan);

    return res.status(200).json({
      data: {
        mac: sosRecord.senderMac,
        coordinates: [lng, lat],
        address: {
          formattedAddress: address?.formattedAddress || '',
          addressComponent: address?.addressComponent || {},
          pois: (address?.pois || []).slice(0, 5),
        },
        probes,
        keywordProbes,
        routeAnchorDebug,
        finalPlan: {
          route: plan.route,
          recommendedRescueTeams: plan.recommendedRescueTeams,
        },
      },
    });
  } catch (err) {
    console.error('[GET /ai/debug-rescue-teams]', err);
    return res.status(500).json({ error: err.message });
  }
});

/**
 * GET /api/sos/ai/rescue-plan/:mac
 *
 * AI辅助决策 - 获取指定求救者的完整救援计划
 * 包含：详细地址、路线规划、医疗建议、推荐医院
 * 
 * 查询参数：
 * - hospitalLng: 医院经度（可选，默认使用配置的默认医院）
 * - hospitalLat: 医院纬度（可选）
 * - hospitalName: 医院名称（可选）
 */
router.get('/ai/rescue-plan/:mac', async (req, res) => {
  try {
    const { mac } = req.params;
    const { hospitalLng, hospitalLat, hospitalName } = req.query;
    
    // 查询求救记录
    const sosRecord = await SosRecord.findOne({ 
      senderMac: mac.toUpperCase(),
      status: 'active' 
    }).lean({ virtuals: true });
    
    if (!sosRecord) {
      return res.status(404).json({ error: '未找到活跃的求救记录' });
    }
    
    // 重新计算优先级
    const ranked = rankSosList([sosRecord]);
    sosRecord.priority = ranked[0]?.priority || null;
    
    // 构建医院列表
    let hospitals = [];
    if (hospitalLng && hospitalLat) {
      // 使用指定的医院
      hospitals.push({
        name: hospitalName || '指定医院',
        lng: parseFloat(hospitalLng),
        lat: parseFloat(hospitalLat),
      });
    }
    // 如果未指定，rescuePlannerService会使用DEFAULT_HOSPITALS
    
    // 生成救援计划
    const plan = await generateSingleRescuePlan(sosRecord, hospitals.length > 0 ? hospitals : undefined);
    
    return res.status(200).json({ data: plan });
  } catch (err) {
    console.error('[GET /ai/rescue-plan]', err);
    return res.status(500).json({ error: err.message });
  }
});

/**
 * POST /api/sos/ai/batch-rescue-plan
 *
 * AI辅助决策 - 批量救援计划优化
 * 输入：多个求救者MAC列表 + 出发点（医院/救援队位置）
 * 输出：最优救援顺序 + 预计总耗时
 * 
 * 请求体：
 * {
 *   "macs": ["AA:BB:CC:DD:EE:FF", ...],  // MAC地址数组
 *   "originLng": 116.397,                  // 出发点经度
 *   "originLat": 39.918,                   // 出发点纬度
 *   "originName": "市第一人民医院",         // 出发点名称（可选）
 *   "optimizationStrategy": "efficiency"  // 优化策略: efficiency|urgency|distance
 * }
 */
router.post('/ai/batch-rescue-plan', async (req, res) => {
  try {
    const { macs, originLng, originLat, originName, optimizationStrategy } = req.body;
    
    if (!Array.isArray(macs) || macs.length === 0) {
      return res.status(400).json({ error: '请提供有效的MAC地址列表' });
    }
    
    if (!originLng || !originLat) {
      return res.status(400).json({ error: '请提供出发点坐标 (originLng, originLat)' });
    }
    
    // 查询所有求救记录
    const sosRecords = await SosRecord.find({
      senderMac: { $in: macs.map(m => m.toUpperCase()) },
      status: 'active',
    }).lean({ virtuals: true });
    
    if (sosRecords.length === 0) {
      return res.status(404).json({ error: '未找到任何活跃的求救记录' });
    }
    
    // 重新计算优先级
    const ranked = rankSosList(sosRecords);
    
    // 优化救援顺序
    const optimization = await optimizeBatchRescue(
      ranked,
      {
        lng: parseFloat(originLng),
        lat: parseFloat(originLat),
        name: originName || '出发点',
      },
      {
        optimizationStrategy: optimizationStrategy || 'efficiency',
      }
    );
    
    return res.status(200).json({ data: optimization });
  } catch (err) {
    console.error('[POST /ai/batch-rescue-plan]', err);
    return res.status(500).json({ error: err.message });
  }
});

// ════════════════════════════════════════════════════════════
//  工具函数
// ════════════════════════════════════════════════════════════

/**
 * 射线法判断点是否在多边形内
 */
function pointInPolygon(lng, lat, polygon) {
  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const xi = polygon[i][0], yi = polygon[i][1];
    const xj = polygon[j][0], yj = polygon[j][1];
    const intersect = ((yi > lat) !== (yj > lat)) &&
      (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}

/**
 * 根据经纬度精确判断所属省份
 * 使用多边形边界 + 射线法，小省份优先匹配避免被大省份矩形吞没
 */
function coordsToProvince(lng, lat) {
  // 第一优先级：直辖市和小面积省份（用精确多边形，最先匹配）
  const smallProvinces = [
    { name: '北京', poly: [[115.4,39.4],[115.4,41.1],[117.5,41.1],[117.5,39.4]] },
    { name: '上海', poly: [[120.8,30.7],[120.8,31.9],[122.0,31.9],[122.0,30.7]] },
    { name: '天津', poly: [[116.7,38.5],[116.7,40.2],[118.0,40.2],[118.0,38.5]] },
    { name: '重庆', poly: [[105.2,28.2],[105.2,32.2],[110.2,32.2],[110.2,28.2]] },
    { name: '海南', poly: [[108.5,18.0],[108.5,20.3],[111.2,20.3],[111.2,18.0]] },
    { name: '宁夏', poly: [[104.0,35.0],[104.0,39.5],[107.5,39.5],[107.5,35.0]] },
  ];
  for (const p of smallProvinces) {
    if (pointInPolygon(lng, lat, p.poly)) return p.name;
  }

  // 第二优先级：其他省份（用矩形框，按从南到北、从东到西排序减少重叠干扰）
  const provinces = [
    { name: '广东', lngMin: 109.5, lngMax: 117.5, latMin: 20.0, latMax: 25.5 },
    { name: '广西', lngMin: 104.0, lngMax: 112.0, latMin: 20.5, latMax: 26.3 },
    { name: '福建', lngMin: 116.0, lngMax: 120.8, latMin: 23.5, latMax: 28.3 },
    { name: '台湾', lngMin: 119.5, lngMax: 122.0, latMin: 21.9, latMax: 25.3 },
    { name: '云南', lngMin: 97.5, lngMax: 106.2, latMin: 21.0, latMax: 29.2 },
    { name: '贵州', lngMin: 103.5, lngMax: 109.5, latMin: 24.5, latMax: 29.2 },
    { name: '湖南', lngMin: 108.7, lngMax: 114.3, latMin: 24.6, latMax: 30.1 },
    { name: '江西', lngMin: 113.5, lngMax: 118.5, latMin: 24.5, latMax: 30.1 },
    { name: '浙江', lngMin: 118.0, lngMax: 123.0, latMin: 27.0, latMax: 31.2 },
    { name: '江苏', lngMin: 116.3, lngMax: 121.9, latMin: 30.7, latMax: 35.1 },
    { name: '安徽', lngMin: 114.8, lngMax: 119.7, latMin: 29.4, latMax: 34.7 },
    { name: '湖北', lngMin: 108.4, lngMax: 116.1, latMin: 29.0, latMax: 33.3 },
    { name: '河南', lngMin: 110.3, lngMax: 116.7, latMin: 31.4, latMax: 36.4 },
    { name: '四川', lngMin: 97.3, lngMax: 108.5, latMin: 26.0, latMax: 34.3 },
    { name: '山东', lngMin: 114.8, lngMax: 122.7, latMin: 34.2, latMax: 38.3 },
    { name: '河北', lngMin: 113.3, lngMax: 119.9, latMin: 36.0, latMax: 42.7 },
    { name: '山西', lngMin: 110.1, lngMax: 114.6, latMin: 34.5, latMax: 40.8 },
    { name: '陕西', lngMin: 105.5, lngMax: 111.2, latMin: 31.7, latMax: 39.6 },
    { name: '甘肃', lngMin: 92.1, lngMax: 108.7, latMin: 32.5, latMax: 42.8 },
    { name: '青海', lngMin: 89.3, lngMax: 103.0, latMin: 31.5, latMax: 39.9 },
    { name: '西藏', lngMin: 78.4, lngMax: 99.1, latMin: 26.0, latMax: 36.5 },
    { name: '新疆', lngMin: 73.4, lngMax: 96.4, latMin: 34.2, latMax: 49.2 },
    { name: '辽宁', lngMin: 118.9, lngMax: 125.5, latMin: 38.7, latMax: 43.5 },
    { name: '吉林', lngMin: 121.6, lngMax: 131.2, latMin: 40.9, latMax: 46.2 },
    { name: '黑龙江', lngMin: 121.2, lngMax: 135.1, latMin: 43.4, latMax: 53.5 },
  ];

  for (const p of provinces) {
    if (lng >= p.lngMin && lng <= p.lngMax && lat >= p.latMin && lat <= p.latMax) {
      return p.name;
    }
  }

  // 第三优先级：内蒙古（最大省份，放最后避免吞没其他省份）
  if (lng >= 97.0 && lng <= 126.0 && lat >= 37.3 && lat <= 53.4) {
    return '内蒙古';
  }

  return '其他地区';
}

/**
 * 将请求体中的单条原始记录标准化为写入 DB 的格式。
 * 抛出 Error 表示校验失败。
 */
function normalizeRecord(raw) {
  const { senderMac, longitude, latitude, bloodType, timestamp } = raw;

  if (!senderMac || typeof senderMac !== 'string') {
    throw new Error('senderMac 缺失或类型错误');
  }
  const lon = parseFloat(longitude);
  const lat = parseFloat(latitude);
  if (isNaN(lon) || isNaN(lat)) {
    throw new Error('longitude / latitude 必须为数字');
  }
  if (lon < -180 || lon > 180 || lat < -90 || lat > 90) {
    throw new Error('经纬度超出合法范围');
  }

  const ts = new Date(timestamp);
  if (isNaN(ts.getTime())) {
    throw new Error('timestamp 不是合法的日期字符串');
  }

  return {
    senderMac: senderMac.toUpperCase().trim(),
    location: { type: 'Point', coordinates: [lon, lat] },
    bloodType: Number.isInteger(bloodType) ? bloodType : -1,
    timestamp: ts,
  };
}

/**
 * 核心去重逻辑：
 *   - 在 [timestamp - DEDUP_WINDOW_MS, timestamp + DEDUP_WINDOW_MS] 窗口内
 *     查找同一 senderMac 的记录。
 *   - 找到 → 追加骡子 ID（$addToSet 防止同一骡子重复记录）。
 *   - 未找到 → 新建文档。
 *
 * @param {Object} record - 标准化的求救记录
 * @param {String} muleId - 数据骡子 MAC 地址
 * @param {Object} medicalProfile - 可选的个人医疗档案信息
 * @returns {{ action: 'created'|'merged', doc: mongoose.Document }}
 */
async function upsertSosRecord(record, muleId, medicalProfile = {}) {
  const windowStart = new Date(record.timestamp.getTime() - DEDUP_WINDOW_MS);
  const windowEnd   = new Date(record.timestamp.getTime() + DEDUP_WINDOW_MS);

  const existing = await SosRecord.findOne({
    senderMac: record.senderMac,
    timestamp: { $gte: windowStart, $lte: windowEnd },
  });

  if (existing) {
    // 已存在：追加骡子 MAC，提升置信度
    await SosRecord.updateOne(
      { _id: existing._id },
      { 
        $addToSet: { reportedBy: muleId },
        // 如果有新的医疗档案信息，也更新
        ...(Object.keys(medicalProfile).length > 0 && {
          $set: { medicalProfile }
        })
      }
    );
    existing.reportedBy = [...new Set([...existing.reportedBy, muleId])];
    if (Object.keys(medicalProfile).length > 0) {
      existing.medicalProfile = medicalProfile;
    }
    return { action: 'merged', doc: existing };
  }

  // 全新求救：插入并广播
  const newDoc = await SosRecord.create({
    ...record,
    reportedBy: [muleId],
    medicalProfile: Object.keys(medicalProfile).length > 0 ? medicalProfile : undefined,
  });
  return { action: 'created', doc: newDoc };
}

async function buildChatContext(question, rankedRecords, clientContext = {}) {
  const chatHistory = Array.isArray(clientContext.chatHistory) ? clientContext.chatHistory : [];
  const summaryOverrides = { ...clientContext };
  delete summaryOverrides.chatHistory;
  delete summaryOverrides.intentHint;
  delete summaryOverrides.targetMac;
  const hintedIntent = normalizeIntentHint(clientContext.intentHint);
  const classifiedIntent = classifyQuestionIntent(question);
  const intent = classifiedIntent === 'rescue_dispatch' ? 'rescue_dispatch' : (hintedIntent || classifiedIntent);
  const includeAllLocationCases = shouldIncludeAllLocationCases(question, intent);
  const topRecords = rankedRecords.slice(0, 8);
  const matchedRecords = findRelevantRecords(question, rankedRecords, intent, chatHistory, clientContext.targetMac);
  const focusRecords = matchedRecords.length > 0
    ? matchedRecords.slice(0, ['route_plan', 'rescue_dispatch'].includes(intent) ? 3 : 5)
    : topRecords.slice(0, intent === 'priority' ? 3 : 5);
  const planTargets = ['route_plan', 'rescue_dispatch'].includes(intent) ? focusRecords.slice(0, 3) : [];
  const locationDetailsByMac = new Map();

  const generatedPlans = [];
  const generatedRescuePlans = [];
  if (intent === 'route_plan') {
  for (const record of planTargets) {
    try {
      const plan = await generateSingleRescuePlan(record);
      generatedPlans.push({
        mac: record.senderMac,
        name: record.medicalProfile?.name || '',
        priorityScore: record.priority?.score ?? 0,
        severityLevel: record.priority?.severityLevel || 'unknown',
        address: plan.location?.address || '',
        routeSummary: plan.route || null,
        recommendedHospitals: plan.recommendedHospitals || [],
        dispatchHint: buildDispatchHint(plan.route),
        aiRecommendations: sanitizePlanRecommendations(plan.aiRecommendations || []),
      });
    } catch (error) {
      generatedPlans.push({
        mac: record.senderMac,
        name: record.medicalProfile?.name || '',
        priorityScore: record.priority?.score ?? 0,
        severityLevel: record.priority?.severityLevel || 'unknown',
        address: '',
        routeSummary: null,
        recommendedHospitals: [],
        dispatchHint: '自动规划失败，当前无法给出可靠路线，建议人工调度复核。',
        aiRecommendations: [`自动规划失败: ${error.message}`],
      });
    }
  }
  }

  if (intent === 'rescue_dispatch') {
    for (const record of planTargets) {
      try {
        const plan = await generateNearestRescueTeamPlan(record);
        generatedRescuePlans.push({
          mac: record.senderMac,
          name: record.medicalProfile?.name || '',
          priorityScore: record.priority?.score ?? 0,
          severityLevel: record.priority?.severityLevel || 'unknown',
          address: plan.location?.address || '',
          routeSummary: plan.route || null,
          recommendedRescueTeams: plan.recommendedRescueTeams || [],
          dispatchHint: buildRescueDispatchHint(plan.route, plan.dispatchRecommendations),
          dispatchRecommendations: plan.dispatchRecommendations || [],
        });
      } catch (error) {
        generatedRescuePlans.push({
          mac: record.senderMac,
          name: record.medicalProfile?.name || '',
          priorityScore: record.priority?.score ?? 0,
          severityLevel: record.priority?.severityLevel || 'unknown',
          address: '',
          routeSummary: null,
          recommendedRescueTeams: [],
          dispatchHint: `rescue team planning failed: ${error.message}`,
          dispatchRecommendations: [`rescue team planning failed: ${error.message}`],
        });
      }
    }
  }

  if (intent === 'location') {
    await Promise.all(focusRecords.slice(0, 3).map(async (record) => {
      const coordinates = record.location?.coordinates || [];
      if (!Array.isArray(coordinates) || coordinates.length !== 2) {
        return;
      }

      try {
        const address = await reverseGeocode(coordinates[0], coordinates[1]);
        locationDetailsByMac.set(record.senderMac, {
          addressText: buildAddressSummary(address),
          nearbyLandmark: buildNearbyLandmark(address),
          formattedAddress: address.formattedAddress || '',
        });
      } catch (error) {
        locationDetailsByMac.set(record.senderMac, {
          addressText: '',
          nearbyLandmark: '',
          formattedAddress: '',
        });
      }
    }));
  }

  return {
    intent,
    summary: {
      total: rankedRecords.length,
      criticalCount: rankedRecords.filter((r) => r.priority?.severityLevel === 'critical').length,
      urgentCount: rankedRecords.filter((r) => r.priority?.severityLevel === 'urgent').length,
      ...summaryOverrides,
    },
    allCases: rankedRecords.map((record) => ({
      mac: record.senderMac,
      name: record.medicalProfile?.name || '',
      age: record.medicalProfile?.age || '',
      priorityScore: record.priority?.score ?? 0,
      severityLevel: record.priority?.severityLevel || 'unknown',
      elapsedMin: record.priority?.elapsedMin ?? 0,
      bloodTypeName: bloodTypeCodeToLabel(
        record.medicalProfile?.bloodTypeDetail ?? record.bloodType,
      ),
      medicalHistory: record.medicalProfile?.medicalHistory || '',
      allergies: record.medicalProfile?.allergies || '',
      emergencyContact: record.medicalProfile?.emergencyContact || '',
      locationText: formatCoordinates(record.location?.coordinates || []),
      province: coordsToProvince(
        record.location?.coordinates?.[0],
        record.location?.coordinates?.[1],
      ),
      confidence: record.confidence ?? (record.reportedBy?.length || 0),
      addressText: locationDetailsByMac.get(record.senderMac)?.addressText || '',
      nearbyLandmark: locationDetailsByMac.get(record.senderMac)?.nearbyLandmark || '',
      formattedAddress: locationDetailsByMac.get(record.senderMac)?.formattedAddress || '',
    })),
    allLocationCases: includeAllLocationCases
      ? rankedRecords.map((record) => ({
        mac: record.senderMac,
        name: record.medicalProfile?.name || '',
        priorityScore: record.priority?.score ?? 0,
        severityLevel: record.priority?.severityLevel || 'unknown',
        elapsedMin: record.priority?.elapsedMin ?? 0,
        locationText: formatCoordinates(record.location?.coordinates || []),
        province: coordsToProvince(
          record.location?.coordinates?.[0],
          record.location?.coordinates?.[1],
        ),
      }))
      : [],
    rankedCases: focusRecords.map((record) => pruneCaseForIntent({
      mac: record.senderMac,
      name: record.medicalProfile?.name || '',
      age: record.medicalProfile?.age || '',
      priorityScore: record.priority?.score ?? 0,
      severityLevel: record.priority?.severityLevel || 'unknown',
      elapsedMin: record.priority?.elapsedMin ?? 0,
      bloodTypeName: bloodTypeCodeToLabel(
        record.medicalProfile?.bloodTypeDetail ?? record.bloodType,
      ),
      medicalHistory: record.medicalProfile?.medicalHistory || '',
      allergies: record.medicalProfile?.allergies || '',
      emergencyContact: record.medicalProfile?.emergencyContact || '',
      locationText: formatCoordinates(record.location?.coordinates || []),
      addressText: locationDetailsByMac.get(record.senderMac)?.addressText || '',
      nearbyLandmark: locationDetailsByMac.get(record.senderMac)?.nearbyLandmark || '',
      formattedAddress: locationDetailsByMac.get(record.senderMac)?.formattedAddress || '',
      confidence: record.confidence ?? (record.reportedBy?.length || 0),
    }, intent)),
    generatedPlans: intent === 'route_plan' ? generatedPlans : [],
    generatedRescuePlans: intent === 'rescue_dispatch' ? generatedRescuePlans : [],
  };
}

function shouldIncludeAllLocationCases(question, intent) {
  if (intent === 'location') {
    return true;
  }

  const text = String(question || '');
  if (!text) {
    return false;
  }

  const broadLocationTerms = [
    '\u54ea\u4e2a\u7701',
    '\u54ea\u4e9b\u7701',
    '\u54ea\u4e2a\u57ce\u5e02',
    '\u54ea\u4e9b\u57ce\u5e02',
    '\u5206\u5e03',
    '\u5206\u5e03\u60c5\u51b5',
    '\u54ea\u91cc\u6700\u4e25\u91cd',
    '\u54ea\u91cc\u60c5\u51b5\u6700\u4e25\u91cd',
    '\u54ea\u91cc\u6700\u5371\u9669',
    '\u54ea\u4e2a\u5730\u533a',
    '\u54ea\u4e9b\u70b9',
    '\u5168\u90e8\u6c42\u6551\u70b9',
    '\u6240\u6709\u6c42\u6551\u70b9',
  ];

  return broadLocationTerms.some((term) => text.includes(term));
}

function findRelevantRecords(question, rankedRecords, intent = 'general', chatHistory = [], targetMac = '') {
  const upperQuestion = String(question || '').toUpperCase();
  const macMatches = upperQuestion.match(/[0-9A-F]{2}(?::[0-9A-F]{2}){5}/g) || [];
  const hintedMac = String(targetMac || '').toUpperCase().trim();
  const uniqueMacs = [...new Set([hintedMac, ...macMatches].filter(Boolean))];

  const macRecords = rankedRecords.filter((record) => uniqueMacs.includes(record.senderMac));
  if (macRecords.length > 0) {
    return macRecords;
  }

  const nameRecords = rankedRecords.filter((record) => {
    const name = record.medicalProfile?.name;
    return name && question.includes(name);
  });
  if (nameRecords.length > 0) {
    return nameRecords;
  }

  if (intent === 'route_plan' && uniqueMacs.length === 0) {
    const historyRecords = resolveRecordsFromHistory(chatHistory, rankedRecords);
    if (historyRecords.length > 0) {
      return historyRecords;
    }
  }

  if (shouldResolveFromHistory(question)) {
    const historyRecords = resolveRecordsFromHistory(chatHistory, rankedRecords);
    if (historyRecords.length > 0) {
      return historyRecords;
    }
  }

  if (intent === 'priority') {
    return rankedRecords.slice(0, 3);
  }

  return [];
}

function shouldResolveFromHistory(question) {
  const text = String(question || '');
  if (!text) {
    return false;
  }

  const referentialTerms = [
    '\u8fd9\u4e2a\u4eba',
    '\u8fd9\u4eba',
    '\u8fd9\u4e2a\u6c42\u6551\u8005',
    '\u8be5\u6c42\u6551\u8005',
    '\u8be5\u60a3\u8005',
    '\u8fd9\u4e2a\u60a3\u8005',
    '\u6b64\u4eba',
    '\u4ed6',
    '\u5979',
    'TA',
    '\u5176\u4f4d\u7f6e',
    '\u5f53\u524d\u4f4d\u7f6e',
    '\u5728\u54ea\u91cc',
    '\u5728\u54ea',
    '\u5177\u4f53\u4f4d\u7f6e',
    '\u5750\u6807',
    '\u5730\u70b9',
  ];

  return referentialTerms.some((term) => text.includes(term));
}

function resolveRecordsFromHistory(chatHistory, rankedRecords) {
  if (!Array.isArray(chatHistory) || chatHistory.length === 0) {
    return [];
  }

  const recentMessages = chatHistory
    .slice(-8)
    .map((item) => String(item?.content || ''))
    .filter(Boolean)
    .reverse();

  for (const content of recentMessages) {
    const macMatches = content.toUpperCase().match(/[0-9A-F]{2}(?::[0-9A-F]{2}){5}/g) || [];
    for (const mac of macMatches) {
      const matchedRecord = rankedRecords.find((record) => record.senderMac === mac);
      if (matchedRecord) {
        return [matchedRecord];
      }
    }
  }

  const recordsWithNames = rankedRecords
    .filter((record) => record.medicalProfile?.name)
    .sort((a, b) => b.medicalProfile.name.length - a.medicalProfile.name.length);

  for (const content of recentMessages) {
    for (const record of recordsWithNames) {
      if (content.includes(record.medicalProfile.name)) {
        return [record];
      }
    }
  }

  return [];
}

function classifyQuestionIntent(question) {
  const text = String(question || '');

  const rescueTerms = [
    '\u6551\u63f4\u961f',
    '\u6551\u63f4\u529b\u91cf',
    '\u6d88\u9632',
    '\u6d88\u9632\u961f',
    '\u6d3e\u51fa\u6240',
    '\u8b66\u5bdf',
    '\u516c\u5b89',
    '\u6025\u6551\u4e2d\u5fc3',
    '\u0031\u0032\u0030',
    '\u6551\u62a4\u8f66',
    '\u6025\u6551\u8f66',
    '\u8c01\u53bb\u6551',
    '\u6d3e\u8c01',
    '\u5c31\u8fd1\u6551\u63f4',
    '\u8c01\u53bb\u73b0\u573a',
    '\u8c01\u53bb\u5904\u7f6e',
  ];
  if (rescueTerms.some((term) => text.includes(term))) {
    return 'rescue_dispatch';
  }

  const routeTerms = ['\u8def\u7ebf', '\u89c4\u5212', '\u9001\u533b', '\u533b\u9662', '\u8c03\u5ea6', '\u65b9\u6848'];
  if (routeTerms.some((term) => text.includes(term))) {
    return 'route_plan';
  }

  const priorityTerms = ['\u4f18\u5148', '\u6700\u9700\u8981\u6551\u63f4', '\u5148\u6551'];
  if (priorityTerms.some((term) => text.includes(term))) {
    return 'priority';
  }

  const locationTerms = ['\u4f4d\u7f6e', '\u5728\u54ea', '\u54ea\u91cc', '\u9644\u8fd1', '\u5730\u70b9', '\u5730\u5740', '\u5750\u6807'];
  if (locationTerms.some((term) => text.includes(term))) {
    return 'location';
  }

  const identityTerms = ['\u59d3\u540d', '\u540d\u5b57', '\u662f\u8c01', '\u53eb\u4ec0\u4e48'];
  if (identityTerms.some((term) => text.includes(term))) {
    return 'identity';
  }

  const medicalTerms = ['\u75c5\u53f2', '\u8fc7\u654f', '\u8840\u578b', '\u5e74\u9f84'];
  if (medicalTerms.some((term) => text.includes(term))) {
    return 'medical';
  }

  const contactTerms = ['\u8054\u7cfb\u4eba', '\u8054\u7cfb', '\u7535\u8bdd'];
  if (contactTerms.some((term) => text.includes(term))) {
    return 'contact';
  }

  return 'general';
}

function normalizeIntentHint(intentHint) {
  const value = String(intentHint || '').trim().toLowerCase();
  const allowed = new Set(['route_plan', 'rescue_dispatch', 'priority', 'location', 'identity', 'medical', 'contact', 'general']);
  if (value === 'general') {
    return '';
  }
  return allowed.has(value) ? value : '';
}

function pruneCaseForIntent(data, intent) {
  switch (intent) {
    case 'priority':
      return {
        mac: data.mac,
        name: data.name,
        priorityScore: data.priorityScore,
        severityLevel: data.severityLevel,
        elapsedMin: data.elapsedMin,
        locationText: data.locationText,
        confidence: data.confidence,
      };
    case 'identity':
      return {
        mac: data.mac,
        name: data.name,
        age: data.age,
        elapsedMin: data.elapsedMin,
        locationText: data.locationText,
      };
    case 'location':
      return {
        mac: data.mac,
        name: data.name,
        elapsedMin: data.elapsedMin,
        locationText: data.locationText,
        addressText: data.addressText,
        nearbyLandmark: data.nearbyLandmark,
        formattedAddress: data.formattedAddress,
      };
    case 'medical':
      return {
        mac: data.mac,
        name: data.name,
        age: data.age,
        bloodTypeName: data.bloodTypeName,
        medicalHistory: data.medicalHistory,
        allergies: data.allergies,
      };
    case 'contact':
      return {
        mac: data.mac,
        name: data.name,
        emergencyContact: data.emergencyContact,
      };
      case 'route_plan':
        return {
          mac: data.mac,
          name: data.name,
          priorityScore: data.priorityScore,
          severityLevel: data.severityLevel,
          elapsedMin: data.elapsedMin,
          allergies: data.allergies,
          medicalHistory: data.medicalHistory,
          locationText: data.locationText,
        };
      case 'rescue_dispatch':
        return {
          mac: data.mac,
          name: data.name,
          priorityScore: data.priorityScore,
          severityLevel: data.severityLevel,
          elapsedMin: data.elapsedMin,
          allergies: data.allergies,
          medicalHistory: data.medicalHistory,
          locationText: data.locationText,
        };
      default:
        return {
        mac: data.mac,
        name: data.name,
        priorityScore: data.priorityScore,
        severityLevel: data.severityLevel,
        elapsedMin: data.elapsedMin,
        locationText: data.locationText,
      };
  }
}

function bloodTypeCodeToLabel(code) {
  switch (code) {
    case 0:
      return 'A';
    case 1:
      return 'B';
    case 2:
      return 'AB';
    case 3:
      return 'O';
    default:
      return '未知';
  }
}

function formatCoordinates(coordinates) {
  if (!Array.isArray(coordinates) || coordinates.length !== 2) {
    return '未知坐标';
  }
  return `${coordinates[1]}, ${coordinates[0]}`;
}

function buildDispatchHint(route) {
  if (!route) {
    return '暂无可靠路线，建议属地救援力量先行接触。';
  }

  if (route.distanceMeters >= 100000 || route.estimatedTimeMinutes >= 120) {
    return '路线超出常规就近送医范围，建议优先属地就近调度，并视情况升级跨区域协同。';
  }

  if (route.estimatedTimeMinutes >= 60) {
    return '路线较长，建议同步通知接收医院并评估是否存在更近接应点。';
  }

  return '路线处于常规应急转运范围，可按当前推荐方案执行。';
}

function buildRescueDispatchHint(route, recommendations = []) {
  if (!route) {
    return 'rescue team route unavailable';
  }

  if (Array.isArray(recommendations) && recommendations.length > 0) {
    return recommendations[0];
  }

  if (route.distanceMeters >= 50000 || route.estimatedTimeMinutes >= 90) {
    return 'nearest rescue team is still far away; consider parallel dispatch';
  }

  return 'nearest rescue team route is available';
}

function sanitizePlanRecommendations(recommendations) {
  if (!Array.isArray(recommendations)) {
    return [];
  }

  const blockedPatterns = [
    /硝酸甘油/,
    /阿司匹林/,
    /肝素/,
    /输血/,
    /血小板/,
    /红细胞/,
    /氧气/,
    /支气管扩张剂/,
    /aed/i,
    /除颤/,
    /药物/,
    /剂量/,
    /给药/,
    /监护设备/,
  ];

  const normalized = recommendations
    .map((item) => String(item || '').trim())
    .filter(Boolean)
    .filter((item) => !blockedPatterns.some((pattern) => pattern.test(item)));

  return [...new Set(normalized)].slice(0, 4);
}

function buildAddressSummary(address) {
  if (!address) {
    return '';
  }

  const component = address.addressComponent || {};
  const parts = [
    component.province,
    component.city,
    component.district,
    component.township,
    component.street,
    component.streetNumber,
  ].filter(Boolean);

  return parts.join('');
}

function buildNearbyLandmark(address) {
  if (!address) {
    return '';
  }

  const poi = Array.isArray(address.pois) ? address.pois[0] : null;
  if (poi?.name) {
    return poi.distance ? `${poi.name}附近（约${poi.distance}米）` : `${poi.name}附近`;
  }

  const road = Array.isArray(address.roads) ? address.roads[0] : null;
  if (road?.name) {
    return road.distance ? `${road.name}附近（约${road.distance}米）` : `${road.name}附近`;
  }

  return '';
}

function buildRouteOverlay(chatContext = {}) {
  const hospitalPlans = Array.isArray(chatContext.generatedPlans) ? chatContext.generatedPlans : [];
  const rescuePlans = Array.isArray(chatContext.generatedRescuePlans) ? chatContext.generatedRescuePlans : [];
  const isRescueDispatch = rescuePlans.length > 0;
  const plan = isRescueDispatch ? rescuePlans[0] : hospitalPlans[0];
  if (!plan?.routeSummary?.fullSteps?.length) {
    return null;
  }

  return {
      mac: plan.mac,
      name: isRescueDispatch ? (plan.routeSummary.fromTeam || '') : (plan.name || ''),
      startName: isRescueDispatch ? (plan.routeSummary.fromTeam || '') : (plan.name || plan.mac),
      endName: isRescueDispatch ? (plan.name || plan.mac) : plan.routeSummary.toHospital,
      startType: isRescueDispatch ? 'rescue_team' : 'victim',
      endType: isRescueDispatch ? 'victim' : 'hospital',
      hospitalName: isRescueDispatch ? (plan.name || plan.mac) : plan.routeSummary.toHospital,
      address: plan.address || '',
      route: plan.routeSummary,
    };
}

function buildRouteAnchorDebug(plan = {}) {
  const route = plan?.route;
  if (!route) {
    return null;
  }

  const routePoints = flattenRouteStepPolylines(route.fullSteps || []);
  const navStartGcj = routePoints[0] || null;
  const navEndGcj = routePoints[routePoints.length - 1] || null;
  const rawSourceWgs = Array.isArray(route.sourceCoordinates) ? route.sourceCoordinates : null;
  const rawDestinationWgs = Array.isArray(route.destinationCoordinates) ? route.destinationCoordinates : null;
  const rawSourceGcj = convertWgsPairToGcj(rawSourceWgs);
  const rawDestinationGcj = convertWgsPairToGcj(rawDestinationWgs);

  return {
    coordinateSystem: {
      sourceInput: 'WGS84',
      destinationInput: 'WGS84',
      routePolyline: 'GCJ-02',
      offsetsComparedIn: 'GCJ-02',
    },
    selectedHospital: {
      name: route.destinationMeta?.name || route.toHospital || '',
      address: route.destinationMeta?.address || '',
      type: route.destinationMeta?.type || '',
      source: route.destinationMeta?.source || '',
    },
    rawSourceWgs,
    rawSourceGcj,
    navStartGcj,
    sourceOffsetMeters: measureMeters(rawSourceGcj, navStartGcj),
    rawDestinationWgs,
    rawDestinationGcj,
    navEndGcj,
    destinationOffsetMeters: measureMeters(rawDestinationGcj, navEndGcj),
  };
}

function buildRescueRouteAnchorDebug(plan = {}) {
  const route = plan?.route;
  if (!route) {
    return null;
  }

  const routePoints = flattenRouteStepPolylines(route.fullSteps || []);
  const navStartGcj = routePoints[0] || null;
  const navEndGcj = routePoints[routePoints.length - 1] || null;
  const rawSourceWgs = Array.isArray(route.sourceCoordinates) ? route.sourceCoordinates : null;
  const rawDestinationWgs = Array.isArray(route.destinationCoordinates) ? route.destinationCoordinates : null;
  const rawSourceGcj = convertWgsPairToGcj(rawSourceWgs);
  const rawDestinationGcj = convertWgsPairToGcj(rawDestinationWgs);

  return {
    coordinateSystem: {
      sourceInput: 'WGS84',
      destinationInput: 'WGS84',
      routePolyline: 'GCJ-02',
      offsetsComparedIn: 'GCJ-02',
    },
    selectedRescueTeam: {
      name: route.sourceMeta?.name || route.fromTeam || '',
      address: route.sourceMeta?.address || '',
      type: route.sourceMeta?.type || '',
      source: route.sourceMeta?.source || '',
    },
    targetVictim: {
      name: route.destinationMeta?.name || '',
      address: route.destinationMeta?.address || '',
      type: route.destinationMeta?.type || '',
      source: route.destinationMeta?.source || '',
    },
    rawSourceWgs,
    rawSourceGcj,
    navStartGcj,
    sourceOffsetMeters: measureMeters(rawSourceGcj, navStartGcj),
    rawDestinationWgs,
    rawDestinationGcj,
    navEndGcj,
    destinationOffsetMeters: measureMeters(rawDestinationGcj, navEndGcj),
  };
}

function flattenRouteStepPolylines(steps = []) {
  const points = [];
  let lastKey = '';

  for (const step of Array.isArray(steps) ? steps : []) {
    const polyline = String(step?.polyline || '');
    const pairs = polyline.split(';').filter(Boolean);
    for (const pair of pairs) {
      const [lng, lat] = pair.split(',').map(Number);
      if (!Number.isFinite(lng) || !Number.isFinite(lat)) {
        continue;
      }
      const key = `${lng.toFixed(6)},${lat.toFixed(6)}`;
      if (key === lastKey) {
        continue;
      }
      lastKey = key;
      points.push([lng, lat]);
    }
  }

  return points;
}

function convertWgsPairToGcj(pair) {
  if (!Array.isArray(pair) || pair.length < 2) {
    return null;
  }

  const lng = Number(pair[0]);
  const lat = Number(pair[1]);
  if (!Number.isFinite(lng) || !Number.isFinite(lat)) {
    return null;
  }

  return wgs84ToGcj02(lng, lat);
}

function measureMeters(a, b) {
  if (!Array.isArray(a) || !Array.isArray(b)) {
    return null;
  }

  const [lng1, lat1] = a;
  const [lng2, lat2] = b;
  if (![lng1, lat1, lng2, lat2].every(Number.isFinite)) {
    return null;
  }

  const toRad = (deg) => (deg * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const lat1Rad = toRad(lat1);
  const lat2Rad = toRad(lat2);
  const h = Math.sin(dLat / 2) ** 2
    + Math.cos(lat1Rad) * Math.cos(lat2Rad) * Math.sin(dLng / 2) ** 2;
  return Math.round(6371000 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h)));
}

module.exports = router;
