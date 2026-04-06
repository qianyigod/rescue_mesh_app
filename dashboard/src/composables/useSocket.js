import { computed, reactive, ref } from 'vue'
import { io } from 'socket.io-client'

function resolveServerBaseUrl() {
  const envSocketUrl = import.meta.env.VITE_SOCKET_URL?.trim()
  const envApiBase = import.meta.env.VITE_API_BASE?.trim()

  if (envSocketUrl || envApiBase) {
    return {
      socketUrl: envSocketUrl || envApiBase,
      apiBase: envApiBase || envSocketUrl,
    }
  }

  if (typeof window === 'undefined') {
    return {
      socketUrl: 'http://101.35.52.133:3000',
      apiBase: 'http://101.35.52.133:3000',
    }
  }

  const { hostname, origin } = window.location
  const isLocalDev = hostname === 'localhost' || hostname === '127.0.0.1'

  return {
    socketUrl: isLocalDev ? 'http://localhost:3000' : origin,
    apiBase: isLocalDev ? 'http://localhost:3000' : origin,
  }
}

const { socketUrl: SOCKET_URL, apiBase: API_BASE } = resolveServerBaseUrl()
const SOCKET_PATH = import.meta.env.VITE_SOCKET_PATH?.trim() || '/socket.io'

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
const connectionError = ref('')
const alerts = ref([])
const activeCount = ref(0)
const bloodCounts = reactive({ '-1': 0, '0': 0, '1': 0, '2': 0, '3': 0 })
const hourlyCounts = ref(Array(12).fill(0))
const medicalStats = reactive({
  totalWithProfile: 0,
  allergyCount: 0,
  historyCount: 0,
})
const selectedAlertId = ref('')
const deletingIds = ref([])

let socket = null

function getAlertKey(sos) {
  return String(sos?._id ?? sos?.id ?? `${sos?.senderMac ?? 'UNKNOWN'}-${sos?.timestamp ?? 'UNKNOWN'}`)
}

function normalizeAlert(raw) {
  if (!raw?.location?.coordinates || raw.location.coordinates.length !== 2) {
    return null
  }

  return {
    ...raw,
    _id: String(raw._id ?? raw.id ?? getAlertKey(raw)),
    senderMac: raw.senderMac || 'UNKNOWN',
    status: raw.status || 'active',
    reportedBy: Array.isArray(raw.reportedBy) ? raw.reportedBy : [],
    medicalProfile: raw.medicalProfile || {},
  }
}

function resolveBloodType(alert) {
  const detail = alert?.medicalProfile?.bloodTypeDetail
  if (detail !== undefined && detail !== null && detail !== -1) {
    return String(detail)
  }
  return String(alert?.bloodType ?? -1)
}

function recomputeMetrics() {
  activeCount.value = alerts.value.length

  for (const key of Object.keys(bloodCounts)) {
    bloodCounts[key] = 0
  }

  hourlyCounts.value = Array(12).fill(0)
  medicalStats.totalWithProfile = 0
  medicalStats.allergyCount = 0
  medicalStats.historyCount = 0

  for (const alert of alerts.value) {
    const bloodType = resolveBloodType(alert)
    bloodCounts[bloodType] = (bloodCounts[bloodType] || 0) + 1

    const diffHours = Math.floor(
      (Date.now() - new Date(alert.timestamp).getTime()) / 3_600_000,
    )
    if (diffHours >= 0 && diffHours < 12) {
      hourlyCounts.value[11 - diffHours] += 1
    }

    const profile = alert.medicalProfile || {}
    if (profile.name || profile.age) {
      medicalStats.totalWithProfile += 1
    }
    if (profile.allergies) {
      medicalStats.allergyCount += 1
    }
    if (profile.medicalHistory) {
      medicalStats.historyCount += 1
    }
  }
}

function upsertAlert(rawAlert) {
  const alert = normalizeAlert(rawAlert)
  if (!alert) {
    return
  }

  const nextAlerts = [...alerts.value]
  const index = nextAlerts.findIndex((item) => item._id === alert._id)
  if (index >= 0) {
    nextAlerts[index] = { ...nextAlerts[index], ...alert }
  } else {
    nextAlerts.unshift(alert)
  }

  nextAlerts.sort((left, right) => {
    return new Date(right.timestamp).getTime() - new Date(left.timestamp).getTime()
  })

  alerts.value = nextAlerts
  recomputeMetrics()
}

function replaceAlerts(rawAlerts) {
  const nextAlerts = rawAlerts
    .map(normalizeAlert)
    .filter(Boolean)
    .sort((left, right) => {
      return new Date(right.timestamp).getTime() - new Date(left.timestamp).getTime()
    })

  alerts.value = nextAlerts

  if (selectedAlertId.value) {
    const stillSelected = nextAlerts.some((alert) => alert._id === selectedAlertId.value)
    if (!stillSelected) {
      selectedAlertId.value = ''
    }
  }

  recomputeMetrics()
}

function removeAlertById(alertId) {
  const normalizedId = String(alertId)
  alerts.value = alerts.value.filter((alert) => alert._id !== normalizedId)
  deletingIds.value = deletingIds.value.filter((id) => id !== normalizedId)

  if (selectedAlertId.value === normalizedId) {
    selectedAlertId.value = alerts.value[0]?._id || ''
  }

  recomputeMetrics()
}

async function fetchActiveFromServer() {
  const response = await fetch(`${API_BASE}/api/sos/active`, {
    cache: 'no-store',
  })

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`)
  }

  const json = await response.json()
  replaceAlerts(json.data || [])
}

function selectAlert(alertOrId) {
  const alertId = typeof alertOrId === 'string' ? alertOrId : getAlertKey(alertOrId)
  selectedAlertId.value = alertId
}

function clearSelection() {
  selectedAlertId.value = ''
}

async function deleteAlert(alertOrId) {
  const alertId = typeof alertOrId === 'string' ? alertOrId : getAlertKey(alertOrId)
  if (!alertId) {
    return
  }

  if (deletingIds.value.includes(alertId)) {
    return
  }

  deletingIds.value = [...deletingIds.value, alertId]

  try {
    const response = await fetch(`${API_BASE}/api/sos/${alertId}`, {
      method: 'DELETE',
    })

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`)
    }

    removeAlertById(alertId)
  } finally {
    deletingIds.value = deletingIds.value.filter((id) => id !== alertId)
  }
}

function attachSocketListeners(instance) {
  instance.on('connect', () => {
    connected.value = true
    connectionError.value = ''
    console.info('[Socket] Connected:', instance.id)
    void fetchActiveFromServer().catch((error) => {
      console.warn('[Socket] Failed to refresh active SOS data:', error.message)
    })
  })

  instance.on('disconnect', (reason) => {
    connected.value = false
    console.warn('[Socket] Disconnected:', reason)

    if (reason === 'io server disconnect') {
      instance.connect()
    }
  })

  instance.on('connect_error', (error) => {
    connected.value = false
    connectionError.value = error.message
    console.error('[Socket] Connect error:', error.message)
  })

  instance.on('new_sos_alert', upsertAlert)
  instance.on('sos_deleted', (payload) => {
    if (payload?.id) {
      removeAlertById(payload.id)
    }
  })

  instance.io.on('reconnect_attempt', (attempt) => {
    console.warn('[Socket] Reconnect attempt:', attempt)
  })

  instance.io.on('reconnect', (attempt) => {
    connected.value = true
    connectionError.value = ''
    console.info('[Socket] Reconnected after attempts:', attempt)
  })

  instance.io.on('reconnect_error', (error) => {
    connectionError.value = error.message
    console.error('[Socket] Reconnect error:', error.message)
  })
}

export function useSocket() {
  const selectedAlert = computed(() => {
    return alerts.value.find((alert) => alert._id === selectedAlertId.value) || null
  })

  function connect() {
    if (socket) {
      if (!socket.connected) {
        socket.connect()
      }
      return
    }

    socket = io(SOCKET_URL, {
      path: SOCKET_PATH,
      transports: ['websocket', 'polling'],
      timeout: 10000,
      reconnection: true,
      reconnectionAttempts: Infinity,
      reconnectionDelay: 1000,
      reconnectionDelayMax: 5000,
      randomizationFactor: 0.5,
      autoConnect: false,
    })

    attachSocketListeners(socket)
    socket.connect()
  }

  async function fetchActive() {
    try {
      await fetchActiveFromServer()
    } catch (error) {
      console.warn('[fetchActive] Failed to load active SOS data:', error.message)
    }
  }

  function disconnect() {
    socket?.disconnect()
    socket = null
    connected.value = false
  }

  return {
    connected,
    connectionError,
    alerts,
    activeCount,
    bloodCounts,
    hourlyCounts,
    medicalStats,
    selectedAlert,
    selectedAlertId,
    deletingIds,
    connect,
    fetchActive,
    disconnect,
    selectAlert,
    clearSelection,
    deleteAlert,
    getAlertKey,
  }
}
