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
            收到 <span class="cyan">{{ fmtCoord(a.location.coordinates) }}</span> 求救<br>
            血型 <span class="red">{{ BLOOD_LABELS[a.bloodType] ?? '未知' }}</span>，
            中继 <span class="cyan">{{ a.reportedBy?.length ?? 1 }}</span> 次
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

/* TransitionGroup slide-in */
.slide-enter-active { transition: all 0.28s ease; }
.slide-enter-from   { opacity: 0; transform: translateY(-16px); }
.slide-leave-active { transition: all 0.2s ease; }
.slide-leave-to     { opacity: 0; transform: translateX(-10px); }
</style>
