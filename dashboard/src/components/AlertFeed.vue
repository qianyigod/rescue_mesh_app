<template>
  <div class="panel alert-feed">
    <div class="panel-title">
      <span class="blink-dot"></span>
      实时告警流
      <span class="count">{{ alerts.length }}</span>
    </div>

    <div class="feed-toolbar">
      <div class="toolbar-tip">
        点击告警可在地图上快速定位，右侧按钮可直接删除测试数据。
      </div>
      <div v-if="selectedAlert" class="focus-chip">
        当前聚焦：{{ selectedAlert.medicalProfile?.name || selectedAlert.senderMac }}
      </div>
    </div>

    <div class="feed-wrap">
      <TransitionGroup name="slide" tag="div" class="feed-list">
        <button
          v-for="alert in alerts.slice(0, 120)"
          :key="alert._id"
          type="button"
          class="feed-item"
          :class="{ active: selectedAlertId === alert._id }"
          @click="handleSelect(alert)"
        >
          <div class="feed-head">
            <div class="f-time">{{ fmtTime(alert.timestamp) }}</div>
            <div class="feed-actions">
              <span class="confidence">中继 {{ alert.reportedBy?.length || 1 }}</span>
              <button
                type="button"
                class="action-btn locate"
                @click.stop="handleSelect(alert)"
              >
                定位
              </button>
              <button
                type="button"
                class="action-btn delete"
                :disabled="deletingIds.includes(alert._id)"
                @click.stop="handleDelete(alert)"
              >
                {{ deletingIds.includes(alert._id) ? '删除中...' : '删除' }}
              </button>
            </div>
          </div>

          <div class="f-body">
            <div class="title-row">
              <span class="f-icon">SOS</span>
              <span class="name-tag">{{ alert.medicalProfile?.name || alert.senderMac }}</span>
              <span class="blood-pill">{{ getBloodTypeLabel(alert) }}</span>
            </div>
            <div class="meta-row">位置 {{ fmtCoord(alert.location.coordinates) }}</div>
            <div class="meta-row">
              {{ alert.medicalProfile?.age ? `年龄 ${alert.medicalProfile.age}` : '年龄未知' }}
              <span v-if="alert.medicalProfile?.emergencyContact"> | 联系 {{ alert.medicalProfile.emergencyContact }}</span>
            </div>
            <div v-if="alert.medicalProfile?.allergies" class="warning-text">
              过敏：{{ alert.medicalProfile.allergies }}
            </div>
            <div v-if="alert.medicalProfile?.medicalHistory" class="history-text">
              病史：{{ alert.medicalProfile.medicalHistory }}
            </div>
          </div>
        </button>
      </TransitionGroup>

      <div v-if="!alerts.length" class="empty-state">
        暂无告警数据，等待新的 SOS 上报。
      </div>
    </div>
  </div>
</template>

<script setup>
import { BLOOD_LABELS, useSocket } from '../composables/useSocket'

const {
  alerts,
  selectedAlert,
  selectedAlertId,
  deletingIds,
  selectAlert,
  deleteAlert,
} = useSocket()

function fmtTime(timestamp) {
  return new Date(timestamp).toLocaleString('zh-CN', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  })
}

function fmtCoord([lng, lat]) {
  return `${lat.toFixed(4)}, ${lng.toFixed(4)}`
}

function getBloodTypeLabel(alert) {
  if (alert.medicalProfile?.bloodTypeDetail !== undefined) {
    return BLOOD_LABELS[alert.medicalProfile.bloodTypeDetail] ?? '未知'
  }
  return BLOOD_LABELS[alert.bloodType] ?? '未知'
}

function handleSelect(alert) {
  selectAlert(alert)
}

async function handleDelete(alert) {
  const label = alert.medicalProfile?.name || alert.senderMac
  const confirmed = window.confirm(`确定删除 ${label} 的这条 SOS 数据吗？`)
  if (!confirmed) {
    return
  }

  try {
    await deleteAlert(alert)
  } catch (error) {
    window.alert(`删除失败：${error.message}`)
  }
}
</script>

<style scoped>
.alert-feed {
  height: 100%;
}

.blink-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: #ff3333;
  display: inline-block;
  flex-shrink: 0;
  animation: blink 1.4s infinite;
  box-shadow: 0 0 6px #ff3333;
}

.count {
  margin-left: auto;
  background: rgba(255, 50, 50, 0.15);
  border: 1px solid rgba(255, 80, 80, 0.35);
  border-radius: 10px;
  padding: 1px 8px;
  font-size: 0.68rem;
  color: #ff8080;
}

.feed-toolbar {
  padding: 10px 14px 6px;
  border-bottom: 1px solid rgba(0, 200, 255, 0.12);
}

.toolbar-tip {
  color: rgba(170, 220, 255, 0.62);
  font-size: 0.7rem;
  line-height: 1.5;
}

.focus-chip {
  margin-top: 8px;
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 5px 10px;
  border-radius: 999px;
  background: rgba(0, 229, 255, 0.12);
  border: 1px solid rgba(0, 229, 255, 0.22);
  color: #8eeaff;
  font-size: 0.7rem;
}

.feed-wrap {
  flex: 1;
  overflow-y: auto;
  padding: 8px;
  min-height: 0;
}

.feed-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.feed-item {
  width: 100%;
  text-align: left;
  background: rgba(255, 20, 20, 0.04);
  border: 1px solid rgba(255, 50, 50, 0.18);
  border-left: 3px solid rgba(255, 50, 50, 0.7);
  border-radius: 8px;
  padding: 10px 12px;
  font-size: 0.73rem;
  line-height: 1.65;
  color: rgba(190, 225, 255, 0.8);
  cursor: pointer;
  transition: transform 0.18s ease, border-color 0.18s ease, box-shadow 0.18s ease;
}

.feed-item:hover,
.feed-item.active {
  transform: translateX(3px);
  border-color: rgba(0, 229, 255, 0.45);
  box-shadow: 0 0 0 1px rgba(0, 229, 255, 0.18), 0 14px 26px rgba(0, 10, 30, 0.22);
}

.feed-head {
  display: flex;
  justify-content: space-between;
  gap: 10px;
  align-items: center;
  margin-bottom: 6px;
}

.f-time {
  font-size: 0.65rem;
  color: rgba(150, 200, 255, 0.45);
}

.feed-actions {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-wrap: wrap;
  justify-content: flex-end;
}

.confidence {
  padding: 1px 8px;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.05);
  color: #9fdfff;
  font-size: 0.64rem;
}

.action-btn {
  border: 1px solid transparent;
  border-radius: 999px;
  padding: 3px 9px;
  font-size: 0.64rem;
  cursor: pointer;
  color: #e9fbff;
  background: rgba(255, 255, 255, 0.08);
}

.action-btn.locate {
  border-color: rgba(0, 229, 255, 0.24);
}

.action-btn.delete {
  border-color: rgba(255, 107, 107, 0.24);
  color: #ffb1b1;
}

.action-btn:disabled {
  opacity: 0.55;
  cursor: wait;
}

.title-row {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
  margin-bottom: 2px;
}

.f-icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 36px;
  padding: 1px 8px;
  border-radius: 999px;
  color: #ffdbdb;
  background: rgba(255, 90, 90, 0.14);
  font-size: 0.63rem;
  letter-spacing: 0.08em;
}

.name-tag {
  color: #00ff88;
  font-weight: 700;
}

.blood-pill {
  padding: 1px 8px;
  border-radius: 999px;
  background: rgba(0, 229, 255, 0.14);
  color: #7ee8ff;
  font-weight: 700;
}

.meta-row {
  color: rgba(190, 225, 255, 0.82);
}

.warning-text {
  color: #ffbf69;
  font-weight: 700;
}

.history-text {
  color: #87ceeb;
}

.empty-state {
  padding: 24px 14px;
  text-align: center;
  color: rgba(170, 220, 255, 0.55);
  font-size: 0.78rem;
}

.slide-enter-active {
  transition: all 0.28s ease;
}

.slide-enter-from {
  opacity: 0;
  transform: translateY(-16px);
}

.slide-leave-active {
  transition: all 0.2s ease;
}

.slide-leave-to {
  opacity: 0;
  transform: translateX(-10px);
}
</style>
