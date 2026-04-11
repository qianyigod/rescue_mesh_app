/**
 * LLM analysis service.
 * Uses DashScope's OpenAI-compatible chat completions API.
 */

const DASHSCOPE_BASE_URL = 'https://dashscope.aliyuncs.com/compatible-mode/v1';
const LLM_MODEL = process.env.LLM_MODEL || 'qwen-plus';

async function chatCompletion(messages) {
  const apiKey = process.env.DASHSCOPE_API_KEY;
  if (!apiKey) {
    throw new Error('DASHSCOPE_API_KEY is not configured. Please update server/.env');
  }

  const response = await fetch(`${DASHSCOPE_BASE_URL}/chat/completions`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: LLM_MODEL,
      messages,
      temperature: 0.15,
      max_tokens: 1800,
    }),
  });

  if (!response.ok) {
    const errBody = await response.text();
    throw new Error(`LLM API call failed (${response.status}): ${errBody}`);
  }

  const data = await response.json();
  return data.choices?.[0]?.message?.content || '';
}

async function generateSituationReport(data) {
  const prompt = `你是应急救援指挥中心分析助手。请根据以下实时数据，生成简洁、专业的中文态势摘要。

概览:
- 求救点总数: ${data.total}
- 危重人数: ${data.criticalCount}
- 紧急人数: ${data.urgentCount}
- 血型分布: ${JSON.stringify(data.bloodDistribution)}

省份分布:
${(data.provinceDistribution || []).map((p) => `- ${p.name}: ${p.count} 例`).join('\n')}

等待最久:
${(data.longestWaiting || [])
  .map((w) => `- 等待 ${w.elapsedMin} 分钟 | 等级 ${w.severityLevel} | 病史 ${w.medicalHistory || '无'}`)
  .join('\n')}

最高优先级:
${(data.topPriorities || [])
  .map((p, i) => `- #${i + 1} | 分数 ${p.score} | 等级 ${p.severityLevel} | 病史 ${p.medicalHistory || '无'}`)
  .join('\n')}

要求:
1. 用中文输出。
2. 先写整体态势，再写重点风险，最后写行动建议。
3. 内容简洁，不空泛。`;

  return chatCompletion([
    {
      role: 'system',
      content: '你是应急救援指挥中心分析助手，擅长输出简洁专业的中文态势报告。',
    },
    { role: 'user', content: prompt },
  ]);
}

function formatCase(item, index) {
  return [
    `- #${index + 1}`,
    `姓名: ${item.name || '未登记'}`,
    `MAC: ${item.mac}`,
    `年龄: ${item.age || '未知'}`,
    `优先级分数: ${item.priorityScore}`,
    `等级: ${item.severityLevel}`,
    `等待时长: ${item.elapsedMin} 分钟`,
    `血型: ${item.bloodTypeName || '未知'}`,
    `病史: ${item.medicalHistory || '无'}`,
    `过敏: ${item.allergies || '无'}`,
    `紧急联系人: ${item.emergencyContact || '无'}`,
    `坐标: ${item.locationText || '未知'}`,
    item.province ? `归属省份: ${item.province}` : null,
    item.addressText ? `地址概述: ${item.addressText}` : null,
    item.nearbyLandmark ? `附近地标: ${item.nearbyLandmark}` : null,
    item.formattedAddress ? `详细地址: ${item.formattedAddress}` : null,
    `置信度: ${item.confidence ?? 0}`,
  ].filter(Boolean).join(' | ');
}

function formatPlan(plan) {
  const route = plan.routeSummary;
  const hospitals = (plan.recommendedHospitals || [])
    .map((hospital) => `${hospital.name}(${hospital.distanceKm}km, 约${hospital.estimatedTimeMinutes}分钟)`)
    .join('；');

  return [
    `- 规划对象: ${plan.name || '未登记'} / ${plan.mac}`,
    `优先级: ${plan.priorityScore} (${plan.severityLevel})`,
    `位置: ${plan.address || '未知'}`,
    route
      ? `推荐路线: 前往${route.toHospital}，距离${route.distanceKm}km，预计${route.estimatedTimeMinutes}分钟，过路费${route.tolls}`
      : '推荐路线: 无',
    plan.dispatchHint ? `调度提示: ${plan.dispatchHint}` : null,
    hospitals ? `候选医院: ${hospitals}` : null,
  ].filter(Boolean).join(' | ');
}

function formatChatContext(contextData = {}) {
  const summary = contextData.summary || {};
  const allCases = Array.isArray(contextData.allCases) ? contextData.allCases : [];
  const rankedCases = Array.isArray(contextData.rankedCases) ? contextData.rankedCases : [];
  const generatedPlans = Array.isArray(contextData.generatedPlans) ? contextData.generatedPlans : [];
  const intent = contextData.intent || 'general';

  const sections = [
    '## 当前态势',
    `- 问题意图: ${intent}`,
    `- 活跃求救点总数: ${summary.total ?? 0}`,
    `- critical: ${summary.criticalCount ?? 0}`,
    `- urgent: ${summary.urgentCount ?? 0}`,
  ];

  if (rankedCases.length > 0) {
    sections.push('## 重点相关个案');
    sections.push(rankedCases.map(formatCase).join('\n'));
  }

  if (allCases.length > 0) {
    sections.push('## 全部活跃求救信息');
    sections.push(allCases.map(formatCase).join('\n'));
  }

  if (generatedPlans.length > 0) {
    sections.push('## 自动生成的路线规划');
    sections.push(generatedPlans.map(formatPlan).join('\n'));
  }

  return sections.join('\n');
}

function buildFriendlyRouteSteps(route) {
  const fullSteps = Array.isArray(route?.fullSteps) ? route.fullSteps : [];
  if (fullSteps.length === 0) {
    return Array.isArray(route?.keySteps) ? route.keySteps.slice(0, 6) : [];
  }

  return fullSteps.slice(0, 6).map((step, index) => formatDrivingStep(step, index, fullSteps.length));
}

function formatDrivingStep(step, index, totalSteps) {
  const road = String(step?.road || '').trim();
  const orientation = String(step?.orientation || '').trim();
  const action = String(step?.action || '').trim();
  const distance = Number.isFinite(step?.distance) ? `${step.distance}米` : '';

  const roadText = road ? `沿${road}` : '从当前位置';
  const moveText = orientation && distance ? `向${orientation}行驶${distance}` : (distance ? `行驶${distance}` : '继续前进');

  if (index === totalSteps - 1) {
    return action
      ? `${roadText}${moveText}后${action}，即可到达目的地。`
      : `${roadText}${moveText}，即可到达目的地。`;
  }

  return action
    ? `${roadText}${moveText}后${action}。`
    : `${roadText}${moveText}。`;
}

function buildRouteAnswer(question, contextData = {}) {
  const generatedPlans = Array.isArray(contextData.generatedPlans) ? contextData.generatedPlans : [];
  if (generatedPlans.length === 0) {
    return '未识别到对应的求救对象。';
  }

  const plan = generatedPlans[0];
  const route = plan.routeSummary;
  const topHospital = (plan.recommendedHospitals || [])[0] || null;
  const target = plan.name ? `${plan.name} / ${plan.mac}` : plan.mac;
  const wantsDetailedRoute = /路线|怎么走|如何走|怎么去|过去|导航|步骤/.test(String(question || ''));

  if (route) {
    const lines = [
      `对象: ${target}`,
      `最近医院: ${route.toHospital}`,
      `路线: ${route.distanceKm} km，约 ${route.estimatedTimeMinutes} 分钟`,
      plan.address ? `位置: ${plan.address}` : null,
      plan.dispatchHint ? `调度提示: ${plan.dispatchHint}` : null,
    ].filter(Boolean);

    if (wantsDetailedRoute) {
      lines.push('导航步骤:');
      buildFriendlyRouteSteps(route).forEach((step, index) => {
        lines.push(`${index + 1}. ${step}`);
      });
    }

    return lines.join('\n');
  }

  if (topHospital) {
    return [
      `对象: ${target}`,
      `已找到医院候选: ${topHospital.name}`,
      `估计距离: ${topHospital.distanceKm} km，约 ${topHospital.estimatedTimeMinutes} 分钟`,
      '路线规划失败。',
    ].join('\n');
  }

  return [
    `对象: ${target}`,
    '没有匹配的医院。',
  ].join('\n');
}

async function answerQuestion(question, contextData) {
  if ((contextData?.intent || 'general') === 'route_plan') {
    return buildRouteAnswer(question, contextData);
  }

  const contextStr = formatChatContext(contextData);

  return chatCompletion([
    {
      role: 'system',
      content:
        '你是救援指挥中心的智能问答助手。'
        + '\n要求:'
        + '\n1. 只能依据上下文中的事实回答，不要编造未提供的信息。'
        + '\n2. 优先直接回答用户提问的核心问题。'
        + '\n3. 可以补充与该问题直接相关、能帮助指挥决策的少量额外信息。'
        + '\n4. 如果无法从上下文确认答案，只输出“无法确认。”'
        + '\n5. 只有路线规划问题才需要严格依赖后端规划结果；其它分析、归纳、比较问题可以基于全部求救信息自行组织答案。',
    },
    {
      role: 'user',
      content:
        `${contextStr}\n\n## 用户问题\n${question}\n\n`
        + '请直接用中文回答。先回答问题，再补充与问题强相关的必要信息；不要展开无关内容。',
    },
  ]);
}

module.exports = { generateSituationReport, answerQuestion };
