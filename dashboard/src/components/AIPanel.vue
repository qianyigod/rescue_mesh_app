<template>
  <div class="panel ai-panel">
    <!-- Tab 切换 -->
    <div class="ai-tabs">
      <button 
        v-for="tab in tabs" 
        :key="tab.key"
        :class="['ai-tab-btn', { active: currentTab === tab.key }]"
        @click="currentTab = tab.key"
      >
        {{ tab.label }}
      </button>
    </div>

    <!-- 优先级列表 -->
    <div v-show="currentTab === 'priority'" class="ai-content">
      <div class="panel-title">
        <span class="icon">◆</span> 救援优先级排序
      </div>
      
      <!-- 统计摘要 -->
      <div v-if="prioritySummary" class="priority-summary">
        <div class="summary-item critical">
          <span class="summary-count">{{ prioritySummary.critical }}</span>
          <span class="summary-label">危急</span>
        </div>
        <div class="summary-item urgent">
          <span class="summary-count">{{ prioritySummary.urgent }}</span>
          <span class="summary-label">紧急</span>
        </div>
        <div class="summary-item warning">
          <span class="summary-count">{{ prioritySummary.warning }}</span>
          <span class="summary-label">注意</span>
        </div>
        <div class="summary-item normal">
          <span class="summary-count">{{ prioritySummary.normal }}</span>
          <span class="summary-label">一般</span>
        </div>
      </div>

      <!-- 优先级列表 -->
      <div class="priority-list">
        <div 
          v-for="(item, idx) in priorityList.slice(0, 20)" 
          :key="item.senderMac"
          :class="['priority-item', item.priority.severityLevel]"
          role="button"
          tabindex="0"
          @click="focusPriorityItem(item)"
          @keyup.enter="focusPriorityItem(item)"
        >
          <div class="priority-rank">#{{ idx + 1 }}</div>
          <div class="priority-info">
            <div class="priority-header">
              <span class="priority-score">{{ item.priority.score }}分</span>
              <span :class="['priority-severity', item.priority.severityLevel]">
                {{ severityLabel(item.priority.severityLevel) }}
              </span>
              <span class="priority-time">等待 {{ item.priority.elapsedMin }}分钟</span>
            </div>
            <div class="priority-details">
              <span v-if="item.medicalProfile?.name" class="detail-tag name">
                {{ item.medicalProfile.name }}
                <template v-if="item.medicalProfile.age">({{ item.medicalProfile.age }}岁)</template>
              </span>
              <span v-if="item.medicalProfile?.medicalHistory && item.medicalProfile.medicalHistory !== '无'" class="detail-tag history">
                {{ item.medicalProfile.medicalHistory }}
              </span>
              <span v-if="item.medicalProfile?.allergies && item.medicalProfile.allergies !== '无'" class="detail-tag allergy">
                ⚠ {{ item.medicalProfile.allergies }}
              </span>
              <span class="detail-tag blood" :style="{ borderColor: bloodColor(item.bloodType) }">
                {{ bloodLabel(item.bloodType) }}
              </span>
            </div>
            <div class="priority-breakdown">
              {{ item.priority.breakdown.join(' · ') }}
            </div>
          </div>
        </div>
        <div v-if="!priorityList.length" class="empty-state">
          暂无求救数据
        </div>
      </div>
    </div>

    <!-- 风险区域 -->
    <div v-show="currentTab === 'risk'" class="ai-content">
      <div class="panel-title">
        <span class="icon">◆</span> 风险聚集区域检测
      </div>
      
      <div v-if="riskAreas.length" class="risk-list">
        <div 
          v-for="(area, idx) in riskAreas" 
          :key="idx"
          :class="['risk-item', area.riskLevel]"
        >
          <div class="risk-header">
            <span :class="['risk-badge', area.riskLevel]">
              {{ riskLevelLabel(area.riskLevel) }}
            </span>
            <span class="risk-count">{{ area.count }} 个求救点聚集</span>
          </div>
          <div class="risk-details">
            <span class="risk-detail">
              坐标: [{{ area.center[0].toFixed(4) }}, {{ area.center[1].toFixed(4) }}]
            </span>
            <span v-if="area.criticalCount" class="risk-detail danger">
              含 {{ area.criticalCount }} 名危重人员
            </span>
            <span v-if="area.urgentCount" class="risk-detail warning">
              含 {{ area.urgentCount }} 名紧急人员
            </span>
          </div>
          <button class="risk-action-btn" @click="flyToArea(area)">
            定位
          </button>
        </div>
      </div>
      <div v-else class="empty-state">
        当前未发现风险聚集区域
      </div>
    </div>

    <!-- 态势摘要 -->
    <div v-show="currentTab === 'summary'" class="ai-content">
      <div class="panel-title">
        <span class="icon">◆</span> 实时态势摘要
      </div>
      
      <div v-if="situationReport" class="summary-content">
        <!-- 自动生成摘要 -->
        <div class="auto-summary">
          <div class="summary-text">
            <p>当前全国共 <strong>{{ situationReport.total }}</strong> 个求救点</p>
            <p v-if="situationReport.criticalCount">
              其中 <strong class="text-critical">{{ situationReport.criticalCount }}</strong> 人为<strong>危重</strong>，
              <strong class="text-urgent">{{ situationReport.urgentCount }}</strong> 人为<strong>紧急</strong>，需优先处理
            </p>
          </div>
          
          <!-- 各省求救点分布 -->
          <div v-if="situationReport.provinceDistribution && situationReport.provinceDistribution.length" class="province-section">
            <div class="section-title"> 各省求救点分布</div>
            <div class="province-list">
              <div v-for="(prov, idx) in situationReport.provinceDistribution" :key="idx" class="province-item">
                <span class="province-name">{{ prov.name }}</span>
                <span class="province-count">{{ prov.count }} 个</span>
              </div>
            </div>
          </div>
          
          <!-- 等待时间最长的求救 -->
          <div v-if="situationReport.longestWaiting.length" class="waiting-section">
            <div class="section-title">⏱ 等待时间最长的求救</div>
            <div v-for="(w, idx) in situationReport.longestWaiting" :key="idx" class="waiting-item">
              <span class="waiting-time">{{ w.elapsedMin }}分钟</span>
              <span class="waiting-severity" :class="w.severityLevel">
                {{ severityLabel(w.severityLevel) }}
              </span>
              <span v-if="w.medicalHistory !== '无'" class="waiting-history">{{ w.medicalHistory }}</span>
            </div>
          </div>

          <!-- 最高优先级求救 -->
          <div v-if="situationReport.topPriorities.length" class="top-priority-section">
            <div class="section-title">🎯 最高优先级求救</div>
            <div v-for="(p, idx) in situationReport.topPriorities" :key="idx" class="top-item">
              <span class="top-rank">{{ idx + 1 }}</span>
              <span class="top-score">{{ p.score }}分</span>
              <span class="top-severity" :class="p.severityLevel">
                {{ severityLabel(p.severityLevel) }}
              </span>
              <span v-if="p.medicalHistory !== '无'" class="top-history">{{ p.medicalHistory }}</span>
              <span v-if="p.allergies !== '无'" class="top-allergy">⚠{{ p.allergies }}</span>
            </div>
          </div>
        </div>
        
        <!-- LLM 智能摘要 -->
        <div class="llm-summary-section">
          <div class="section-title">🤖 AI 智能分析</div>
          <button class="llm-generate-btn" @click="generateLlmSummary" :disabled="llmLoading">
            {{ llmLoading ? '分析中...' : '生成 AI 分析报告' }}
          </button>
          <div v-if="llmSummary" class="llm-output" v-html="formatMarkdown(llmSummary)"></div>
          <div v-if="llmLoading" class="llm-loading">
            <span class="loading-dots">●●●</span> AI 正在分析态势数据...
          </div>
        </div>
      </div>
      <div v-else class="empty-state">
        加载中...
      </div>
    </div>

    <!-- 智能问答 -->
    <div v-show="currentTab === 'chat'" class="ai-content">
      <div class="panel-title">
        <span class="icon">◆</span> 智能问答
      </div>
      
      <div class="chat-container">
        <div class="chat-messages" ref="chatMessagesRef">
          <div v-for="(msg, idx) in chatMessages" :key="idx" :class="['chat-msg', msg.role]">
            <div class="chat-avatar">{{ msg.role === 'user' ? '👤' : '🤖' }}</div>
            <div class="chat-bubble" v-html="formatMarkdown(msg.content)"></div>
          </div>
          <div v-if="!chatMessages.length" class="chat-placeholder">
            <p>💡 试试问我：</p>
            <ul>
              <li @click="askQuickQuestion('当前最危险的求救点是哪些？')">当前最危险的求救点是哪些？</li>
              <li @click="askQuickQuestion('哪个省的情况最严重？')">哪个省的情况最严重？</li>
              <li @click="askQuickQuestion('有哪些需要特殊血型的人？')">有哪些需要特殊血型的人？</li>
              <li @click="askQuickQuestion('给我一份救援优先级建议')">给我一份救援优先级建议</li>
            </ul>
          </div>
          <div v-if="chatLoading" class="chat-msg ai">
            <div class="chat-avatar">🤖</div>
            <div class="chat-bubble typing">
              <span class="loading-dots">●●●</span>
            </div>
          </div>
        </div>

        <div v-if="currentRouteOverlay" class="route-step-panel">
          <div class="route-step-panel-head">
            <div>
              <div class="route-step-panel-title">当前导航</div>
              <div class="route-step-panel-meta">
                {{ currentRouteOverlay.name || currentRouteOverlay.mac }} → {{ currentRouteOverlay.hospitalName }}
              </div>
              <div class="route-step-panel-meta">
                {{ currentRouteOverlay.route?.distanceKm || '--' }} km · {{ currentRouteOverlay.route?.estimatedTimeMinutes || '--' }} 分钟
              </div>
            </div>
            <button class="route-focus-btn" @click="focusWholeRoute">定位路线</button>
          </div>
          <div class="route-step-list">
            <button
              v-for="(step, idx) in getRouteSteps(currentRouteOverlay.route)"
              :key="`${currentRouteOverlay.mac}-${idx}`"
              :class="['route-step-btn', { active: activeRouteStepIndex === idx }]"
              @click="focusRouteStep(idx)"
            >
              <span class="route-step-index">{{ idx + 1 }}</span>
              <span class="route-step-text">{{ step.instruction }}</span>
            </button>
          </div>
        </div>
        
        <div class="chat-input-area">
          <input 
            v-model="chatInput"
            class="chat-input"
            type="text"
            placeholder="输入你的问题..."
            @keyup.enter="sendChat"
            :disabled="chatLoading"
          />
          <button class="chat-send-btn" @click="sendChat" :disabled="chatLoading || !chatInput.trim()">
            发送
          </button>
        </div>
      </div>
    </div>

    <!-- 刷新按钮 -->
    <div class="ai-footer">
      <button class="refresh-btn" @click="refreshAll" :disabled="loading">
        {{ loading ? '刷新中...' : '↻ 刷新数据' }}
      </button>
      <span class="refresh-time">最后更新: {{ lastUpdateTime }}</span>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { BLOOD_LABELS, BLOOD_COLORS } from '../composables/useSocket'

const API_BASE = import.meta.env.VITE_API_BASE || 'http://localhost:3000'

const tabs = [
  { key: 'priority', label: '🎯 优先级' },
  { key: 'risk', label: '⚠ 风险区域' },
  { key: 'summary', label: '📊 态势摘要' },
  { key: 'chat', label: '🤖 智能问答' },
]

const currentTab = ref('priority')
const priorityList = ref([])
const prioritySummary = ref(null)
const riskAreas = ref([])
const situationReport = ref(null)
const llmSummary = ref('')
const llmLoading = ref(false)
const chatMessages = ref([])
const chatInput = ref('')
const chatLoading = ref(false)
const loading = ref(false)
const lastUpdateTime = ref('--:--:--')
const currentRouteOverlay = ref(null)
const activeRouteStepIndex = ref(-1)

let refreshTimer = null

function classifyChatIntent(question) {
  const text = String(question || '')
  const routeTerms = ['路线', '规划', '送医', '医院', '调度', '方案', '怎么走', '导航']
  if (routeTerms.some((term) => text.includes(term))) return 'route_plan'

  const priorityTerms = ['优先', '最需要救援', '先救']
  if (priorityTerms.some((term) => text.includes(term))) return 'priority'

  const locationTerms = ['位置', '在哪', '哪里', '附近', '地点', '地址', '坐标']
  if (locationTerms.some((term) => text.includes(term))) return 'location'

  const identityTerms = ['姓名', '名字', '是谁', '叫什么']
  if (identityTerms.some((term) => text.includes(term))) return 'identity'

  const medicalTerms = ['病史', '过敏', '血型', '年龄']
  if (medicalTerms.some((term) => text.includes(term))) return 'medical'

  const contactTerms = ['联系人', '联系', '电话']
  if (contactTerms.some((term) => text.includes(term))) return 'contact'

  return 'general'
}

function extractTargetMac(question) {
  const matches = String(question || '').toUpperCase().match(/[0-9A-F]{2}(?::[0-9A-F]{2}){5}/g) || []
  return matches[0] || ''
}

function getRouteSteps(route) {
  if (Array.isArray(route?.fullSteps) && route.fullSteps.length) {
    return route.fullSteps.slice(0, 8).map((step) => ({
      instruction: step.instruction || '继续前进',
    }))
  }

  if (Array.isArray(route?.keySteps) && route.keySteps.length) {
    return route.keySteps.slice(0, 8).map((instruction) => ({ instruction }))
  }

  return []
}

function focusRouteStep(index) {
  if (!currentRouteOverlay.value) return
  activeRouteStepIndex.value = index
  window.dispatchEvent(new CustomEvent('map-highlight-route-step', {
    detail: {
      stepIndex: index,
      routeOverlay: currentRouteOverlay.value,
    },
  }))
}

function focusWholeRoute() {
  if (!currentRouteOverlay.value) return
  activeRouteStepIndex.value = -1
  window.dispatchEvent(new CustomEvent('map-focus-route', {
    detail: currentRouteOverlay.value,
  }))
}

// 血型标签和颜色
function bloodLabel(type) {
  return BLOOD_LABELS[String(type ?? -1)] || '未知'
}

function bloodColor(type) {
  return BLOOD_COLORS[String(type ?? -1)] || '#9966FF'
}

// 严重等级标签
function severityLabel(level) {
  const labels = {
    critical: '危急',
    urgent: '紧急',
    warning: '注意',
    normal: '一般',
  }
  return labels[level] || level
}

// 风险等级标签
function riskLevelLabel(level) {
  const labels = {
    high: '高风险',
    medium: '中风险',
    low: '低风险',
  }
  return labels[level] || level
}

// 获取优先级数据
async function fetchPriorities() {
  try {
    const res = await fetch(`${API_BASE}/api/sos/ai/priorities`)
    const json = await res.json()
    priorityList.value = json.data || []
    prioritySummary.value = json.summary || null
  } catch (e) {
    console.warn('[AI] 获取优先级数据失败:', e.message)
  }
}

// 获取风险区域
async function fetchRiskAreas() {
  try {
    const res = await fetch(`${API_BASE}/api/sos/ai/risk-areas`)
    const json = await res.json()
    riskAreas.value = json.data || []
  } catch (e) {
    console.warn('[AI] 获取风险区域失败:', e.message)
  }
}

// 获取态势摘要
async function fetchSituationReport() {
  try {
    const res = await fetch(`${API_BASE}/api/sos/ai/situation-report`)
    const json = await res.json()
    situationReport.value = json.data || null
  } catch (e) {
    console.warn('[AI] 获取态势摘要失败:', e.message)
  }
}

// 定位到风险区域
function flyToArea(area) {
  window.dispatchEvent(new CustomEvent('map-flyto-area', {
    detail: {
      center: area.center,
      count: area.count,
    },
  }))
}

function focusPriorityItem(item) {
  if (!item) return
  window.dispatchEvent(new CustomEvent('map-flyto', {
    detail: item,
  }))
}

// LLM 生成态势摘要
async function generateLlmSummary() {
  if (!situationReport.value) return
  llmLoading.value = true
  try {
    const res = await fetch(`${API_BASE}/api/sos/ai/generate-report`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ reportData: situationReport.value }),
    })
    const json = await res.json()
    llmSummary.value = json.data?.summary || ''
  } catch (e) {
    console.warn('[AI] LLM 摘要生成失败:', e.message)
    llmSummary.value = `⚠️ 生成失败: ${e.message}`
  } finally {
    llmLoading.value = false
  }
}

// 发送聊天消息
async function sendChat() {
  const question = chatInput.value.trim()
  if (!question || chatLoading.value || !situationReport.value) return
  const intentHint = classifyChatIntent(question)
  const targetMac = extractTargetMac(question)
  
  chatMessages.value.push({ role: 'user', content: question })
  chatInput.value = ''
  chatLoading.value = true
  
  try {
    const res = await fetch(`${API_BASE}/api/sos/ai/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        question,
        intentHint,
        targetMac,
        contextData: situationReport.value,
        chatHistory: chatMessages.value.slice(-6),
      }),
    })
    const json = await res.json()
    if (json.data?.routeOverlay) {
      currentRouteOverlay.value = json.data.routeOverlay
      activeRouteStepIndex.value = -1
      window.dispatchEvent(new CustomEvent('map-show-route', {
        detail: json.data.routeOverlay,
      }))
    }
    chatMessages.value.push({ role: 'ai', content: json.data?.answer || '抱歉，暂时无法回答' })
  } catch (e) {
    chatMessages.value.push({ role: 'ai', content: `⚠️ 回答失败: ${e.message}` })
  } finally {
    chatLoading.value = false
    scrollToBottom()
  }
}

// 快捷提问
function askQuickQuestion(q) {
  chatInput.value = q
  sendChat()
}

// 简单 Markdown 格式化（粗体 + 换行）
function formatMarkdown(text) {
  if (!text) return ''
  return text
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/\n/g, '<br/>')
}

// 滚动到底部
function scrollToBottom() {
  // 延迟确保 DOM 更新
  setTimeout(() => {
    const container = document.querySelector('.chat-messages')
    if (container) container.scrollTop = container.scrollHeight
  }, 100)
}

// 刷新所有数据
async function refreshAll() {
  loading.value = true
  await Promise.all([fetchPriorities(), fetchRiskAreas(), fetchSituationReport()])
  lastUpdateTime.value = new Date().toLocaleTimeString('zh-CN')
  loading.value = false
}

onMounted(() => {
  refreshAll()
  // 每30秒自动刷新
  refreshTimer = setInterval(refreshAll, 30000)
  window.addEventListener('map-route-step-changed', handleRouteStepChanged)
})

onUnmounted(() => {
  if (refreshTimer) clearInterval(refreshTimer)
  window.removeEventListener('map-route-step-changed', handleRouteStepChanged)
})

function handleRouteStepChanged(e) {
  const stepIndex = Number(e.detail?.stepIndex)
  activeRouteStepIndex.value = Number.isInteger(stepIndex) ? stepIndex : -1
}
</script>

<style scoped>
.ai-panel {
  display: flex;
  flex-direction: column;
  background: rgba(0, 12, 30, 0.95);
  border: 1px solid rgba(0, 200, 255, 0.2);
  border-radius: 6px;
  overflow: hidden;
  height: 100%;
}

/* Tab 切换 */
.ai-tabs {
  display: flex;
  gap: 0;
  border-bottom: 1px solid rgba(0, 200, 255, 0.2);
  flex-shrink: 0;
}

.ai-tab-btn {
  flex: 1;
  padding: 8px 4px;
  background: transparent;
  border: none;
  color: rgba(160, 210, 255, 0.5);
  font-size: 0.7rem;
  font-family: 'Courier New', monospace;
  cursor: pointer;
  transition: all 0.2s;
  border-bottom: 2px solid transparent;
}

.ai-tab-btn:hover {
  color: rgba(160, 210, 255, 0.8);
  background: rgba(0, 200, 255, 0.05);
}

.ai-tab-btn.active {
  color: #00e5ff;
  border-bottom-color: #00e5ff;
  background: rgba(0, 200, 255, 0.08);
}

.ai-content {
  flex: 1;
  overflow-y: auto;
  padding: 8px;
}

.panel-title {
  font-size: 0.7rem;
  color: rgba(0, 200, 255, 0.6);
  letter-spacing: 1px;
  margin-bottom: 8px;
  display: flex;
  align-items: center;
  gap: 4px;
}

.panel-title .icon {
  color: #00e5ff;
}

/* 优先级统计摘要 */
.priority-summary {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 4px;
  margin-bottom: 10px;
}

.summary-item {
  text-align: center;
  padding: 6px 2px;
  border-radius: 4px;
  background: rgba(0, 20, 50, 0.6);
  border: 1px solid rgba(100, 150, 200, 0.15);
}

.summary-item.critical { border-color: rgba(255, 50, 50, 0.4); }
.summary-item.urgent { border-color: rgba(255, 165, 0, 0.4); }
.summary-item.warning { border-color: rgba(255, 206, 86, 0.3); }
.summary-item.normal { border-color: rgba(0, 229, 255, 0.2); }

.summary-count {
  display: block;
  font-size: 1.1rem;
  font-weight: bold;
  color: #fff;
}

.summary-item.critical .summary-count { color: #ff4444; }
.summary-item.urgent .summary-count { color: #ffa500; }
.summary-item.warning .summary-count { color: #ffce56; }
.summary-item.normal .summary-count { color: #00e5ff; }

.summary-label {
  font-size: 0.6rem;
  color: rgba(160, 210, 255, 0.5);
}

/* 优先级列表 */
.priority-list {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.priority-item {
  display: flex;
  gap: 8px;
  padding: 8px;
  border-radius: 4px;
  background: rgba(0, 15, 40, 0.8);
  border: 1px solid rgba(100, 150, 200, 0.1);
  cursor: pointer;
  transition: border-color 0.2s, transform 0.2s, box-shadow 0.2s;
}

.priority-item:hover {
  border-color: rgba(0, 200, 255, 0.3);
  transform: translateY(-1px);
  box-shadow: 0 10px 24px rgba(0, 0, 0, 0.18);
}

.priority-item:focus-visible {
  outline: none;
  border-color: rgba(0, 229, 255, 0.42);
  box-shadow: 0 0 0 1px rgba(0, 229, 255, 0.24), 0 10px 24px rgba(0, 0, 0, 0.18);
}

.priority-item.critical {
  border-left: 3px solid #ff4444;
  background: rgba(40, 5, 5, 0.6);
}

.priority-item.urgent {
  border-left: 3px solid #ffa500;
  background: rgba(30, 15, 0, 0.5);
}

.priority-item.warning {
  border-left: 3px solid #ffce56;
}

.priority-item.normal {
  border-left: 3px solid rgba(0, 229, 255, 0.3);
}

.priority-rank {
  font-size: 0.9rem;
  font-weight: bold;
  color: rgba(0, 200, 255, 0.5);
  flex-shrink: 0;
  width: 28px;
  text-align: center;
  padding-top: 2px;
}

.priority-info {
  flex: 1;
  min-width: 0;
}

.priority-header {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-bottom: 4px;
}

.priority-score {
  font-size: 0.85rem;
  font-weight: bold;
  color: #fff;
}

.priority-severity {
  font-size: 0.6rem;
  padding: 1px 6px;
  border-radius: 3px;
  font-weight: bold;
}

.priority-severity.critical {
  background: rgba(255, 50, 50, 0.3);
  color: #ff6666;
}

.priority-severity.urgent {
  background: rgba(255, 165, 0, 0.3);
  color: #ffaa44;
}

.priority-severity.warning {
  background: rgba(255, 206, 86, 0.2);
  color: #ffce56;
}

.priority-severity.normal {
  background: rgba(0, 229, 255, 0.15);
  color: #00e5ff;
}

.priority-time {
  font-size: 0.6rem;
  color: rgba(160, 210, 255, 0.4);
  margin-left: auto;
}

.priority-details {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
  margin-bottom: 4px;
}

.detail-tag {
  font-size: 0.6rem;
  padding: 1px 6px;
  border-radius: 3px;
  white-space: nowrap;
}

.detail-tag.name {
  background: rgba(0, 200, 255, 0.15);
  color: #00e5ff;
}

.detail-tag.history {
  background: rgba(255, 100, 100, 0.15);
  color: #ff8888;
}

.detail-tag.allergy {
  background: rgba(255, 200, 50, 0.15);
  color: #ffcc44;
}

.detail-tag.blood {
  border: 1px solid;
  color: inherit;
}

.priority-breakdown {
  font-size: 0.55rem;
  color: rgba(160, 210, 255, 0.35);
  line-height: 1.4;
}

/* 风险区域 */
.risk-list {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.risk-item {
  padding: 10px;
  border-radius: 4px;
  background: rgba(0, 15, 40, 0.8);
  border: 1px solid rgba(100, 150, 200, 0.1);
  position: relative;
}

.risk-item.high {
  border-left: 3px solid #ff4444;
  background: rgba(40, 5, 5, 0.6);
}

.risk-item.medium {
  border-left: 3px solid #ffa500;
  background: rgba(30, 15, 0, 0.5);
}

.risk-item.low {
  border-left: 3px solid #ffce56;
}

.risk-header {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 6px;
}

.risk-badge {
  font-size: 0.65rem;
  padding: 2px 8px;
  border-radius: 3px;
  font-weight: bold;
}

.risk-badge.high {
  background: rgba(255, 50, 50, 0.3);
  color: #ff6666;
}

.risk-badge.medium {
  background: rgba(255, 165, 0, 0.3);
  color: #ffaa44;
}

.risk-badge.low {
  background: rgba(255, 206, 86, 0.2);
  color: #ffce56;
}

.risk-count {
  font-size: 0.75rem;
  color: #e0f4ff;
}

.risk-details {
  display: flex;
  flex-direction: column;
  gap: 2px;
  margin-bottom: 6px;
}

.risk-detail {
  font-size: 0.6rem;
  color: rgba(160, 210, 255, 0.5);
}

.risk-detail.danger {
  color: #ff6666;
}

.risk-detail.warning {
  color: #ffaa44;
}

.risk-action-btn {
  position: absolute;
  top: 8px;
  right: 8px;
  padding: 3px 10px;
  font-size: 0.6rem;
  font-family: 'Courier New', monospace;
  background: rgba(0, 200, 255, 0.15);
  border: 1px solid rgba(0, 200, 255, 0.3);
  color: #00e5ff;
  border-radius: 3px;
  cursor: pointer;
  transition: all 0.2s;
}

.risk-action-btn:hover {
  background: rgba(0, 200, 255, 0.3);
}

/* 态势摘要 */
.summary-content {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.auto-summary {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.summary-text p {
  font-size: 0.75rem;
  color: #c0e0ff;
  margin: 0 0 4px 0;
  line-height: 1.6;
}

.summary-text strong {
  color: #00e5ff;
}

.text-critical { color: #ff4444 !important; }
.text-urgent { color: #ffa500 !important; }

.section-title {
  font-size: 0.7rem;
  color: rgba(0, 200, 255, 0.6);
  margin-bottom: 6px;
  letter-spacing: 1px;
}

.province-section {
  background: rgba(0, 15, 40, 0.6);
  border: 1px solid rgba(100, 150, 200, 0.1);
  border-radius: 4px;
  padding: 8px;
  margin-top: 8px;
}

.province-list {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}

.province-item {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 4px 10px;
  background: rgba(0, 30, 60, 0.5);
  border: 1px solid rgba(100, 150, 200, 0.12);
  border-radius: 3px;
  font-size: 0.65rem;
}

.province-name {
  color: #c0e0ff;
}

.province-count {
  color: #00e5ff;
  font-weight: bold;
}

.waiting-section,
.top-priority-section {
  background: rgba(0, 15, 40, 0.6);
  border: 1px solid rgba(100, 150, 200, 0.1);
  border-radius: 4px;
  padding: 8px;
}

.waiting-item,
.top-item {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 4px 0;
  border-bottom: 1px solid rgba(100, 150, 200, 0.08);
  font-size: 0.65rem;
}

.waiting-item:last-child,
.top-item:last-child {
  border-bottom: none;
}

.waiting-time {
  color: #ff8844;
  font-weight: bold;
  min-width: 50px;
}

.waiting-severity {
  font-size: 0.55rem;
  padding: 1px 5px;
  border-radius: 2px;
}

.waiting-severity.critical {
  background: rgba(255, 50, 50, 0.3);
  color: #ff6666;
}

.waiting-severity.urgent {
  background: rgba(255, 165, 0, 0.3);
  color: #ffaa44;
}

.waiting-severity.warning {
  background: rgba(255, 206, 86, 0.2);
  color: #ffce56;
}

.waiting-history {
  color: rgba(255, 100, 100, 0.7);
}

.top-rank {
  color: #00e5ff;
  font-weight: bold;
  min-width: 16px;
}

.top-score {
  color: #fff;
  font-weight: bold;
  min-width: 30px;
}

.top-severity {
  font-size: 0.55rem;
  padding: 1px 5px;
  border-radius: 2px;
}

.top-severity.critical {
  background: rgba(255, 50, 50, 0.3);
  color: #ff6666;
}

.top-severity.urgent {
  background: rgba(255, 165, 0, 0.3);
  color: #ffaa44;
}

.top-severity.warning {
  background: rgba(255, 206, 86, 0.2);
  color: #ffce56;
}

.top-history {
  color: rgba(255, 100, 100, 0.7);
}

.top-allergy {
  color: #ffcc44;
  font-size: 0.6rem;
}

/* Footer */
.ai-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 6px 8px;
  border-top: 1px solid rgba(0, 200, 255, 0.15);
  flex-shrink: 0;
}

/* LLM Summary Section */
.llm-summary-section {
  margin-top: 10px;
  padding-top: 10px;
  border-top: 1px dashed rgba(100, 150, 200, 0.15);
}

.llm-generate-btn {
  width: 100%;
  padding: 6px 12px;
  font-size: 0.65rem;
  font-family: 'Courier New', monospace;
  background: linear-gradient(135deg, rgba(0, 200, 255, 0.15), rgba(100, 100, 255, 0.15));
  border: 1px solid rgba(0, 200, 255, 0.3);
  color: #00e5ff;
  border-radius: 4px;
  cursor: pointer;
  transition: all 0.2s;
}

.llm-generate-btn:hover:not(:disabled) {
  background: linear-gradient(135deg, rgba(0, 200, 255, 0.25), rgba(100, 100, 255, 0.25));
}

.llm-generate-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.llm-output {
  margin-top: 8px;
  padding: 10px;
  background: rgba(0, 20, 50, 0.6);
  border: 1px solid rgba(100, 100, 255, 0.2);
  border-radius: 4px;
  font-size: 0.65rem;
  color: #c0e0ff;
  line-height: 1.6;
  white-space: pre-wrap;
}

.llm-loading {
  margin-top: 8px;
  padding: 10px;
  text-align: center;
  color: rgba(0, 200, 255, 0.6);
  font-size: 0.65rem;
}

/* Chat Interface */
.chat-container {
  display: flex;
  flex-direction: column;
  height: calc(100vh - 280px);
  min-height: 300px;
}

.chat-messages {
  flex: 1;
  overflow-y: auto;
  padding: 8px 0;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.chat-msg {
  display: flex;
  gap: 6px;
  max-width: 95%;
}

.chat-msg.user {
  align-self: flex-end;
  flex-direction: row-reverse;
}

.chat-avatar {
  font-size: 0.8rem;
  flex-shrink: 0;
  margin-top: 2px;
}

.chat-bubble {
  padding: 6px 10px;
  border-radius: 6px;
  font-size: 0.65rem;
  line-height: 1.5;
}

.chat-msg.ai .chat-bubble {
  background: rgba(0, 20, 50, 0.8);
  border: 1px solid rgba(100, 150, 200, 0.15);
  color: #c0e0ff;
}

.chat-msg.user .chat-bubble {
  background: rgba(0, 100, 200, 0.2);
  border: 1px solid rgba(0, 150, 255, 0.3);
  color: #e0f4ff;
}

.chat-placeholder {
  text-align: center;
  padding: 20px 10px;
  color: rgba(160, 210, 255, 0.3);
  font-size: 0.7rem;
}

.chat-placeholder p {
  margin-bottom: 8px;
}

.chat-placeholder ul {
  list-style: none;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.chat-placeholder li {
  padding: 4px 8px;
  background: rgba(0, 30, 60, 0.5);
  border: 1px solid rgba(100, 150, 200, 0.1);
  border-radius: 3px;
  cursor: pointer;
  transition: all 0.2s;
  color: rgba(0, 200, 255, 0.6);
}

.chat-placeholder li:hover {
  background: rgba(0, 50, 100, 0.5);
  border-color: rgba(0, 200, 255, 0.3);
  color: #00e5ff;
}

.chat-input-area {
  display: flex;
  gap: 6px;
  padding-top: 8px;
  border-top: 1px solid rgba(100, 150, 200, 0.1);
  flex-shrink: 0;
}

.route-step-panel {
  margin-top: 10px;
  padding: 10px;
  border: 1px solid rgba(0, 229, 255, 0.18);
  border-radius: 8px;
  background: linear-gradient(180deg, rgba(2, 22, 40, 0.96), rgba(1, 14, 28, 0.96));
}

.route-step-panel-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 8px;
  margin-bottom: 10px;
}

.route-step-panel-title {
  color: #8fefff;
  font-size: 0.72rem;
  font-weight: bold;
}

.route-step-panel-meta {
  color: rgba(180, 225, 255, 0.72);
  font-size: 0.6rem;
  line-height: 1.45;
}

.route-focus-btn {
  flex-shrink: 0;
  height: 30px;
  padding: 0 10px;
  border-radius: 999px;
  border: 1px solid rgba(0, 229, 255, 0.24);
  background: rgba(0, 229, 255, 0.1);
  color: #9df5ff;
  cursor: pointer;
  font-size: 0.62rem;
}

.route-focus-btn:hover {
  background: rgba(0, 229, 255, 0.16);
}

.route-step-list {
  display: flex;
  flex-direction: column;
  gap: 6px;
  max-height: 180px;
  overflow-y: auto;
}

.route-step-btn {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  width: 100%;
  padding: 8px;
  border-radius: 8px;
  border: 1px solid rgba(0, 229, 255, 0.12);
  background: rgba(5, 19, 34, 0.82);
  color: #d9f7ff;
  text-align: left;
  cursor: pointer;
  transition: border-color 0.16s ease, background 0.16s ease, transform 0.16s ease;
}

.route-step-btn:hover {
  border-color: rgba(0, 229, 255, 0.32);
  background: rgba(8, 28, 49, 0.94);
  transform: translateX(2px);
}

.route-step-btn.active {
  border-color: rgba(255, 234, 91, 0.62);
  background: rgba(47, 41, 10, 0.7);
  box-shadow: 0 0 0 1px rgba(255, 234, 91, 0.18) inset;
}

.route-step-index {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 22px;
  height: 22px;
  border-radius: 50%;
  background: rgba(0, 229, 255, 0.14);
  border: 1px solid rgba(0, 229, 255, 0.2);
  color: #98f4ff;
  font-size: 0.64rem;
  font-weight: bold;
  flex-shrink: 0;
}

.route-step-btn.active .route-step-index {
  background: rgba(255, 234, 91, 0.18);
  border-color: rgba(255, 234, 91, 0.4);
  color: #fff4a3;
}

.route-step-text {
  color: rgba(224, 247, 255, 0.92);
  font-size: 0.66rem;
  line-height: 1.45;
}

.chat-input {
  flex: 1;
  padding: 6px 10px;
  font-size: 0.65rem;
  font-family: 'Courier New', monospace;
  background: rgba(0, 15, 40, 0.8);
  border: 1px solid rgba(100, 150, 200, 0.2);
  border-radius: 4px;
  color: #e0f4ff;
  outline: none;
}

.chat-input:focus {
  border-color: rgba(0, 200, 255, 0.4);
}

.chat-input::placeholder {
  color: rgba(160, 210, 255, 0.3);
}

.chat-send-btn {
  padding: 6px 14px;
  font-size: 0.65rem;
  font-family: 'Courier New', monospace;
  background: rgba(0, 200, 255, 0.15);
  border: 1px solid rgba(0, 200, 255, 0.3);
  color: #00e5ff;
  border-radius: 4px;
  cursor: pointer;
  transition: all 0.2s;
}

.chat-send-btn:hover:not(:disabled) {
  background: rgba(0, 200, 255, 0.25);
}

.chat-send-btn:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}

.typing .loading-dots {
  animation: pulse 1.5s infinite;
}

/* Loading dots animation */
.loading-dots {
  animation: pulse 1.5s infinite;
}

@keyframes pulse {
  0%, 100% { opacity: 0.3; }
  50% { opacity: 1; }
}

/* Footer */
.ai-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 6px 8px;
  border-top: 1px solid rgba(0, 200, 255, 0.15);
  flex-shrink: 0;
}

.refresh-btn {
  padding: 4px 12px;
  font-size: 0.65rem;
  font-family: 'Courier New', monospace;
  background: rgba(0, 200, 255, 0.1);
  border: 1px solid rgba(0, 200, 255, 0.3);
  color: #00e5ff;
  border-radius: 3px;
  cursor: pointer;
  transition: all 0.2s;
}

.refresh-btn:hover:not(:disabled) {
  background: rgba(0, 200, 255, 0.2);
}

.refresh-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.refresh-time {
  font-size: 0.55rem;
  color: rgba(160, 210, 255, 0.35);
}

.empty-state {
  text-align: center;
  padding: 30px 10px;
  color: rgba(160, 210, 255, 0.3);
  font-size: 0.75rem;
}

/* 滚动条 */
.ai-content::-webkit-scrollbar {
  width: 4px;
}

.ai-content::-webkit-scrollbar-track {
  background: transparent;
}

.ai-content::-webkit-scrollbar-thumb {
  background: rgba(0, 200, 255, 0.2);
  border-radius: 2px;
}
</style>
