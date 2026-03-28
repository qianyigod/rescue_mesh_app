<template>
  <div class="panel alert-feed">
    <div class="panel-title">
      <span class="blink-dot"></span>
      实时军情播报
      <span class="count">{{ alerts.length }}</span>
    </div>

    <div class="feed-wrap">
      <TransitionGroup name="slide" tag="div" class="feed-list">
        <div
          v-for="a in alerts.slice(0, 80)"
          :key="`${a.senderMac}|${a.timestamp}`"
          class="feed-item"
        >
          <div class="f-time">{{ fmtTime(a.timestamp) }}</div>
          <div class="f-body">
            <span class="f-icon">⚠</span>
            <span v-if="a.medicalProfile?.name" class="name-tag">
              【{{ a.medicalProfile.name }}】
            </span>
            收到 <span class="cyan">{{ fmtCoord(a.location.coordinates) }}</span> 求救<br>
            <span v-if="a.medicalProfile?.age">年龄：{{ a.medicalProfile.age }} | </span>
            血型 <span class="red">{{ getBloodTypeLabel(a) }}</span><br>
            <span v-if="a.medicalProfile?.allergies" class="warning-text">
              ⚠ 过敏：{{ a.medicalProfile.allergies }}
            </span>
            <span v-if="a.medicalProfile?.medicalHistory" class="history-text">
              | 病史：{{ a.medicalProfile.medicalHistory }}
            </span>
            <br>
            中继 <span class="cyan">{{ a.reportedBy?.length ?? 1 }}</span> 次
            <span v-if="a.medicalProfile?.emergencyContact" class="contact-text">
              | 联系：{{ a.medicalProfile.emergencyContact }}
            </span>
          </div>
        </div>
      </TransitionGroup>
    </div>
  </div>
</template>

<script setup>
import { useSocket, BLOOD_LABELS } from '../composables/useSocket'

const { alerts } = useSocket()

function fmtTime(ts) {
  return new Date(ts).toLocaleTimeString('zh-CN', {
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  })
}

function fmtCoord([lng, lat]) {
  return `(${lat.toFixed(3)}, ${lng.toFixed(3)})`
}

function getBloodTypeLabel(alert) {
  // 优先使用 medicalProfile 中的详细血型
  if (alert.medicalProfile?.bloodTypeDetail !== undefined) {
    return BLOOD_LABELS[alert.medicalProfile.bloodTypeDetail] ?? '未知'
  }
  return BLOOD_LABELS[alert.bloodType] ?? '未知'
}
</script>

<style scoped>
.alert-feed { height: 100%; }

.blink-dot {
  width: 8px; height: 8px;
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

.feed-wrap {
  flex: 1;
  overflow-y: auto;
  padding: 6px;
  min-height: 0;
}

.feed-list {
  display: flex;
  flex-direction: column;
  gap: 5px;
}

.feed-item {
  background: rgba(255, 20, 20, 0.04);
  border: 1px solid rgba(255, 50, 50, 0.18);
  border-left: 3px solid rgba(255, 50, 50, 0.7);
  border-radius: 4px;
  padding: 7px 10px;
  font-size: 0.73rem;
  line-height: 1.65;
}

.f-time {
  font-size: 0.65rem;
  color: rgba(150, 200, 255, 0.45);
  margin-bottom: 3px;
}

.f-body { color: rgba(190, 225, 255, 0.8); }
.f-icon { color: #ff6b6b; margin-right: 3px; }
.cyan   { color: #00e5ff; font-weight: bold; }
.red    { color: #ff8080; font-weight: bold; }
.name-tag { color: #00ff88; font-weight: bold; }
.warning-text { color: #ffa500; font-weight: bold; }
.history-text { color: #87ceeb; }
.contact-text { color: #dda0dd; }

/* TransitionGroup slide-in */
.slide-enter-active { transition: all 0.28s ease; }
.slide-enter-from   { opacity: 0; transform: translateY(-16px); }
.slide-leave-active { transition: all 0.2s ease; }
.slide-leave-to     { opacity: 0; transform: translateX(-10px); }
</style>
