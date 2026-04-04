<template>
  <div class="map-shell">
    <div ref="mapEl" class="map-wrap">
      <div class="scan-line"></div>
    </div>

    <div class="map-badge">
      <span class="badge-label">战场聚焦</span>
      <span class="badge-value">{{ selectedAlert ? (selectedAlert.medicalProfile?.name || selectedAlert.senderMac) : '未选中目标' }}</span>
    </div>

    <div v-if="selectedAlert" class="focus-panel">
      <div class="focus-head">
        <div>
          <div class="focus-kicker">地图详情</div>
          <div class="focus-title">{{ selectedAlert.medicalProfile?.name || selectedAlert.senderMac }}</div>
        </div>
        <button type="button" class="focus-close" @click="clearSelection">关闭</button>
      </div>

      <div class="focus-grid">
        <div class="focus-item">
          <span>坐标</span>
          <strong>{{ fmtCoord(selectedAlert.location.coordinates) }}</strong>
        </div>
        <div class="focus-item">
          <span>血型</span>
          <strong>{{ getBloodTypeLabel(selectedAlert) }}</strong>
        </div>
        <div class="focus-item">
          <span>时间</span>
          <strong>{{ fmtDateTime(selectedAlert.timestamp) }}</strong>
        </div>
        <div class="focus-item">
          <span>中继</span>
          <strong>{{ selectedAlert.reportedBy?.length || 1 }} 次</strong>
        </div>
      </div>

      <div class="focus-extra">
        <div v-if="selectedAlert.medicalProfile?.allergies"><span>过敏：</span>{{ selectedAlert.medicalProfile.allergies }}</div>
        <div v-if="selectedAlert.medicalProfile?.medicalHistory"><span>病史：</span>{{ selectedAlert.medicalProfile.medicalHistory }}</div>
        <div v-if="selectedAlert.medicalProfile?.emergencyContact"><span>联系：</span>{{ selectedAlert.medicalProfile.emergencyContact }}</div>
        <div v-if="!selectedAlert.medicalProfile?.allergies && !selectedAlert.medicalProfile?.medicalHistory && !selectedAlert.medicalProfile?.emergencyContact" class="muted">
          该目标暂无更多补充信息。
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { onMounted, onUnmounted, ref, watch } from 'vue'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { BLOOD_LABELS, useSocket } from '../composables/useSocket'

const { alerts, selectedAlert, selectAlert, clearSelection, getAlertKey } = useSocket()

const mapEl = ref(null)
let map = null
const markers = new Map()
const TILE = 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'

function fmtCoord([lng, lat]) {
  return `${lat.toFixed(4)}, ${lng.toFixed(4)}`
}

function fmtDateTime(timestamp) {
  return new Date(timestamp).toLocaleString('zh-CN')
}

function getBloodTypeLabel(alert) {
  if (alert.medicalProfile?.bloodTypeDetail !== undefined) {
    return BLOOD_LABELS[alert.medicalProfile.bloodTypeDetail] ?? '未知'
  }
  return BLOOD_LABELS[alert.bloodType] ?? '未知'
}

function getMarkerHtml(isSelected) {
  const stateClass = isSelected ? 'selected' : 'normal'
  return `
    <div class="sos-marker ${stateClass}">
      <div class="sos-dot"></div>
      <div class="sos-ring"></div>
      <div class="sos-ring ring-secondary"></div>
    </div>
  `
}

function makeMarkerIcon(isSelected) {
  return L.divIcon({
    className: 'dashboard-sos-icon',
    html: getMarkerHtml(isSelected),
    iconSize: [36, 36],
    iconAnchor: [18, 18],
    popupAnchor: [0, -18],
  })
}

function buildPopup(alert) {
  return `
    <div class="sos-popup">
      <div class="p-title">SOS 现场信息</div>
      <div class="p-row"><span>目标</span><span>${alert.medicalProfile?.name || alert.senderMac}</span></div>
      <div class="p-row"><span>坐标</span><span>${fmtCoord(alert.location.coordinates)}</span></div>
      <div class="p-row"><span>血型</span><span class="hi-red">${getBloodTypeLabel(alert)}</span></div>
      <div class="p-row"><span>时间</span><span>${fmtDateTime(alert.timestamp)}</span></div>
      <div class="p-row"><span>中继</span><span class="hi-cyan">${alert.reportedBy?.length || 1} 次</span></div>
      ${alert.medicalProfile?.allergies ? `<div class="p-row"><span>过敏</span><span class="hi-orange">${alert.medicalProfile.allergies}</span></div>` : ''}
      ${alert.medicalProfile?.medicalHistory ? `<div class="p-row"><span>病史</span><span>${alert.medicalProfile.medicalHistory}</span></div>` : ''}
      ${alert.medicalProfile?.emergencyContact ? `<div class="p-row"><span>联系</span><span class="hi-purple">${alert.medicalProfile.emergencyContact}</span></div>` : ''}
    </div>
  `
}

function syncMarkers(nextAlerts) {
  if (!map) {
    return
  }

  const nextKeys = new Set(nextAlerts.map(getAlertKey))

  for (const alert of nextAlerts) {
    const key = getAlertKey(alert)
    const [lng, lat] = alert.location.coordinates
    const marker = markers.get(key)

    if (marker) {
      marker.setLatLng([lat, lng])
      marker.setPopupContent(buildPopup(alert))
      marker.setIcon(makeMarkerIcon(selectedAlert.value?._id === key))
      continue
    }

    const createdMarker = L.marker([lat, lng], {
      icon: makeMarkerIcon(selectedAlert.value?._id === key),
    })
      .bindPopup(buildPopup(alert), {
        className: 'sos-popup-wrap',
        maxWidth: 320,
      })
      .addTo(map)

    createdMarker.on('click', () => {
      selectAlert(alert)
    })

    markers.set(key, createdMarker)
  }

  for (const [key, marker] of markers.entries()) {
    if (!nextKeys.has(key)) {
      marker.remove()
      markers.delete(key)
    }
  }
}

function focusOnAlert(alert) {
  if (!map || !alert) {
    return
  }

  const key = getAlertKey(alert)
  const marker = markers.get(key)
  const [lng, lat] = alert.location.coordinates

  map.flyTo([lat, lng], Math.max(map.getZoom(), 13), {
    animate: true,
    duration: 0.8,
  })

  if (marker) {
    marker.openPopup()
  }
}

watch(
  alerts,
  (nextAlerts) => {
    syncMarkers(nextAlerts)
  },
  { deep: true },
)

watch(
  selectedAlert,
  (alert) => {
    syncMarkers(alerts.value)
    if (alert) {
      focusOnAlert(alert)
    }
  },
  { deep: true },
)

onMounted(() => {
  map = L.map(mapEl.value, {
    center: [35.86, 104.19],
    zoom: 5,
    zoomControl: false,
    attributionControl: false,
  })

  L.tileLayer(TILE, { maxZoom: 19, subdomains: 'abcd' }).addTo(map)
  L.control.zoom({ position: 'bottomright' }).addTo(map)

  syncMarkers(alerts.value)
  if (selectedAlert.value) {
    focusOnAlert(selectedAlert.value)
  }
})

onUnmounted(() => {
  for (const marker of markers.values()) {
    marker.remove()
  }
  markers.clear()
  map?.remove()
})
</script>

<style scoped>
.map-shell {
  position: relative;
  width: 100%;
  height: 100%;
}

.map-wrap {
  position: relative;
  width: 100%;
  height: 100%;
  border-radius: 6px;
  overflow: hidden;
  border: 1px solid rgba(0, 200, 255, 0.2);
  box-shadow: inset 0 0 30px rgba(0, 10, 30, 0.6);
}

.scan-line {
  position: absolute;
  left: 0;
  right: 0;
  height: 2px;
  background: linear-gradient(90deg, transparent, rgba(0, 229, 255, 0.4), transparent);
  animation: scan-line 6s linear infinite;
  z-index: 800;
  pointer-events: none;
}

.map-badge {
  position: absolute;
  top: 14px;
  left: 14px;
  z-index: 900;
  padding: 10px 14px;
  border-radius: 14px;
  background: rgba(3, 14, 30, 0.82);
  border: 1px solid rgba(0, 229, 255, 0.2);
  backdrop-filter: blur(12px);
  min-width: 220px;
}

.badge-label {
  display: block;
  color: rgba(160, 210, 255, 0.56);
  font-size: 0.68rem;
  margin-bottom: 4px;
}

.badge-value {
  display: block;
  color: #e8faff;
  font-size: 0.82rem;
  font-weight: 700;
}

.focus-panel {
  position: absolute;
  right: 16px;
  top: 16px;
  width: min(320px, calc(100% - 32px));
  z-index: 900;
  border-radius: 18px;
  padding: 16px;
  background: rgba(2, 12, 28, 0.88);
  border: 1px solid rgba(0, 229, 255, 0.18);
  box-shadow: 0 24px 50px rgba(0, 0, 0, 0.35);
  backdrop-filter: blur(14px);
}

.focus-head {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  align-items: flex-start;
}

.focus-kicker {
  color: rgba(142, 234, 255, 0.58);
  font-size: 0.68rem;
  text-transform: uppercase;
  letter-spacing: 0.12em;
}

.focus-title {
  color: #f5fcff;
  font-size: 1.06rem;
  font-weight: 700;
  margin-top: 4px;
}

.focus-close {
  background: transparent;
  border: 1px solid rgba(255, 255, 255, 0.14);
  color: rgba(225, 245, 255, 0.82);
  border-radius: 999px;
  padding: 5px 10px;
  cursor: pointer;
}

.focus-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px;
  margin-top: 16px;
}

.focus-item {
  padding: 10px;
  border-radius: 12px;
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.06);
}

.focus-item span {
  display: block;
  color: rgba(160, 210, 255, 0.58);
  font-size: 0.66rem;
  margin-bottom: 4px;
}

.focus-item strong {
  color: #f0fbff;
  font-size: 0.82rem;
  line-height: 1.4;
}

.focus-extra {
  margin-top: 14px;
  padding-top: 12px;
  border-top: 1px solid rgba(255, 255, 255, 0.08);
  display: flex;
  flex-direction: column;
  gap: 8px;
  color: rgba(210, 236, 255, 0.86);
  font-size: 0.76rem;
  line-height: 1.6;
}

.focus-extra span,
.muted {
  color: rgba(160, 210, 255, 0.58);
}

:global(.dashboard-sos-icon) {
  background: transparent;
  border: 0;
}

:global(.sos-marker) {
  position: relative;
  width: 36px;
  height: 36px;
}

:global(.sos-dot) {
  position: absolute;
  inset: 10px;
  border-radius: 50%;
  background: #ff6767;
  box-shadow: 0 0 16px rgba(255, 103, 103, 0.85);
}

:global(.sos-ring) {
  position: absolute;
  inset: 3px;
  border-radius: 50%;
  border: 2px solid rgba(255, 103, 103, 0.42);
  animation: sos-pulse 2.4s ease-out infinite;
}

:global(.sos-marker.normal .ring-secondary) {
  animation-delay: 1.2s;
}

:global(.sos-marker.selected .sos-dot) {
  background: #00e5ff;
  box-shadow: 0 0 18px rgba(0, 229, 255, 0.95);
}

:global(.sos-marker.selected .sos-ring) {
  border-color: rgba(0, 229, 255, 0.48);
}

:global(.sos-popup) {
  min-width: 220px;
}

:global(.sos-popup .p-title) {
  font-weight: 700;
  margin-bottom: 10px;
  color: #0f172a;
}

:global(.sos-popup .p-row) {
  display: flex;
  justify-content: space-between;
  gap: 10px;
  margin-bottom: 6px;
  font-size: 12px;
}

:global(.sos-popup .hi-red) {
  color: #ef4444;
  font-weight: 700;
}

:global(.sos-popup .hi-cyan) {
  color: #0891b2;
  font-weight: 700;
}

:global(.sos-popup .hi-orange) {
  color: #ea580c;
  font-weight: 700;
}

:global(.sos-popup .hi-purple) {
  color: #7c3aed;
  font-weight: 700;
}

:global(.leaflet-popup-content-wrapper),
:global(.leaflet-popup-tip) {
  background: rgba(245, 252, 255, 0.96);
}

@keyframes scan-line {
  0% {
    top: 0;
  }
  100% {
    top: calc(100% - 2px);
  }
}

@keyframes sos-pulse {
  0% {
    transform: scale(0.78);
    opacity: 0.88;
  }
  100% {
    transform: scale(1.18);
    opacity: 0;
  }
}

@media (max-width: 1280px) {
  .focus-panel {
    width: 280px;
  }
}
</style>
