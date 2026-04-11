/**
 * AI 辅助决策 - 规则引擎
 * 基于优先级评分和风险区域检测的轻量级算法
 */

// 病史严重度评分表
const MEDICAL_HISTORY_SCORES = {
  '心脏病': 40, '心肌梗死': 45, '冠心病': 35, '心力衰竭': 40,
  '脑卒中': 45, '脑梗': 45, '脑出血': 50,
  '癫痫': 30, '哮喘': 25, '慢性阻塞性肺病': 30, 'COPD': 30,
  '糖尿病': 20, '高血压': 15,
  '白血病': 40, '淋巴瘤': 40, '癌症': 45,
  '肾衰竭': 40, '肝硬化': 35,
};

// 血型稀有度评分（越稀有分数越高）
const BLOOD_RARITY_SCORES = {
  0: 10, // A型 - 较常见
  1: 15, // B型 - 较稀有
  2: 20, // AB型 - 最稀有
  3: 5,  // O型 - 最常见
  '-1': 8, // 未知 - 中等
};

/**
 * 判断病史是否包含关键词
 */
function hasKeyword(history, keywords) {
  if (!history) return false;
  return keywords.some(kw => history.includes(kw));
}

/**
 * 计算单个SOS记录的优先级分数
 * @param {Object} sos - SOS记录对象
 * @returns {Object} { score, breakdown, severityLevel }
 */
function calculatePriority(sos) {
  let score = 0;
  const breakdown = [];

  // 1. 病史严重度评分 (0-50分)
  const mp = sos.medicalProfile || {};
  const history = mp.medicalHistory || '';
  let medicalScore = 0;
  
  if (history && history !== '无' && history !== '无重大疾病') {
    // 遍历病史关键词表，取最高匹配分
    let maxScore = 0;
    let matchedCondition = '';
    for (const [condition, pts] of Object.entries(MEDICAL_HISTORY_SCORES)) {
      if (history.includes(condition) && pts > maxScore) {
        maxScore = pts;
        matchedCondition = condition;
      }
    }
    
    if (maxScore > 0) {
      medicalScore = maxScore;
      breakdown.push(`病史"${matchedCondition}" +${medicalScore}`);
    } else {
      // 有病史但未匹配到已知严重疾病
      medicalScore = 10;
      breakdown.push('有其他病史 +10');
    }
  }
  score += medicalScore;

  // 2. 血型稀有度评分 (0-20分)
  const bloodType = sos.bloodType ?? mp.bloodTypeDetail ?? -1;
  const bloodScore = BLOOD_RARITY_SCORES[bloodType] ?? 8;
  score += bloodScore;
  breakdown.push(`血型${bloodScore}分`);

  // 3. 等待时长评分 (每10分钟+1分，上限30分)
  const elapsedMs = Date.now() - new Date(sos.timestamp).getTime();
  const elapsedMin = Math.floor(elapsedMs / 60000);
  const timeScore = Math.min(Math.floor(elapsedMin / 10), 30);
  score += timeScore;
  breakdown.push(`等待${elapsedMin}分钟 +${timeScore}`);

  // 4. 过敏史加分 (+10分，过敏患者用药需谨慎)
  if (mp.allergies && mp.allergies !== '无' && mp.allergies !== '') {
    score += 10;
    breakdown.push('有过敏史 +10');
  }

  // 判定严重等级
  let severityLevel;
  if (score >= 70) severityLevel = 'critical';      // 危急
  else if (score >= 50) severityLevel = 'urgent';    // 紧急
  else if (score >= 30) severityLevel = 'warning';   // 注意
  else severityLevel = 'normal';                      // 一般

  return {
    score,
    breakdown,
    severityLevel,
    elapsedMin,
  };
}

/**
 * 对一组SOS记录按优先级排序
 * @param {Array} sosList - SOS记录数组
 * @returns {Array} 带优先级信息的排序后数组
 */
function rankSosList(sosList) {
  return sosList
    .map(sos => ({
      ...sos,
      priority: calculatePriority(sos),
    }))
    .sort((a, b) => b.priority.score - a.priority.score);
}

/**
 * 检测风险区域（基于地理聚类和密度）
 * @param {Array} sosList - SOS记录数组
 * @param {Object} options - 配置选项
 * @returns {Array} 风险区域列表
 */
function detectRiskAreas(sosList, options = {}) {
  const {
    radiusKm = 5,        // 聚类半径（公里）
    minCount = 3,        // 最小聚集数量
    timeWindowMin = 60,  // 时间窗口（分钟）
  } = options;

  const now = Date.now();
  const cutoff = now - timeWindowMin * 60000;

  // 只分析时间窗口内的活跃求救
  const recent = sosList.filter(s => 
    s.status === 'active' && new Date(s.timestamp).getTime() >= cutoff
  );

  if (recent.length < minCount) return [];

  // 简化的DBSCAN聚类
  const clusters = [];
  const visited = new Set();

  function haversine(lat1, lon1, lat2, lon2) {
    const R = 6371;
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat/2)**2 + Math.cos(lat1*Math.PI/180) * Math.cos(lat2*Math.PI/180) * Math.sin(dLon/2)**2;
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
  }

  for (let i = 0; i < recent.length; i++) {
    if (visited.has(i)) continue;
    
    const cluster = [recent[i]];
    visited.add(i);
    
    for (let j = i + 1; j < recent.length; j++) {
      if (visited.has(j)) continue;
      
      const p1 = recent[i].location.coordinates;
      const p2 = recent[j].location.coordinates;
      const dist = haversine(p1[1], p1[0], p2[1], p2[0]);
      
      if (dist <= radiusKm) {
        cluster.push(recent[j]);
        visited.add(j);
      }
    }

    if (cluster.length >= minCount) {
      // 计算聚类中心
      const avgLat = cluster.reduce((s, c) => s + c.location.coordinates[1], 0) / cluster.length;
      const avgLon = cluster.reduce((s, c) => s + c.location.coordinates[0], 0) / cluster.length;
      
      // 统计危重人数
      const criticalCount = cluster.filter(c => calculatePriority(c).severityLevel === 'critical').length;
      const urgentCount = cluster.filter(c => calculatePriority(c).severityLevel === 'urgent').length;

      let riskLevel;
      if (criticalCount > 0 || cluster.length >= 8) riskLevel = 'high';
      else if (urgentCount >= 2 || cluster.length >= 5) riskLevel = 'medium';
      else riskLevel = 'low';

      clusters.push({
        center: [avgLon, avgLat],
        count: cluster.length,
        criticalCount,
        urgentCount,
        riskLevel,
        members: cluster.map(c => c.senderMac),
      });
    }
  }

  return clusters.sort((a, b) => {
    const levelOrder = { high: 3, medium: 2, low: 1 };
    return levelOrder[b.riskLevel] - levelOrder[a.riskLevel];
  });
}

module.exports = {
  calculatePriority,
  rankSosList,
  detectRiskAreas,
  MEDICAL_HISTORY_SCORES,
};
