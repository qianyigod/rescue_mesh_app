import { ref, reactive } from 'vue'
import { io } from 'socket.io-client'

const SOCKET_URL = import.meta.env.VITE_SOCKET_URL || 'http://101.35.52.133:3000'
const API_BASE   = import.meta.env.VITE_API_BASE   || 'http://101.35.52.133:3000'

// ── 血型映射 ────────────────────────────────────────────────
export const BLOOD_LABELS = { '-1': '未知', 0: 'A型', 1: 'B型', 2: 'AB型', 3: 'O型' }
export const BLOOD_COLORS = { '-1': '#9966FF', 0: '#FF6B6B', 1: '#4BC0C0', 2: '#FFCE56', 3: '#00E5FF' }

// ── 单例响应式状态（跨组件共享）────────────────────────────
const connected   = ref(false)
const alerts      = ref([])           // 全部告警，最新的在 index 0
const activeCount = ref(0)
const bloodCounts = reactive({ '-1': 0, '0': 0, '1': 0, '2': 0, '3': 0 })
// hourlyCounts[0]=11小时前，hourlyCounts[11]=当前小时
const hourlyCounts = ref(Array(12).fill(0))// 新增：医疗档案统计
const medicalStats = reactive({
  totalWithProfile: 0,  // 有医疗档案的人数
  allergyCount: 0,      // 有过敏史的人数
  historyCount: 0,      // 有病史的人数
})
let socket = null

// ── 内部：处理一条新告警 ───────────────────────────────────
function pushAlert(sos) {
  alerts.value.unshift(sos)
  if (alerts.value.length > 300) alerts.value.pop()

  if (sos.status === 'active') activeCount.value++

  const bt = String(sos.bloodType ?? -1)
  bloodCounts[bt] = (bloodCounts[bt] || 0) + 1

  const diffH = Math.floor((Date.now() - new Date(sos.timestamp)) / 3_600_000)
  if (diffH >= 0 && diffH < 12) {
    const arr = [...hourlyCounts.value]
    arr[11 - diffH]++
    hourlyCounts.value = arr
  }

  // 更新医疗档案统计
  if (sos.medicalProfile) {
    const mp = sos.medicalProfile
    if (mp.name || mp.age) medicalStats.totalWithProfile++
    if (mp.allergies) medicalStats.allergyCount++
    if (mp.medicalHistory) medicalStats.historyCount++
  }
}

// ── 公开 composable ────────────────────────────────────────
export function useSocket() {
  function connect() {
    if (socket) return
    socket = io(SOCKET_URL, { transports: ['websocket', 'polling'] })
    socket.on('connect',        () => { connected.value = true })
    socket.on('disconnect',     () => { connected.value = false })
    socket.on('new_sos_alert',  pushAlert)
  }

  async function fetchActive() {
    try {
      const res  = await fetch(`${API_BASE}/api/sos/active`)
      const json = await res.json()
      ;(json.data || []).forEach(pushAlert)
    } catch (e) {
      console.warn('[fetchActive] 无法加载历史数据:', e.message)
    }
  }

  function disconnect() {
    socket?.disconnect()
    socket = null
  }

  return { 
    connected, 
    alerts, 
    activeCount, 
    bloodCounts, 
    hourlyCounts,
    medicalStats,
    connect, 
    fetchActive, 
    disconnect 
  }
}
