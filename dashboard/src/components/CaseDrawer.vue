<template>
  <Transition name="drawer-fade">
    <aside v-if="selectedAlert" class="case-drawer">
      <div class="panel drawer-panel">
        <div class="panel-title drawer-title">
          <span>案件详情</span>
          <button class="drawer-close" @click="handleCloseDrawer">关闭</button>
        </div>

        <div class="drawer-body">
          <div v-if="loading" class="drawer-loading">案件详情加载中...</div>
          <div v-else-if="currentCase" class="drawer-sections">
            <section class="drawer-section hero">
              <div class="hero-head">
                <div>
                  <div class="hero-name">{{ currentCase.medicalProfile?.name || currentCase.senderMac || '未知案件' }}</div>
                  <div class="hero-meta">{{ bloodLabel(currentCase) }} · {{ statusLabel(currentCase.status) }}</div>
                </div>
                <span :class="['workflow-badge', currentCase.workflowStatus || 'reported']">
                  {{ workflowLabel(currentCase.workflowStatus) }}
                </span>
              </div>
              <div class="hero-grid">
                <div class="hero-item">
                  <span>求救时间</span>
                  <strong>{{ formatDateTime(currentCase.timestamp) }}</strong>
                </div>
                <div class="hero-item">
                  <span>接警人员</span>
                  <strong>{{ currentCase.acknowledgedBy || '未接警' }}</strong>
                </div>
                <div class="hero-item">
                  <span>中继次数</span>
                  <strong>{{ currentCase.reportedBy?.length ?? 1 }}</strong>
                </div>
                <div class="hero-item">
                  <span>置信度</span>
                  <strong>{{ currentCase.confidence ?? currentCase.reportedBy?.length ?? 1 }}</strong>
                </div>
              </div>
            </section>

            <section class="drawer-section">
              <div class="section-title">基本信息</div>
              <div class="info-list">
                <div class="info-row">
                  <span>设备 MAC</span>
                  <strong>{{ currentCase.senderMac }}</strong>
                </div>
                <div class="info-row">
                  <span>年龄</span>
                  <strong>{{ currentCase.medicalProfile?.age || '未知' }}</strong>
                </div>
                <div class="info-row">
                  <span>坐标</span>
                  <strong>{{ formatCoord(currentCase.location?.coordinates) }}</strong>
                </div>
                <div class="info-row">
                  <span>紧急联系人</span>
                  <strong>{{ currentCase.medicalProfile?.emergencyContact || '未填写' }}</strong>
                </div>
                <div class="info-row full">
                  <span>过敏信息</span>
                  <strong>{{ currentCase.medicalProfile?.allergies || '无' }}</strong>
                </div>
                <div class="info-row full">
                  <span>病史</span>
                  <strong>{{ currentCase.medicalProfile?.medicalHistory || '无' }}</strong>
                </div>
              </div>
            </section>

            <section class="drawer-section">
              <div class="section-title">调度摘要</div>
              <div class="info-list">
                <div class="info-row">
                  <span>救援队</span>
                  <strong>{{ currentCase.dispatchInfo?.teamName || '未派单' }}</strong>
                </div>
                <div class="info-row">
                  <span>目标医院</span>
                  <strong>{{ currentCase.dispatchInfo?.hospitalName || '未指定' }}</strong>
                </div>
                <div class="info-row">
                  <span>预计到达</span>
                  <strong>{{ currentCase.dispatchInfo?.etaMinutes ?? '--' }} 分钟</strong>
                </div>
                <div class="info-row">
                  <span>结案结果</span>
                  <strong>{{ closeResultLabel(currentCase.closureInfo?.resultStatus) }}</strong>
                </div>
              </div>
            </section>

            <section class="drawer-section">
              <div class="section-title">处置动作</div>
              <div class="operator-row">
                <label>值班员</label>
                <input v-model.trim="operatorName" type="text" placeholder="输入当前操作员名称" />
              </div>
              <div v-if="actionError" class="action-error">{{ actionError }}</div>

              <div class="action-card">
                <div class="action-head">
                  <span>接警确认</span>
                  <button class="action-btn" :disabled="!canAcknowledge || actionLoading" @click="submitAcknowledge">
                    {{ actionLoading && pendingAction === 'ack' ? '处理中...' : '确认接警' }}
                  </button>
                </div>
                <textarea v-model.trim="ackNote" rows="2" placeholder="接警备注，例如现场回拨、人员校核结果" />
              </div>

              <div class="action-card">
                <div class="action-head">
                  <span>派单调度</span>
                  <button class="action-btn" :disabled="!canDispatch || actionLoading" @click="submitDispatch">
                    {{ actionLoading && pendingAction === 'dispatch' ? '处理中...' : '提交派单' }}
                  </button>
                </div>
                <div class="action-grid">
                  <input v-model.trim="dispatchForm.teamName" type="text" placeholder="救援队名称" />
                  <input v-model.trim="dispatchForm.hospitalName" type="text" placeholder="目标医院" />
                  <input v-model.trim="dispatchForm.etaMinutes" type="number" min="0" placeholder="ETA 分钟" />
                </div>
                <textarea v-model.trim="dispatchForm.note" rows="2" placeholder="派单备注，例如路线受阻、装备等级" />
              </div>

              <div class="action-card">
                <div class="action-head">
                  <span>结案处理</span>
                  <button class="action-btn danger" :disabled="!canClose || actionLoading" @click="submitClose">
                    {{ actionLoading && pendingAction === 'close' ? '处理中...' : '提交结案' }}
                  </button>
                </div>
                <div class="action-grid close-grid">
                  <select v-model="closeForm.resultStatus">
                    <option value="rescued">已救援</option>
                    <option value="false_alarm">误报</option>
                  </select>
                </div>
                <textarea v-model.trim="closeForm.note" rows="2" placeholder="结案备注，例如已送医、核验误报原因" />
              </div>
            </section>

            <section class="drawer-section timeline-section">
              <div class="section-title">处置时间线</div>
              <div v-if="timeline.length" class="timeline-list">
                <div v-for="item in timeline" :key="item._id || `${item.actionType}-${item.createdAt}`" class="timeline-item">
                  <div class="timeline-time">{{ formatDateTime(item.createdAt) }}</div>
                  <div class="timeline-content">
                    <div class="timeline-head">
                      <span class="timeline-action">{{ actionLabel(item.actionType) }}</span>
                      <span class="timeline-actor">{{ item.actorName || item.actorType || 'system' }}</span>
                    </div>
                    <div class="timeline-meta">
                      <span v-if="item.meta?.teamName">队伍：{{ item.meta.teamName }}</span>
                      <span v-if="item.meta?.hospitalName">医院：{{ item.meta.hospitalName }}</span>
                      <span v-if="item.meta?.etaMinutes != null">ETA：{{ item.meta.etaMinutes }} 分钟</span>
                      <span v-if="item.meta?.resultStatus">结果：{{ closeResultLabel(item.meta.resultStatus) }}</span>
                    </div>
                    <div v-if="item.note" class="timeline-note">{{ item.note }}</div>
                  </div>
                </div>
              </div>
              <div v-else class="drawer-empty">暂无时间线数据</div>
            </section>
          </div>
          <div v-else class="drawer-empty">未找到案件详情</div>
        </div>
      </div>
    </aside>
  </Transition>
</template>

<script setup>
import { computed, reactive, ref, watch } from 'vue'
import { useSocket, BLOOD_LABELS, WORKFLOW_LABELS, getEffectiveBloodType } from '../composables/useSocket'
import { requestJson } from '../utils/api'

const {
  selectedAlert,
  setSelectedAlertSnapshot,
  clearSelectedAlert,
} = useSocket()

const detail = ref(null)
const timeline = ref([])
const loading = ref(false)
const actionLoading = ref(false)
const pendingAction = ref('')
const actionError = ref('')
const operatorName = ref('指挥中心')
const ackNote = ref('')
const dispatchForm = reactive({
  teamName: '',
  hospitalName: '',
  etaMinutes: '',
  note: '',
})
const closeForm = reactive({
  resultStatus: 'rescued',
  note: '',
})

const currentCase = computed(() => detail.value || selectedAlert.value)
const currentCaseId = computed(() => currentCase.value?._id || '')
const canAcknowledge = computed(() => currentCase.value?.status === 'active' && currentCase.value?.workflowStatus === 'reported')
const canDispatch = computed(() => currentCase.value?.status === 'active')
const canClose = computed(() => currentCase.value?.status === 'active')

watch(
  () => selectedAlert.value?._id || '',
  async (id) => {
    actionError.value = ''
    if (!id) {
      detail.value = null
      timeline.value = []
      ackNote.value = ''
      dispatchForm.teamName = ''
      dispatchForm.hospitalName = ''
      dispatchForm.etaMinutes = ''
      dispatchForm.note = ''
      closeForm.resultStatus = 'rescued'
      closeForm.note = ''
      return
    }
    ackNote.value = ''
    dispatchForm.teamName = ''
    dispatchForm.hospitalName = ''
    dispatchForm.etaMinutes = ''
    dispatchForm.note = ''
    closeForm.resultStatus = 'rescued'
    closeForm.note = ''
    await loadDetail(id)
  },
  { immediate: true },
)

watch(currentCase, (value) => {
  if (!value) return
  if (!dispatchForm.teamName && value.dispatchInfo?.teamName) {
    dispatchForm.teamName = value.dispatchInfo.teamName
  }
  if (!dispatchForm.hospitalName && value.dispatchInfo?.hospitalName) {
    dispatchForm.hospitalName = value.dispatchInfo.hospitalName
  }
  if (!dispatchForm.etaMinutes && value.dispatchInfo?.etaMinutes != null) {
    dispatchForm.etaMinutes = String(value.dispatchInfo.etaMinutes)
  }
}, { immediate: true })

async function loadDetail(id = currentCaseId.value) {
  if (!id) return
  loading.value = true
  try {
    const json = await requestJson(`/api/sos/${id}/detail`)
    detail.value = json.data?.sos || null
    timeline.value = Array.isArray(json.data?.timeline) ? json.data.timeline : []
    if (detail.value) {
      setSelectedAlertSnapshot(detail.value)
    }
  } catch (error) {
    actionError.value = error.message
  } finally {
    loading.value = false
  }
}

async function submitAction(action, payload) {
  const id = currentCaseId.value
  if (!id) return

  actionLoading.value = true
  pendingAction.value = action
  actionError.value = ''

  try {
    const json = await requestJson(`/api/sos/${id}/${action}`, {
      method: 'POST',
      body: JSON.stringify(payload),
    })

    const nextSos = json.data?.sos || null
    const nextTimelineItem = json.data?.timelineItem || null
    if (nextSos) {
      detail.value = nextSos
      setSelectedAlertSnapshot(nextSos)
    }
    if (nextTimelineItem) {
      timeline.value = [nextTimelineItem, ...timeline.value.filter((item) => item._id !== nextTimelineItem._id)]
    }
    await loadDetail(id)
  } catch (error) {
    actionError.value = error.message
  } finally {
    actionLoading.value = false
    pendingAction.value = ''
  }
}

function submitAcknowledge() {
  submitAction('acknowledge', {
    operatorName: operatorName.value,
    note: ackNote.value,
  })
}

function submitDispatch() {
  submitAction('dispatch', {
    operatorName: operatorName.value,
    teamName: dispatchForm.teamName,
    hospitalName: dispatchForm.hospitalName,
    etaMinutes: dispatchForm.etaMinutes,
    note: dispatchForm.note,
  })
}

function submitClose() {
  submitAction('close', {
    operatorName: operatorName.value,
    resultStatus: closeForm.resultStatus,
    note: closeForm.note,
  })
}

function handleCloseDrawer() {
  detail.value = null
  timeline.value = []
  actionError.value = ''
  clearSelectedAlert()
}

function workflowLabel(status) {
  return WORKFLOW_LABELS[status] || '待处理'
}

function bloodLabel(record) {
  return BLOOD_LABELS[String(getEffectiveBloodType(record))] || '未知'
}

function statusLabel(status) {
  if (status === 'rescued') return '已救援'
  if (status === 'false_alarm') return '误报'
  return '待救援'
}

function closeResultLabel(status) {
  if (status === 'rescued') return '已救援'
  if (status === 'false_alarm') return '误报'
  return '未结案'
}

function actionLabel(action) {
  const labels = {
    reported: '案件上报',
    relay_merged: '中继补报',
    acknowledged: '接警确认',
    dispatch: '调度派单',
    closed: '案件结案',
  }
  return labels[action] || action
}

function formatDateTime(value) {
  if (!value) return '--'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return '--'
  return date.toLocaleString('zh-CN', {
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  })
}

function formatCoord(coords = []) {
  const [lng, lat] = Array.isArray(coords) ? coords : []
  if (!Number.isFinite(lng) || !Number.isFinite(lat)) return '--'
  return `${lat.toFixed(4)}, ${lng.toFixed(4)}`
}
</script>

<style scoped>
.case-drawer {
  position: absolute;
  top: 58px;
  right: 10px;
  bottom: 10px;
  width: min(380px, 34vw);
  min-width: 320px;
  z-index: 40;
  pointer-events: none;
}

.drawer-panel {
  height: 100%;
  pointer-events: auto;
  box-shadow: 0 18px 60px rgba(0, 0, 0, 0.45);
}

.drawer-title {
  justify-content: space-between;
}

.drawer-close {
  border: 1px solid rgba(0, 229, 255, 0.22);
  background: rgba(0, 229, 255, 0.08);
  color: #9cefff;
  border-radius: 999px;
  padding: 4px 10px;
  font-size: 0.68rem;
  cursor: pointer;
}

.drawer-body {
  flex: 1;
  overflow-y: auto;
  padding: 14px;
}

.drawer-loading,
.drawer-empty {
  display: grid;
  place-items: center;
  min-height: 160px;
  color: rgba(180, 220, 255, 0.55);
  font-size: 0.82rem;
}

.drawer-sections {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.drawer-section {
  background: rgba(5, 23, 44, 0.8);
  border: 1px solid rgba(0, 229, 255, 0.12);
  border-radius: 10px;
  padding: 12px;
}

.hero {
  background: linear-gradient(135deg, rgba(2, 27, 56, 0.95), rgba(14, 46, 76, 0.82));
}

.hero-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 10px;
}

.hero-name {
  color: #e8fbff;
  font-size: 1.02rem;
  font-weight: bold;
}

.hero-meta {
  margin-top: 4px;
  color: rgba(163, 217, 255, 0.72);
  font-size: 0.74rem;
}

.workflow-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 74px;
  height: 28px;
  padding: 0 10px;
  border-radius: 999px;
  font-size: 0.7rem;
  letter-spacing: 1px;
  border: 1px solid rgba(0, 229, 255, 0.24);
  color: #9cefff;
  background: rgba(0, 229, 255, 0.08);
}

.workflow-badge.dispatching,
.workflow-badge.acknowledged {
  color: #ffe97d;
  border-color: rgba(255, 233, 125, 0.34);
  background: rgba(255, 233, 125, 0.08);
}

.workflow-badge.closed {
  color: #8bffb3;
  border-color: rgba(139, 255, 179, 0.28);
  background: rgba(139, 255, 179, 0.08);
}

.hero-grid,
.action-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 8px;
}

.hero-grid {
  margin-top: 12px;
}

.hero-item,
.info-row {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.hero-item span,
.info-row span,
.section-title,
.operator-row label,
.timeline-time {
  color: rgba(156, 206, 244, 0.58);
  font-size: 0.68rem;
  letter-spacing: 1px;
}

.hero-item strong,
.info-row strong {
  color: #ecfbff;
  font-size: 0.82rem;
  font-weight: 600;
  word-break: break-all;
}

.section-title {
  margin-bottom: 10px;
}

.info-list {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px 12px;
}

.info-row.full {
  grid-column: 1 / -1;
}

.operator-row {
  display: flex;
  flex-direction: column;
  gap: 6px;
  margin-bottom: 10px;
}

.operator-row input,
.action-grid input,
.action-grid select,
.action-card textarea {
  width: 100%;
  border: 1px solid rgba(0, 229, 255, 0.16);
  border-radius: 8px;
  background: rgba(2, 16, 31, 0.92);
  color: #e3fbff;
  padding: 9px 10px;
  font-size: 0.78rem;
  outline: none;
}

.action-card textarea {
  resize: vertical;
  min-height: 60px;
}

.action-card {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 10px;
  border-radius: 8px;
  background: rgba(1, 14, 28, 0.66);
  border: 1px solid rgba(0, 229, 255, 0.1);
}

.action-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  color: #d7f6ff;
  font-size: 0.8rem;
}

.action-btn {
  height: 30px;
  padding: 0 12px;
  border: 1px solid rgba(0, 229, 255, 0.24);
  background: rgba(0, 229, 255, 0.1);
  color: #9cefff;
  border-radius: 999px;
  cursor: pointer;
  font-size: 0.68rem;
}

.action-btn.danger {
  border-color: rgba(255, 107, 107, 0.28);
  background: rgba(255, 107, 107, 0.1);
  color: #ff9d9d;
}

.action-btn:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.action-error {
  margin-bottom: 10px;
  padding: 8px 10px;
  border-radius: 8px;
  border: 1px solid rgba(255, 107, 107, 0.24);
  background: rgba(255, 66, 66, 0.08);
  color: #ff9b9b;
  font-size: 0.74rem;
}

.timeline-section {
  min-height: 180px;
}

.timeline-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.timeline-item {
  display: grid;
  grid-template-columns: 62px 1fr;
  gap: 10px;
}

.timeline-content {
  padding: 10px;
  border-radius: 8px;
  background: rgba(1, 14, 28, 0.66);
  border: 1px solid rgba(0, 229, 255, 0.1);
}

.timeline-head,
.timeline-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.timeline-head {
  align-items: center;
  justify-content: space-between;
  color: #e5fbff;
  font-size: 0.78rem;
}

.timeline-action {
  color: #9cefff;
}

.timeline-actor,
.timeline-meta,
.timeline-note {
  color: rgba(186, 225, 255, 0.68);
  font-size: 0.72rem;
}

.timeline-meta {
  margin-top: 6px;
}

.timeline-note {
  margin-top: 6px;
  line-height: 1.6;
}

.drawer-fade-enter-active,
.drawer-fade-leave-active {
  transition: opacity 0.18s ease, transform 0.18s ease;
}

.drawer-fade-enter-from,
.drawer-fade-leave-to {
  opacity: 0;
  transform: translateX(12px);
}

@media (max-width: 1280px) {
  .case-drawer {
    width: min(360px, 42vw);
  }
}

@media (max-width: 960px) {
  .case-drawer {
    width: calc(100% - 20px);
    min-width: 0;
  }

  .hero-grid,
  .info-list,
  .action-grid {
    grid-template-columns: 1fr;
  }

  .timeline-item {
    grid-template-columns: 1fr;
  }
}
</style>
