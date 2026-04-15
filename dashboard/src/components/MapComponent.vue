<template>
  <div ref="mapEl" class="map-wrap">
    <div v-if="mapError" class="map-error-panel">
      <div class="map-error-title">地图加载失败</div>
      <div class="map-error-body">{{ mapError }}</div>
      <div class="map-error-hint">
        请检查 `dashboard/.env` 中的 `VITE_AMAP_JS_KEY`、`VITE_AMAP_SECURITY_CODE`，并在修改后重启前端。
      </div>
    </div>
    <div v-if="currentRouteState" :class="['route-hud', { compact: isRouteHudCompact }]">
      <div class="route-hud-head">
        <div class="route-hud-head-copy">
          <div class="route-hud-title">导航路线已锁定</div>
          <div class="route-hud-subtitle">
            {{ currentRouteState.name || currentRouteState.mac }} → {{ currentRouteState.hospitalName }}
          </div>
        </div>
        <div class="route-hud-tools">
          <button class="route-hud-icon-btn" @click="toggleRouteHudCompact">
            {{ isRouteHudCompact ? '展开' : '收起' }}
          </button>
          <button class="route-hud-icon-btn" @click="clearRouteOverlay">关闭</button>
        </div>
      </div>
      <div v-if="isRouteHudCompact" class="route-hud-compact-summary">
        <span>{{ currentRouteState.route?.distanceKm || '--' }} km</span>
        <span>{{ currentRouteState.route?.estimatedTimeMinutes || '--' }} 分钟</span>
        <span>{{ activeRouteStepIndex >= 0 ? `步骤 #${activeRouteStepIndex + 1}` : '全线' }}</span>
      </div>
      <div v-else class="route-hud-metrics">
        <div class="route-hud-metric">
          <span class="route-hud-label">总距离</span>
          <strong>{{ currentRouteState.route?.distanceKm || '--' }} km</strong>
        </div>
        <div class="route-hud-metric">
          <span class="route-hud-label">预计时间</span>
          <strong>{{ currentRouteState.route?.estimatedTimeMinutes || '--' }} 分钟</strong>
        </div>
        <div class="route-hud-metric">
          <span class="route-hud-label">当前步骤</span>
          <strong>{{ activeRouteStepIndex >= 0 ? `#${activeRouteStepIndex + 1}` : '全线' }}</strong>
        </div>
      </div>
      <div v-if="!isRouteHudCompact" class="route-hud-step">
        {{ activeRouteStepIndex >= 0 ? getActiveRouteStepText() : '已高亮整条推荐路线，地图上的编号节点可与右侧步骤对应。' }}
      </div>
      <div v-if="!isRouteHudCompact" class="route-hud-actions">
        <button class="route-hud-btn" @click="focusWholeRoute">查看全线</button>
        <button class="route-hud-btn ghost" @click="clearRouteOverlay">隐藏路线</button>
      </div>
      <div v-if="!isRouteHudCompact" class="route-hud-note">虚线表示求救点或医院与实际可通行道路起终点之间的偏移。</div>
    </div>
    <div class="scan-line"></div>
  </div>
</template>

<script setup>
import { ref, watchEffect, watch, onMounted, onUnmounted } from 'vue'
import { useSocket, BLOOD_LABELS } from '../composables/useSocket'
import { wgs84ToGcj02 } from '../utils/coordTransform'

const { alerts, searchState } = useSocket()
const mapEl = ref(null)
const mapReady = ref(false)
const mapError = ref('')
const currentRouteState = ref(null)
const activeRouteStepIndex = ref(-1)
const isRouteHudCompact = ref(false)

const AMAP_JS_KEY = import.meta.env.VITE_AMAP_JS_KEY || import.meta.env.VITE_AMAP_KEY || ''
const AMAP_SECURITY_CODE = import.meta.env.VITE_AMAP_SECURITY_CODE || ''
const AMAP_MAP_STYLE = import.meta.env.VITE_AMAP_MAP_STYLE || 'amap://styles/dark'
const STALE_THRESHOLD = 30 * 60 * 1000

let amapLoadPromise = null
let AMapLib = null
let map = null
let heatmap = null
let infoWindow = null
let staleTimer = null
let activeInfoTargetKey = ''
const added = new Map()
let routeOverlays = []

function loadAmapSdk() {
  if (window.AMap) {
    return Promise.resolve(window.AMap)
  }

  if (amapLoadPromise) {
    return amapLoadPromise
  }

  amapLoadPromise = new Promise((resolve, reject) => {
    if (!AMAP_JS_KEY) {
      reject(new Error('缺少 VITE_AMAP_JS_KEY'))
      return
    }

    if (AMAP_SECURITY_CODE) {
      window._AMapSecurityConfig = { securityJsCode: AMAP_SECURITY_CODE }
    }

    const existing = document.getElementById('amap-jsapi')
    if (existing) {
      existing.addEventListener('load', () => resolve(window.AMap), { once: true })
      existing.addEventListener('error', () => reject(new Error('高德 JS API 加载失败')), { once: true })
      return
    }

    const callbackName = `__amapInit_${Date.now()}`
    window[callbackName] = () => {
      if (!window.AMap) {
        reject(new Error('高德脚本已返回，但 window.AMap 不可用'))
        delete window[callbackName]
        return
      }
      resolve(window.AMap)
      delete window[callbackName]
    }

    const script = document.createElement('script')
    script.id = 'amap-jsapi'
    script.src = `https://webapi.amap.com/maps?v=2.0&key=${encodeURIComponent(AMAP_JS_KEY)}&plugin=AMap.HeatMap&callback=${callbackName}`
    script.async = true
    script.onerror = () => {
      reject(new Error('高德 JS API 脚本加载失败'))
      delete window[callbackName]
    }
    document.head.appendChild(script)
  })

  return amapLoadPromise
}

function toGcjPoint(coords = []) {
  if (!Array.isArray(coords) || coords.length < 2) return null
  const [lng, lat] = coords
  if (!Number.isFinite(lng) || !Number.isFinite(lat)) return null
  const [gcjLng, gcjLat] = wgs84ToGcj02(lng, lat)
  return [gcjLng, gcjLat]
}

function updateHeatmap() {
  if (!map || !heatmap) return

  const data = alerts.value
    .filter((sos) => sos.status === 'active' && sos.location?.coordinates)
    .map((sos) => {
      const point = toGcjPoint(sos.location.coordinates)
      if (!point) return null
      const weight = Math.min((sos.reportedBy?.length ?? 1) / 5, 1)
      return {
        lng: point[0],
        lat: point[1],
        count: Math.max(1, Math.round(weight * 100)),
      }
    })
    .filter(Boolean)

  heatmap.setDataSet({ data, max: 100 })
}

function createMarkerElement() {
  const el = document.createElement('div')
  el.className = 'sos-marker-wrap'
  el.innerHTML = `
    <div class="sos-marker">
      <div class="sos-dot"></div>
      <div class="sos-ring"></div>
      <div class="sos-ring r2"></div>
    </div>
  `
  return el
}

function mkPopup(sos) {
  const bt = sos.medicalProfile?.bloodTypeDetail !== undefined
    ? BLOOD_LABELS[sos.medicalProfile.bloodTypeDetail] ?? '未知'
    : BLOOD_LABELS[sos.bloodType] ?? '未知'
  const time = new Date(sos.timestamp).toLocaleString('zh-CN')
  const relay = sos.reportedBy?.length ?? 1
  const mp = sos.medicalProfile || {}
  const [lng, lat] = sos.location?.coordinates || [0, 0]

  return `<div class="sos-popup">
    <div class="p-title">⚠ SOS 求救信号</div>
    <div class="p-row"><span>设备 MAC</span><span>${sos.senderMac}</span></div>
    ${mp.name ? `<div class="p-row"><span>姓名</span><span class="hi-green">${mp.name}</span></div>` : ''}
    ${mp.age ? `<div class="p-row"><span>年龄</span><span>${mp.age}</span></div>` : ''}
    <div class="p-row"><span>血型</span><span class="hi-red">${bt}</span></div>
    ${mp.allergies ? `<div class="p-row"><span class="warn">⚠ 过敏</span><span class="hi-orange">${mp.allergies}</span></div>` : ''}
    ${mp.medicalHistory ? `<div class="p-row"><span>病史</span><span>${mp.medicalHistory}</span></div>` : ''}
    ${mp.emergencyContact ? `<div class="p-row"><span>联系人</span><span class="hi-purple">${mp.emergencyContact}</span></div>` : ''}
    <div class="p-row"><span>坐标</span><span class="coord">${lng.toFixed(4)}°E, ${lat.toFixed(4)}°N</span></div>
    <div class="p-row"><span>求救时间</span><span>${time}</span></div>
    <div class="p-row"><span>中继次数</span><span class="hi">${relay} 次</span></div>
    <div class="p-row"><span>置信度</span><span class="hi">${sos.confidence ?? relay}</span></div>
  </div>`
}

function openInfoWindow(position, content) {
  if (!map || !infoWindow) return
  infoWindow.setContent(`<div class="map-info-window">${content}</div>`)
  infoWindow.open(map, position)
}

function toggleInfoWindow(targetKey, position, content) {
  if (!map || !infoWindow) return
  if (activeInfoTargetKey === targetKey) {
    infoWindow.close()
    activeInfoTargetKey = ''
    return false
  }
  activeInfoTargetKey = targetKey
  openInfoWindow(position, content)
  return true
}

function addMarker(sos) {
  const key = `${sos.senderMac}|${sos.timestamp}`
  if (added.has(key) || !map) return
  const point = toGcjPoint(sos.location?.coordinates)
  if (!point) return

  const contentEl = createMarkerElement()
  const marker = new AMapLib.Marker({
    position: point,
    anchor: 'center',
    content: contentEl,
    offset: new AMapLib.Pixel(-15, -15),
    zIndex: 130,
  })
  marker.setExtData({ sosData: sos })
  marker.on('click', () => {
    const opened = toggleInfoWindow(`sos:${key}`, point, mkPopup(sos))
    if (opened) {
      const nextZoom = Math.max(map.getZoom() || 5, 15)
      map.setZoomAndCenter(nextZoom, point, false, 500)
    }
  })
  marker.setMap(map)

  setTimeout(() => contentEl.classList.add('flash-in'), 50)
  added.set(key, { marker, el: contentEl, sosData: sos })
  scheduleStaleCheck()
}

function scheduleStaleCheck() {
  if (staleTimer) clearTimeout(staleTimer)
  staleTimer = setTimeout(updateStaleMarkers, 5000)
}

function updateStaleMarkers() {
  const now = Date.now()
  for (const [, entry] of added) {
    const ts = entry.sosData?.timestamp
    if (!ts || !entry.el) continue
    const age = now - new Date(ts).getTime()
    if (age > STALE_THRESHOLD) entry.el.classList.add('stale')
    else entry.el.classList.remove('stale')
  }
  scheduleStaleCheck()
}

function clearAllRouteOverlays() {
  routeOverlays.forEach((overlay) => overlay?.setMap?.(null))
  routeOverlays = []
}

function clearRouteOverlay() {
  clearAllRouteOverlays()
  currentRouteState.value = null
  activeRouteStepIndex.value = -1
  isRouteHudCompact.value = false
  setHeatmapRouteMode(false)
}

function toggleRouteHudCompact() {
  isRouteHudCompact.value = !isRouteHudCompact.value
}

function setHeatmapRouteMode(active) {
  const canvas = mapEl.value?.querySelector('.amap-heatmap-layer')
  if (!canvas) return
  canvas.style.opacity = active ? '0.18' : '1'
  canvas.style.filter = active ? 'saturate(0.65)' : 'saturate(1)'
  canvas.style.transition = 'opacity 180ms ease, filter 180ms ease'
}

function decodeStepPolyline(step) {
  return String(step?.polyline || '')
    .split(';')
    .filter(Boolean)
    .map((pair) => pair.split(',').map(Number))
    .filter((point) => point.length === 2 && Number.isFinite(point[0]) && Number.isFinite(point[1]))
}

function decodeRoutePolyline(route) {
  const steps = Array.isArray(route?.fullSteps) ? route.fullSteps : []
  const points = []
  let lastKey = null
  steps.forEach((step) => {
    decodeStepPolyline(step).forEach(([lng, lat]) => {
      const key = `${lng.toFixed(6)},${lat.toFixed(6)}`
      if (key === lastKey) return
      lastKey = key
      points.push([lng, lat])
    })
  })
  return points
}

function calcMeters(a, b) {
  if (!Array.isArray(a) || !Array.isArray(b)) return 0
  const toRad = (deg) => (deg * Math.PI) / 180
  const [lng1, lat1] = a
  const [lng2, lat2] = b
  const dLat = toRad(lat2 - lat1)
  const dLng = toRad(lng2 - lng1)
  const lat1Rad = toRad(lat1)
  const lat2Rad = toRad(lat2)
  const h = Math.sin(dLat / 2) ** 2
    + Math.cos(lat1Rad) * Math.cos(lat2Rad) * Math.sin(dLng / 2) ** 2
  return 6371000 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h))
}

function addOverlay(overlay) {
  overlay.setMap(map)
  routeOverlays.push(overlay)
  return overlay
}

function makeEndpointMarker(kind, label, position) {
  return new AMapLib.Marker({
    position,
    anchor: 'center',
    offset: new AMapLib.Pixel(-18, -17),
    zIndex: 1200,
    content: `<div class="route-endpoint ${kind}">
      <div class="route-endpoint-badge">${kind === 'start' ? 'SOS' : '医'}</div>
      <div class="route-endpoint-label">${label}</div>
    </div>`,
  })
}

function makeAnchorMarker(kind, position) {
  return new AMapLib.Marker({
    position,
    anchor: 'center',
    offset: new AMapLib.Pixel(-6, -6),
    zIndex: 1000,
    content: `<div class="route-anchor ${kind}"></div>`,
  })
}

function makeTurnMarker(index, active, position, step) {
  const marker = new AMapLib.Marker({
    position,
    anchor: 'center',
    offset: new AMapLib.Pixel(-12, -12),
    zIndex: 1100 + index,
    content: `<div class="route-turn-marker ${active ? 'active' : ''}">${index + 1}</div>`,
  })
  marker.on('click', () => {
    openInfoWindow(position, `<div class="sos-popup route-popup"><div class="p-title">步骤 ${index + 1}</div><div class="p-row"><span>${step.instruction || ''}</span><span>${step.distance || 0}m</span></div></div>`)
    highlightRouteStep(index)
  })
  return marker
}

function fitView(overlays, options = {}) {
  if (!map || !overlays.length) return

  const {
    padding = [120, 120, 120, 120],
    minZoom = 0,
    extraZoom = 0,
  } = options

  map.setFitView(overlays, false, padding)

  const currentZoom = Number(map.getZoom?.() || 0)
  if (!Number.isFinite(currentZoom)) return

  const targetZoom = Math.min(18, Math.max(currentZoom + extraZoom, minZoom))
  if (targetZoom > currentZoom) {
    map.setZoom(targetZoom, false, 350)
  }
}

function getRouteFocusOptions(route) {
  const distance = Number(route?.distanceMeters || 0)

  if (distance > 0 && distance <= 2000) {
    return {
      padding: [130, 110, 110, 110],
      minZoom: 15,
      extraZoom: 1,
    }
  }

  if (distance > 0 && distance <= 5000) {
    return {
      padding: [130, 110, 110, 110],
      minZoom: 14,
      extraZoom: 1,
    }
  }

  return {
    padding: [120, 120, 120, 120],
    minZoom: 12,
    extraZoom: 0,
  }
}

function rebuildRouteOverlay(detail, options = {}) {
  if (!map || !detail?.route) return
  const { focusBounds = true } = options

  currentRouteState.value = detail
  setHeatmapRouteMode(true)
  clearAllRouteOverlays()

  const routePoints = decodeRoutePolyline(detail.route)
  if (routePoints.length < 2) return

  const shadow = addOverlay(new AMapLib.Polyline({
    path: routePoints,
    strokeColor: '#031623',
    strokeWeight: 12,
    lineCap: 'round',
    lineJoin: 'round',
    zIndex: 800,
  }))

  const line = addOverlay(new AMapLib.Polyline({
    path: routePoints,
    strokeColor: '#23e7ff',
    strokeWeight: 6,
    lineCap: 'round',
    lineJoin: 'round',
    zIndex: 900,
  }))

  const startCoords = toGcjPoint(detail.route.sourceCoordinates) || routePoints[0]
  const endCoords = toGcjPoint(detail.route.destinationCoordinates) || routePoints[routePoints.length - 1]
  const routeStart = routePoints[0]
  const routeEnd = routePoints[routePoints.length - 1]

  const startMarker = makeEndpointMarker('start', detail.name || detail.mac || '求救点', startCoords)
  startMarker.on('click', () => {
    toggleInfoWindow(
      `route-start:${detail.mac || detail.name || 'unknown'}`,
      startCoords,
      `<div class="sos-popup route-popup"><div class="p-title">求救点</div><div class="p-row"><span>${detail.name || detail.mac || ''}</span><span>${detail.address || ''}</span></div></div>`,
    )
  })
  addOverlay(startMarker)

  const endMarker = makeEndpointMarker('end', detail.hospitalName || '目的医院', endCoords)
  endMarker.on('click', () => {
    toggleInfoWindow(
      `route-end:${detail.hospitalName || 'hospital'}:${detail.route.distanceKm || ''}`,
      endCoords,
      `<div class="sos-popup route-popup"><div class="p-title">目的医院</div><div class="p-row"><span>${detail.hospitalName || '医院'}</span><span>${detail.route.distanceKm || ''} km</span></div></div>`,
    )
  })
  addOverlay(endMarker)

  if (calcMeters(startCoords, routeStart) > 20) {
    addOverlay(new AMapLib.Polyline({
      path: [startCoords, routeStart],
      strokeColor: '#00f0b8',
      strokeWeight: 2,
      strokeStyle: 'dashed',
      lineDash: [6, 6],
      zIndex: 850,
    }))
    addOverlay(makeAnchorMarker('start', routeStart))
  }

  if (calcMeters(routeEnd, endCoords) > 20) {
    addOverlay(new AMapLib.Polyline({
      path: [routeEnd, endCoords],
      strokeColor: '#ffd966',
      strokeWeight: 2,
      strokeStyle: 'dashed',
      lineDash: [6, 6],
      zIndex: 850,
    }))
    addOverlay(makeAnchorMarker('end', routeEnd))
  }

  const steps = Array.isArray(detail.route?.fullSteps) ? detail.route.fullSteps.slice(0, 6) : []
  steps.forEach((step, index) => {
    const stepPoints = decodeStepPolyline(step)
    if (!stepPoints.length) return
    addOverlay(makeTurnMarker(index, activeRouteStepIndex.value === index, stepPoints[stepPoints.length - 1], step))
  })

  if (focusBounds) {
    fitView([shadow, line], getRouteFocusOptions(detail.route))
  }

  if (activeRouteStepIndex.value >= 0) {
    highlightRouteStep(activeRouteStepIndex.value, { fly: false, rerender: false })
  }
}

function getRouteEndpointBadge(type, fallbackKind) {
  if (type === 'rescue_team') return '\u6551'
  if (type === 'victim') return 'SOS'
  if (type === 'hospital') return '\u533b'
  return fallbackKind === 'start' ? 'SOS' : '\u533b'
}

function getRouteEndpointTitle(type, fallbackKind) {
  if (type === 'rescue_team') return '\u6551\u63f4\u961f'
  if (type === 'victim') return '\u6c42\u6551\u70b9'
  if (type === 'hospital') return '\u76ee\u7684\u533b\u9662'
  return fallbackKind === 'start' ? '\u6c42\u6551\u70b9' : '\u76ee\u7684\u533b\u9662'
}

function makeTypedEndpointMarker(kind, label, position, type) {
  return new AMapLib.Marker({
    position,
    anchor: 'center',
    offset: new AMapLib.Pixel(-18, -17),
    zIndex: 1200,
    content: `<div class="route-endpoint ${kind}">
      <div class="route-endpoint-badge">${getRouteEndpointBadge(type, kind)}</div>
      <div class="route-endpoint-label">${label}</div>
    </div>`,
  })
}

function renderRouteOverlay(detail, options = {}) {
  if (!map || !detail?.route) return
  const { focusBounds = true } = options

  currentRouteState.value = detail
  setHeatmapRouteMode(true)
  clearAllRouteOverlays()

  const routePoints = decodeRoutePolyline(detail.route)
  if (routePoints.length < 2) return

  const shadow = addOverlay(new AMapLib.Polyline({
    path: routePoints,
    strokeColor: '#031623',
    strokeWeight: 12,
    lineCap: 'round',
    lineJoin: 'round',
    zIndex: 800,
  }))

  const line = addOverlay(new AMapLib.Polyline({
    path: routePoints,
    strokeColor: '#23e7ff',
    strokeWeight: 6,
    lineCap: 'round',
    lineJoin: 'round',
    zIndex: 900,
  }))

  const startCoords = toGcjPoint(detail.route.sourceCoordinates) || routePoints[0]
  const endCoords = toGcjPoint(detail.route.destinationCoordinates) || routePoints[routePoints.length - 1]
  const routeStart = routePoints[0]
  const routeEnd = routePoints[routePoints.length - 1]

  const startLabel = detail.startName || detail.name || detail.mac || getRouteEndpointTitle(detail.startType, 'start')
  const startTitle = getRouteEndpointTitle(detail.startType, 'start')
  const startAddress = detail.route?.sourceMeta?.address || ''
  const startMarker = makeTypedEndpointMarker('start', startLabel, startCoords, detail.startType)
  startMarker.on('click', () => {
    toggleInfoWindow(
      `route-start:${detail.startName || detail.mac || detail.name || 'unknown'}`,
      startCoords,
      `<div class="sos-popup route-popup"><div class="p-title">${startTitle}</div><div class="p-row"><span>${startLabel}</span><span>${startAddress}</span></div></div>`,
    )
  })
  addOverlay(startMarker)

  const endLabel = detail.endName || detail.hospitalName || getRouteEndpointTitle(detail.endType, 'end')
  const endTitle = getRouteEndpointTitle(detail.endType, 'end')
  const endAddress = detail.route?.destinationMeta?.address || ''
  const endMarker = makeTypedEndpointMarker('end', endLabel, endCoords, detail.endType)
  endMarker.on('click', () => {
    const distanceRow = `${detail.route.distanceKm || ''} km`
    const addressRow = endAddress
      ? `<div class="p-row"><span>\u5730\u5740</span><span>${endAddress}</span></div>`
      : ''
    toggleInfoWindow(
      `route-end:${detail.endName || detail.hospitalName || 'target'}:${detail.route.distanceKm || ''}`,
      endCoords,
      `<div class="sos-popup route-popup"><div class="p-title">${endTitle}</div><div class="p-row"><span>${endLabel}</span><span>${distanceRow}</span></div>${addressRow}</div>`,
    )
  })
  addOverlay(endMarker)

  if (calcMeters(startCoords, routeStart) > 20) {
    addOverlay(new AMapLib.Polyline({
      path: [startCoords, routeStart],
      strokeColor: '#00f0b8',
      strokeWeight: 2,
      strokeStyle: 'dashed',
      lineDash: [6, 6],
      zIndex: 850,
    }))
    addOverlay(makeAnchorMarker('start', routeStart))
  }

  if (calcMeters(routeEnd, endCoords) > 20) {
    addOverlay(new AMapLib.Polyline({
      path: [routeEnd, endCoords],
      strokeColor: '#ffd966',
      strokeWeight: 2,
      strokeStyle: 'dashed',
      lineDash: [6, 6],
      zIndex: 850,
    }))
    addOverlay(makeAnchorMarker('end', routeEnd))
  }

  const steps = Array.isArray(detail.route?.fullSteps) ? detail.route.fullSteps.slice(0, 6) : []
  steps.forEach((step, index) => {
    const stepPoints = decodeStepPolyline(step)
    if (!stepPoints.length) return
    addOverlay(makeTurnMarker(index, activeRouteStepIndex.value === index, stepPoints[stepPoints.length - 1], step))
  })

  if (focusBounds) {
    fitView([shadow, line], getRouteFocusOptions(detail.route))
  }

  if (activeRouteStepIndex.value >= 0) {
    highlightRouteStep(activeRouteStepIndex.value, { fly: false, rerender: false })
  }
}

function showRouteOverlay(detail) {
  if (!detail?.route) return
  activeRouteStepIndex.value = -1
  renderRouteOverlay(detail)
}

function highlightRouteStep(stepIndex, options = {}) {
  const detail = currentRouteState.value
  const steps = Array.isArray(detail?.route?.fullSteps) ? detail.route.fullSteps : []
  if (!detail?.route || !Number.isInteger(stepIndex) || stepIndex < 0 || stepIndex >= steps.length) {
    activeRouteStepIndex.value = -1
    if (detail) renderRouteOverlay(detail, { focusBounds: false })
    return
  }

  const { fly = true, rerender = true } = options
  activeRouteStepIndex.value = stepIndex
  if (rerender) {
    renderRouteOverlay(detail, { focusBounds: false })
  }

  const stepPoints = decodeStepPolyline(steps[stepIndex])
  if (stepPoints.length < 2) return

  const shadow = addOverlay(new AMapLib.Polyline({
    path: stepPoints,
    strokeColor: '#ffffff',
    strokeOpacity: 0.15,
    strokeWeight: 12,
    lineCap: 'round',
    lineJoin: 'round',
    zIndex: 1150,
  }))

  const line = addOverlay(new AMapLib.Polyline({
    path: stepPoints,
    strokeColor: '#ffea5b',
    strokeWeight: 7,
    lineCap: 'round',
    lineJoin: 'round',
    zIndex: 1200,
  }))

  if (fly) {
    fitView([shadow, line], {
      padding: [120, 120, 120, 120],
      minZoom: 16,
      extraZoom: 1,
    })
  }

  window.dispatchEvent(new CustomEvent('map-route-step-changed', {
    detail: { stepIndex },
  }))
}

function getActiveRouteStepText() {
  const steps = currentRouteState.value?.route?.fullSteps || []
  const step = steps[activeRouteStepIndex.value]
  return step?.instruction || '已锁定当前步骤。'
}

function focusWholeRoute() {
  if (!currentRouteState.value) return
  activeRouteStepIndex.value = -1
  renderRouteOverlay(currentRouteState.value)
  window.dispatchEvent(new CustomEvent('map-route-step-changed', {
    detail: { stepIndex: -1 },
  }))
}

function applyMarkerFilterState() {
  if (!mapReady.value) return
  for (const [key, entry] of added) {
    const el = entry.el
    if (!el) continue
    if (searchState.hasFilter && !searchState.activeKeys.has(key)) {
      el.classList.add('dimmed')
      el.classList.remove('highlighted')
    } else if (searchState.activeKeys.has(key)) {
      el.classList.remove('dimmed')
      el.classList.add('highlighted')
    } else {
      el.classList.remove('dimmed', 'highlighted')
    }
  }
}

function flyToSos(sos) {
  if (!map || !sos?.location?.coordinates) return
  const point = toGcjPoint(sos.location.coordinates)
  if (!point) return
  map.setZoomAndCenter(15, point, false, 500)

  const key = `${sos.senderMac}|${sos.timestamp}`
  const entry = added.get(key)
  if (entry?.marker) {
    openInfoWindow(point, mkPopup(entry.sosData))
  }
}

function handleFlyTo(e) {
  flyToSos(e.detail)
}

function handleShowRoute(e) {
  showRouteOverlay(e.detail)
}

function handleHighlightRouteStep(e) {
  const detail = e.detail?.routeOverlay
  if (!currentRouteState.value && detail?.route) {
    showRouteOverlay(detail)
  }

  const stepIndex = Number(e.detail?.stepIndex)
  if (!Number.isInteger(stepIndex) || stepIndex < 0) {
    focusWholeRoute()
    return
  }
  highlightRouteStep(stepIndex)
}

function handleFocusRoute(e) {
  const detail = e?.detail
  if (!currentRouteState.value && detail?.route) {
    showRouteOverlay(detail)
    return
  }
  focusWholeRoute()
}

function handleFlyToArea(e) {
  if (!map) return
  const center = Array.isArray(e.detail?.center) ? e.detail.center : null
  if (!center || center.length < 2) return
  const point = toGcjPoint(center)
  if (!point) return
  const count = Number(e.detail?.count || 0)
  const zoom = count >= 8 ? 10 : count >= 5 ? 11 : 12
  map.setZoomAndCenter(zoom, point, false, 800)
}

watchEffect(() => {
  if (!mapReady.value) return
  alerts.value.forEach(addMarker)
  updateHeatmap()
})

watch(() => searchState.activeKeys, () => {
  applyMarkerFilterState()
}, { deep: true })

onMounted(async () => {
  try {
    AMapLib = await loadAmapSdk()
  } catch (error) {
    console.error('[Map] 高德地图加载失败:', error.message)
    mapError.value = error.message
    return
  }

  infoWindow = new AMapLib.InfoWindow({
    isCustom: true,
    autoMove: true,
    offset: new AMapLib.Pixel(0, -28),
    content: '',
  })

  map = new AMapLib.Map(mapEl.value, {
    center: toGcjPoint([104.19, 35.86]),
    zoom: 5,
    mapStyle: AMAP_MAP_STYLE,
    viewMode: '2D',
    features: ['bg', 'road', 'building', 'point'],
    showLabel: true,
    resizeEnable: true,
    jogEnable: false,
    pitchEnable: false,
    rotateEnable: false,
  })

  infoWindow.on('close', () => {
    activeInfoTargetKey = ''
  })

  heatmap = new AMapLib.HeatMap(map, {
    radius: 35,
    opacity: [0, 0.9],
    gradient: {
      0.0: '#0066ff',
      0.25: '#00ffff',
      0.5: '#00ff88',
      0.75: '#ffcc00',
      1.0: '#ff3333',
    },
  })

  mapReady.value = true
  mapError.value = ''
  setHeatmapRouteMode(false)

  window.addEventListener('map-flyto', handleFlyTo)
  window.addEventListener('map-show-route', handleShowRoute)
  window.addEventListener('map-highlight-route-step', handleHighlightRouteStep)
  window.addEventListener('map-focus-route', handleFocusRoute)
  window.addEventListener('map-flyto-area', handleFlyToArea)
})

onUnmounted(() => {
  if (staleTimer) clearTimeout(staleTimer)
  clearAllRouteOverlays()
  window.removeEventListener('map-flyto', handleFlyTo)
  window.removeEventListener('map-show-route', handleShowRoute)
  window.removeEventListener('map-highlight-route-step', handleHighlightRouteStep)
  window.removeEventListener('map-focus-route', handleFocusRoute)
  window.removeEventListener('map-flyto-area', handleFlyToArea)
  map?.destroy?.()
  map = null
  infoWindow = null
  heatmap = null
  added.clear()
})

defineExpose({ flyToSos })
</script>

<style scoped>
.map-wrap {
  position: relative;
  width: 100%;
  height: 100%;
  border-radius: 6px;
  overflow: hidden;
  border: 1px solid rgba(0, 200, 255, 0.2);
  box-shadow: inset 0 0 30px rgba(0, 10, 30, 0.6);
}

.map-wrap::before {
  content: '';
  position: absolute;
  inset: 0;
  z-index: 1;
  pointer-events: none;
  background:
    radial-gradient(circle at 20% 18%, rgba(0, 170, 255, 0.08), transparent 28%),
    radial-gradient(circle at 82% 78%, rgba(0, 255, 217, 0.06), transparent 30%),
    linear-gradient(180deg, rgba(2, 10, 18, 0.06), rgba(2, 10, 18, 0.14));
}

.map-error-panel {
  position: absolute;
  left: 16px;
  top: 16px;
  z-index: 980;
  width: min(420px, calc(100% - 32px));
  padding: 14px 16px;
  border-radius: 14px;
  border: 1px solid rgba(255, 107, 107, 0.28);
  background: linear-gradient(180deg, rgba(33, 8, 12, 0.96), rgba(18, 4, 8, 0.96));
  box-shadow: 0 18px 45px rgba(0, 0, 0, 0.34);
}

.map-error-title {
  color: #ff8d8d;
  font-size: 0.88rem;
  font-weight: bold;
  margin-bottom: 8px;
}

.map-error-body {
  color: #ffe6e6;
  font-size: 0.68rem;
  line-height: 1.55;
  word-break: break-word;
}

.map-error-hint {
  margin-top: 8px;
  color: rgba(255, 219, 219, 0.72);
  font-size: 0.62rem;
  line-height: 1.45;
}

.route-hud {
  position: absolute;
  top: 14px;
  left: 14px;
  z-index: 950;
  width: min(360px, calc(100% - 28px));
  min-width: 240px;
  max-width: 460px;
  min-height: 96px;
  resize: both;
  overflow: auto;
  padding: 12px 14px;
  border-radius: 14px;
  border: 1px solid rgba(0, 229, 255, 0.16);
  background: linear-gradient(180deg, rgba(4, 20, 34, 0.96), rgba(3, 14, 26, 0.95));
  box-shadow: 0 22px 50px rgba(0, 0, 0, 0.3);
  backdrop-filter: blur(12px);
}

.route-hud.compact {
  width: min(300px, calc(100% - 28px));
  min-height: auto;
  resize: horizontal;
}

.route-hud-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 8px;
  margin-bottom: 10px;
}

.route-hud-head-copy {
  min-width: 0;
  flex: 1;
}

.route-hud-tools {
  display: flex;
  gap: 6px;
  flex-shrink: 0;
}

.route-hud-icon-btn {
  height: 28px;
  padding: 0 10px;
  border-radius: 999px;
  border: 1px solid rgba(255, 255, 255, 0.12);
  background: rgba(255, 255, 255, 0.05);
  color: rgba(227, 246, 255, 0.82);
  font-size: 0.6rem;
  cursor: pointer;
}

.route-hud-title {
  color: #9ff6ff;
  font-size: 0.78rem;
  font-weight: bold;
  letter-spacing: 0.06em;
}

.route-hud-subtitle {
  margin-top: 3px;
  color: rgba(208, 244, 255, 0.8);
  font-size: 0.67rem;
  line-height: 1.45;
  word-break: break-word;
}

.route-hud-compact-summary {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  color: rgba(220, 247, 255, 0.9);
  font-size: 0.64rem;
  line-height: 1.5;
}

.route-hud-metrics {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 8px;
}

.route-hud-metric {
  padding: 8px;
  border-radius: 10px;
  background: rgba(7, 32, 50, 0.9);
  border: 1px solid rgba(0, 229, 255, 0.12);
}

.route-hud-label {
  display: block;
  color: rgba(167, 212, 226, 0.62);
  font-size: 0.58rem;
  margin-bottom: 3px;
}

.route-hud-metric strong {
  color: #f2feff;
  font-size: 0.8rem;
}

.route-hud-step {
  margin-top: 10px;
  padding: 9px 10px;
  border-radius: 10px;
  background: rgba(9, 37, 58, 0.88);
  color: rgba(227, 248, 255, 0.88);
  font-size: 0.64rem;
  line-height: 1.5;
}

.route-hud-actions {
  display: flex;
  gap: 8px;
  margin-top: 10px;
}

.route-hud-btn {
  height: 30px;
  padding: 0 12px;
  border-radius: 999px;
  border: 1px solid rgba(0, 229, 255, 0.18);
  background: rgba(0, 229, 255, 0.1);
  color: #aaf4ff;
  font-size: 0.62rem;
  cursor: pointer;
}

.route-hud-btn.ghost {
  background: rgba(255, 255, 255, 0.04);
  color: rgba(217, 240, 250, 0.82);
}

.route-hud-note {
  margin-top: 9px;
  color: rgba(157, 200, 214, 0.56);
  font-size: 0.56rem;
  line-height: 1.45;
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

@keyframes scan-line {
  0% { top: 0; opacity: 0; }
  10% { opacity: 1; }
  90% { opacity: 1; }
  100% { top: 100%; opacity: 0; }
}
</style>

<style>
.map-info-window {
  min-width: 260px;
  border-radius: 18px;
  background: linear-gradient(180deg, rgba(6, 18, 31, 0.98), rgba(4, 13, 24, 0.98));
  border: 1px solid rgba(0, 229, 255, 0.16);
  box-shadow: 0 18px 44px rgba(0, 0, 0, 0.38);
  backdrop-filter: blur(16px);
}

.sos-marker-wrap {
  transform-origin: center center;
  transition: opacity 0.2s ease, filter 0.2s ease, transform 0.2s ease;
}

.sos-marker-wrap.flash-in {
  animation: marker-flash-in 500ms ease;
}

.sos-marker-wrap.stale {
  filter: grayscale(0.35);
  opacity: 0.65;
}

.sos-marker-wrap.dimmed {
  opacity: 0.25;
  filter: grayscale(0.6);
}

.sos-marker-wrap.highlighted {
  transform: scale(1.1);
}

.sos-marker {
  position: relative;
  width: 30px;
  height: 30px;
}

.sos-dot {
  position: absolute;
  left: 50%;
  top: 50%;
  width: 12px;
  height: 12px;
  border-radius: 50%;
  background: #ff3b30;
  transform: translate(-50%, -50%);
  box-shadow: 0 0 12px rgba(255, 59, 48, 0.85);
}

.sos-ring {
  position: absolute;
  left: 50%;
  top: 50%;
  width: 24px;
  height: 24px;
  border: 2px solid rgba(0, 255, 235, 0.45);
  border-radius: 50%;
  transform: translate(-50%, -50%);
  animation: sos-pulse 2.4s ease-out infinite;
}

.sos-ring.r2 {
  animation-delay: 1.2s;
}

@keyframes sos-pulse {
  0% { transform: translate(-50%, -50%) scale(0.6); opacity: 0.9; }
  100% { transform: translate(-50%, -50%) scale(1.55); opacity: 0; }
}

@keyframes marker-flash-in {
  0% { transform: scale(0.6); opacity: 0; }
  100% { transform: scale(1); opacity: 1; }
}

.sos-popup {
  min-width: 260px;
  padding: 14px 16px;
  border-radius: 18px;
  color: #effbff;
  font-family: 'Courier New', monospace;
  background: linear-gradient(180deg, rgba(5, 18, 31, 0.98), rgba(3, 12, 23, 0.98));
}

.sos-popup .p-title {
  color: #9ff6ff;
  font-size: 0.92rem;
  font-weight: bold;
  margin-bottom: 10px;
  letter-spacing: 0.04em;
}

.sos-popup .p-row {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  align-items: flex-start;
  padding-top: 10px;
  border-top: 1px solid rgba(255, 255, 255, 0.08);
  font-size: 0.74rem;
  line-height: 1.5;
}

.sos-popup .p-row span:first-child {
  min-width: 56px;
  color: rgba(177, 220, 235, 0.74);
}

.sos-popup .p-row span:last-child {
  flex: 1;
  color: #f2fbff;
  text-align: right;
  word-break: break-word;
}

.route-popup .p-title {
  color: #ff8c8c;
}

.hi-green { color: #53ffbc !important; }
.hi-red { color: #ff8a8a !important; }
.hi-orange { color: #ffd76d !important; }
.hi-purple { color: #d9a8ff !important; }
.hi { color: #8fefff !important; }
.warn { color: #ffd76d !important; }
.coord { color: #b5e8ff !important; }

.route-endpoint {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  min-width: 136px;
  max-width: 220px;
  padding: 5px 12px 5px 5px;
  border-radius: 999px;
  border: 1px solid rgba(255, 255, 255, 0.14);
  box-shadow: 0 12px 28px rgba(0, 0, 0, 0.3);
  backdrop-filter: blur(14px);
}

.route-endpoint.start {
  background: linear-gradient(135deg, rgba(80, 18, 24, 0.96), rgba(42, 11, 16, 0.94));
  border-color: rgba(255, 105, 105, 0.32);
}

.route-endpoint.end {
  background: linear-gradient(135deg, rgba(77, 61, 12, 0.96), rgba(43, 31, 6, 0.94));
  border-color: rgba(255, 212, 90, 0.34);
}

.route-endpoint-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 26px;
  height: 26px;
  border-radius: 50%;
  font-size: 12px;
  font-weight: bold;
}

.route-endpoint.start .route-endpoint-badge {
  background: #ff5b5b;
  color: #fff;
  box-shadow: 0 0 18px rgba(255, 91, 91, 0.45);
}

.route-endpoint.end .route-endpoint-badge {
  background: #ffd44a;
  color: #201600;
  box-shadow: 0 0 18px rgba(255, 212, 74, 0.4);
}

.route-endpoint-label {
  max-width: 170px;
  color: #f6fcff;
  font-size: 12px;
  font-weight: 600;
  font-family: 'Courier New', monospace;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  text-shadow: 0 1px 8px rgba(0, 0, 0, 0.35);
}

.route-anchor {
  width: 12px;
  height: 12px;
  border-radius: 50%;
  border: 2px solid rgba(255, 255, 255, 0.95);
  box-shadow: 0 0 14px rgba(255, 255, 255, 0.18);
}

.route-anchor.start {
  background: #00f0b8;
}

.route-anchor.end {
  background: #ffd966;
}

.route-turn-marker {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: 24px;
  border-radius: 50%;
  background: rgba(2, 18, 31, 0.92);
  border: 2px solid rgba(0, 229, 255, 0.75);
  color: #b7fbff;
  font-family: 'Courier New', monospace;
  font-size: 12px;
  font-weight: bold;
  box-shadow: 0 0 12px rgba(0, 229, 255, 0.24);
}

.route-turn-marker.active {
  border-color: rgba(255, 234, 91, 0.95);
  color: #fff4a3;
  box-shadow: 0 0 16px rgba(255, 234, 91, 0.35);
}
</style>
