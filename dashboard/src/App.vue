<template>
  <div class="screen">
    <header class="hdr">
      <div>
        <span class="hdr-logo">RESCUE MESH</span>
        <span class="hdr-sub">应急指挥中心 · 实时态势</span>
      </div>
      <div class="hdr-right">
        <div class="conn-wrap">
          <span :class="['conn-dot', connected ? 'on' : 'off']"></span>
          <span class="conn-text">{{ connected ? '实时连接' : '连接断开' }}</span>
          <span v-if="connectionError" class="conn-error">{{ connectionError }}</span>
        </div>
        <span class="hdr-badge">待救援 {{ activeCount }}</span>
        <span class="hdr-time">{{ clock }}</span>
      </div>
    </header>

    <main class="grid">
      <AlertFeed />
      <MapComponent />
      <StatsComponent />
    </main>
  </div>
</template>

<script setup>
import { onMounted, onUnmounted, ref } from 'vue'
import { useSocket } from './composables/useSocket'
import AlertFeed from './components/AlertFeed.vue'
import MapComponent from './components/MapComponent.vue'
import StatsComponent from './components/StatsComponent.vue'

const { connected, connectionError, activeCount, connect, fetchActive, disconnect } = useSocket()

const clock = ref('')
let clockTimer = null

function updateClock() {
  clock.value = new Date().toLocaleString('zh-CN', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  })
}

onMounted(async () => {
  updateClock()
  clockTimer = setInterval(updateClock, 1000)
  connect()
  await fetchActive()
})

onUnmounted(() => {
  clearInterval(clockTimer)
  disconnect()
})
</script>

<style scoped>
.screen {
  display: flex;
  flex-direction: column;
  height: 100vh;
  background: radial-gradient(circle at top, rgba(5, 39, 78, 0.42), transparent 42%), #000a1a;
  color: #e0f4ff;
  font-family: 'Courier New', monospace;
  user-select: none;
}

.hdr {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 10px 20px;
  background: rgba(0, 18, 45, 0.97);
  border-bottom: 1px solid rgba(0, 200, 255, 0.3);
  flex-shrink: 0;
  min-height: 58px;
}

.hdr-logo {
  display: block;
  font-size: 1.18rem;
  font-weight: 700;
  color: #00e5ff;
  letter-spacing: 0.28em;
}

.hdr-sub {
  display: block;
  margin-top: 4px;
  font-size: 0.74rem;
  color: rgba(0, 200, 255, 0.58);
  letter-spacing: 0.12em;
}

.hdr-right {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
  justify-content: flex-end;
}

.conn-wrap {
  display: flex;
  align-items: center;
  gap: 10px;
  max-width: 420px;
}

.conn-dot {
  width: 9px;
  height: 9px;
  border-radius: 50%;
  display: inline-block;
  flex-shrink: 0;
}

.conn-dot.on {
  background: #00ff88;
  box-shadow: 0 0 8px #00ff88;
  animation: blink 2s infinite;
}

.conn-dot.off {
  background: #ff3333;
  box-shadow: 0 0 8px #ff3333;
}

.conn-text {
  color: rgba(180, 230, 255, 0.78);
  font-size: 0.78rem;
}

.conn-error {
  color: #ff9b9b;
  font-size: 0.72rem;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.hdr-badge {
  background: rgba(255, 50, 50, 0.15);
  border: 1px solid rgba(255, 80, 80, 0.5);
  padding: 4px 10px;
  border-radius: 999px;
  color: #ff6b6b;
  font-weight: 700;
  font-size: 0.78rem;
}

.hdr-time {
  color: rgba(0, 200, 255, 0.6);
  font-size: 0.75rem;
  letter-spacing: 0.08em;
}

.grid {
  flex: 1;
  display: grid;
  grid-template-columns: 24% 1fr 22%;
  gap: 10px;
  padding: 10px;
  overflow: hidden;
  min-height: 0;
}

@media (max-width: 1400px) {
  .grid {
    grid-template-columns: 28% 1fr 26%;
  }
}
</style>
