<template>
  <div class="screen">
    <!-- ── Header ── -->
    <header class="hdr">
      <span class="hdr-logo">⬡ RESCUE MESH</span>
      <span class="hdr-sub">省级应急指挥中心 · 实时态势</span>
      <div class="hdr-right">
        <span :class="['conn-dot', connected ? 'on' : 'off']"></span>
        <span class="conn-text">{{ connected ? '实时连接' : '连接断开' }}</span>
        <span class="hdr-badge">⚠ 待救援 {{ activeCount }}</span>
        <span class="hdr-time">{{ clock }}</span>
      </div>
    </header>
    <!-- ── Main Grid ── -->
    <main class="grid">
      <AlertFeed />
      <MapComponent />
      <StatsComponent />
    </main>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { useSocket } from './composables/useSocket'
import AlertFeed     from './components/AlertFeed.vue'
import MapComponent  from './components/MapComponent.vue'
import StatsComponent from './components/StatsComponent.vue'

const { connected, activeCount, connect, fetchActive, disconnect } = useSocket()

const clock = ref('')
let clockTimer = null

function updateClock() {
  clock.value = new Date().toLocaleString('zh-CN', {
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
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
  background: #000a1a;
  color: #e0f4ff;
  font-family: 'Courier New', monospace;
  user-select: none;
}
.hdr {
  display: flex;
  align-items: center;
  gap: 16px;
  padding: 8px 20px;
  background: rgba(0, 18, 45, 0.97);
  border-bottom: 1px solid rgba(0, 200, 255, 0.3);
  flex-shrink: 0;
  height: 48px;
}
.hdr-logo {
  font-size: 1.2rem;
  font-weight: bold;
  color: #00e5ff;
  letter-spacing: 4px;
}
.hdr-sub {
  font-size: 0.75rem;
  color: rgba(0, 200, 255, 0.5);
  letter-spacing: 2px;
}
.hdr-right {
  margin-left: auto;
  display: flex;
  align-items: center;
  gap: 12px;
  font-size: 0.8rem;
}
.conn-dot {
  width: 9px; height: 9px;
  border-radius: 50%;
  display: inline-block;
  flex-shrink: 0;
}
.conn-dot.on  { background: #00ff88; box-shadow: 0 0 8px #00ff88; animation: blink 2s infinite; }
.conn-dot.off { background: #ff3333; box-shadow: 0 0 8px #ff3333; }
.conn-text { color: rgba(180, 230, 255, 0.7); }
.hdr-badge {
  background: rgba(255, 50, 50, 0.15);
  border: 1px solid rgba(255, 80, 80, 0.5);
  padding: 3px 10px;
  border-radius: 4px;
  color: #ff6b6b;
  font-weight: bold;
}
.hdr-time { color: rgba(0, 200, 255, 0.6); font-size: 0.75rem; letter-spacing: 1px; }
.grid {
  flex: 1;
  display: grid;
  grid-template-columns: 22% 1fr 22%;
  gap: 10px;
  padding: 10px;
  overflow: hidden;
  min-height: 0;
}
</style>
