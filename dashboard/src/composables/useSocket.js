import { ref, reactive } from 'vue'
import { io } from 'socket.io-client'

const SOCKET_URL = import.meta.env.VITE_SOCKET_URL || 'http://localhost:3000'
const API_BASE = import.meta.env.VITE_API_BASE || 'http://localhost:3000'
const MAX_ALERTS = 300

export const BLOOD_LABELS = {
  '-1': '未知',
  0: 'A型',
  1: 'B型',
  2: 'AB型',
  3: 'O型',
}

export const BLOOD_COLORS = {
  '-1': '#9966FF',
  0: '#FF6B6B',
  1: '#4BC0C0',
  2: '#FFCE56',
  3: '#00E5FF',
}

const connected = ref(false)
const alerts = ref([])
const activeCount = ref(0)
const bloodCounts = reactive({ '-1': 0, '0': 0, '1': 0, '2': 0, '3': 0 })
const hourlyCounts = ref(Array(12).fill(0))
const medicalStats = reactive({
  totalWithProfile: 0,
  allergyCount: 0,
  historyCount: 0,
})

const searchState = reactive({
  keyword: '',
  blood: '',
  time: '',
  activeKeys: new Set(),
  hasFilter: false,
})

let socket = null
const alertKeyIndex = new Map()

function getAlertKey(sos) {
  if (!sos) return ''
  if (sos._id) return String(sos._id)

  const senderMac = String(sos.senderMac || '').trim()
  const date = sos.timestamp ? new Date(sos.timestamp) : null
  const timestamp = date && !Number.isNaN(date.getTime())
    ? date.toISOString()
    : String(sos.timestamp || '')

  return `${senderMac}|${timestamp}`
}

function sortAlertsByTimeDesc(list) {
  return [...list].sort((a, b) => {
    const aTime = new Date(a?.timestamp || 0).getTime()
    const bTime = new Date(b?.timestamp || 0).getTime()
    return bTime - aTime
  })
}

function rebuildAlertIndex() {
  alertKeyIndex.clear()
  alerts.value.forEach((item, index) => {
    const key = getAlertKey(item)
    if (key) {
      alertKeyIndex.set(key, index)
    }
  })
}

function resetDerivedStats() {
  activeCount.value = 0

  Object.keys(bloodCounts).forEach((key) => {
    bloodCounts[key] = 0
  })

  medicalStats.totalWithProfile = 0
  medicalStats.allergyCount = 0
  medicalStats.historyCount = 0
}

function recomputeDerivedStats() {
  resetDerivedStats()

  alerts.value.forEach((sos) => {
    if (sos?.status === 'active') {
      activeCount.value++
    }

    const bt = String(sos?.bloodType ?? -1)
    bloodCounts[bt] = (bloodCounts[bt] || 0) + 1

    const mp = sos?.medicalProfile
    if (mp) {
      if (mp.name || mp.age) medicalStats.totalWithProfile++
      if (mp.allergies) medicalStats.allergyCount++
      if (mp.medicalHistory) medicalStats.historyCount++
    }
  })
}

function trimAlerts() {
  if (alerts.value.length <= MAX_ALERTS) return
  alerts.value = alerts.value.slice(0, MAX_ALERTS)
  rebuildAlertIndex()
}

function removeAlertByKey(key) {
  const existingIndex = alertKeyIndex.get(key)
  if (existingIndex == null) return

  alerts.value.splice(existingIndex, 1)
  rebuildAlertIndex()
  recomputeDerivedStats()
}

function upsertAlert(sos) {
  const key = getAlertKey(sos)
  if (!key) return

  if (sos?.status && sos.status !== 'active') {
    removeAlertByKey(key)
    return
  }

  const next = { ...sos }
  const existingIndex = alertKeyIndex.get(key)

  if (existingIndex != null) {
    const prev = alerts.value[existingIndex] || {}
    alerts.value.splice(existingIndex, 1, { ...prev, ...next })
  } else {
    alerts.value.unshift(next)
  }

  alerts.value = sortAlertsByTimeDesc(alerts.value)
  trimAlerts()
  rebuildAlertIndex()
  recomputeDerivedStats()
}

function replaceAlerts(list) {
  const merged = new Map()

  ;(Array.isArray(list) ? list : []).forEach((item) => {
    const key = getAlertKey(item)
    if (!key) return

    const prev = merged.get(key) || {}
    merged.set(key, { ...prev, ...item })
  })

  alerts.value = sortAlertsByTimeDesc(Array.from(merged.values())).slice(0, MAX_ALERTS)
  rebuildAlertIndex()
  recomputeDerivedStats()
}

export function useSocket() {
  function connect() {
    if (socket) return
    socket = io(SOCKET_URL, { transports: ['websocket', 'polling'] })
    socket.on('connect', () => { connected.value = true })
    socket.on('disconnect', () => { connected.value = false })
    socket.on('new_sos_alert', upsertAlert)
  }

  async function fetchActive() {
    try {
      const res = await fetch(`${API_BASE}/api/sos/active`)
      const json = await res.json()
      replaceAlerts(json.data || [])
    } catch (e) {
      console.warn('[fetchActive] 无法加载活跃告警:', e.message)
    }
  }

  async function fetchHourlyStats() {
    try {
      const res = await fetch(`${API_BASE}/api/sos/hourly-stats`)
      const json = await res.json()
      if (json.data && Array.isArray(json.data)) {
        hourlyCounts.value = json.data
      }
    } catch (e) {
      console.warn('[fetchHourlyStats] 无法加载趋势数据:', e.message)
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
    searchState,
    connect,
    fetchActive,
    fetchHourlyStats,
    disconnect,
    upsertAlert,
  }
}
