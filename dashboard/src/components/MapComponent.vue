<template>
  <div ref="mapEl" class="map-wrap">
    <!-- 扫描线特效 -->
    <div class="scan-line"></div>
  </div>
</template>

<script setup>
import { ref, watchEffect, onMounted, onUnmounted } from 'vue'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { useSocket, BLOOD_LABELS } from '../composables/useSocket'

const { alerts } = useSocket()
const mapEl    = ref(null)
const mapReady = ref(false)

let map     = null
const added = new Map()   // key → true，防止重复打点

// CartoDB Dark Matter 底图
const TILE = 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'

function mkIcon() {
  return L.divIcon({
    className: '',
    html: `<div class="sos-marker">
             <div class="sos-dot"></div>
             <div class="sos-ring"></div>
             <div class="sos-ring r2"></div>
           </div>`,
    iconSize:    [30, 30],
    iconAnchor:  [15, 15],
    popupAnchor: [0, -18],
  })
}

function mkPopup(sos) {
  const bt   = sos.medicalProfile?.bloodTypeDetail !== undefined 
    ? BLOOD_LABELS[sos.medicalProfile.bloodTypeDetail] ?? '未知'
    : BLOOD_LABELS[sos.bloodType] ?? '未知'
  const time = new Date(sos.timestamp).toLocaleString('zh-CN')
  const relay = sos.reportedBy?.length ?? 1
  const mp = sos.medicalProfile || {}
  
  return `<div class="sos-popup">
    <div class="p-title">⚠ SOS 求救信号</div>
    <div class="p-row"><span>设备 MAC</span><span>${sos.senderMac}</span></div>
    ${mp.name ? `<div class="p-row"><span>姓名</span><span class="hi-green">${mp.name}</span></div>` : ''}
    ${mp.age ? `<div class="p-row"><span>年龄</span><span>${mp.age}</span></div>` : ''}
    <div class="p-row"><span>血型</span><span class="hi-red">${bt}</span></div>
    ${mp.allergies ? `<div class="p-row"><span class="warn">⚠ 过敏</span><span class="hi-orange">${mp.allergies}</span></div>` : ''}
    ${mp.medicalHistory ? `<div class="p-row"><span>病史</span><span>${mp.medicalHistory}</span></div>` : ''}
    ${mp.emergencyContact ? `<div class="p-row"><span>联系人</span><span class="hi-purple">${mp.emergencyContact}</span></div>` : ''}
    <div class="p-row"><span>求救时间</span><span>${time}</span></div>
    <div class="p-row"><span>中继次数</span><span class="hi">${relay} 次</span></div>
    <div class="p-row"><span>置信度</span><span class="hi">${sos.confidence ?? relay}</span></div>
  </div>`
}

function addMarker(sos) {
  const key = `${sos.senderMac}|${sos.timestamp}`
  if (added.has(key) || !map) return
  added.set(key, true)

  const [lng, lat] = sos.location.coordinates
  L.marker([lat, lng], { icon: mkIcon() })
    .bindPopup(mkPopup(sos), { className: 'sos-popup-wrap', maxWidth: 260 })
    .addTo(map)
}

// watchEffect：mapReady + alerts 双重依赖
// 每次 alerts 有新项或地图就绪时重跑，dedup 由 added Map 保证
watchEffect(() => {
  if (!mapReady.value) return
  alerts.value.forEach(addMarker)
})

onMounted(() => {
  map = L.map(mapEl.value, {
    center: [35.86, 104.19],
    zoom: 5,
    zoomControl: false,
    attributionControl: false,
  })

  L.tileLayer(TILE, { maxZoom: 19, subdomains: 'abcd' }).addTo(map)
  L.control.zoom({ position: 'bottomright' }).addTo(map)

  mapReady.value = true
})

onUnmounted(() => map?.remove())
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
/* 扫描线特效 */
.scan-line {
  position: absolute;
  left: 0; right: 0;
  height: 2px;
  background: linear-gradient(90deg, transparent, rgba(0, 229, 255, 0.4), transparent);
  animation: scan-line 6s linear infinite;
  z-index: 800;
  pointer-events: none;
}
</style>
