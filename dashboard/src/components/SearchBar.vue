<template>
  <div class="search-bar">
    <div class="search-input-wrap">
      <span class="search-icon">🔍</span>
      <input
        v-model="keyword"
        type="text"
        placeholder="搜索姓名 / MAC / 病史 / 过敏 / 地区..."
        @input="onInput"
        @focus="showDropdown = true"
        @blur="hideDropdown"
        class="search-input"
      />
      <span v-if="keyword" class="clear-btn" @click="clear">✕</span>
    </div>

    <!-- 快捷过滤器 -->
    <div class="filters">
      <select v-model="bloodFilter" @change="applyFilters" class="filter-select">
        <option value="">血型</option>
        <option value="0">A型</option>
        <option value="1">B型</option>
        <option value="2">AB型</option>
        <option value="3">O型</option>
        <option value="-1">未知</option>
      </select>
      <select v-model="timeFilter" @change="applyFilters" class="filter-select">
        <option value="">时间</option>
        <option value="1">近1小时</option>
        <option value="6">近6小时</option>
        <option value="24">今天</option>
      </select>
    </div>

    <!-- 搜索结果下拉 -->
    <div v-if="showDropdown && results.length" class="dropdown" @mousedown.prevent>
      <div
        v-for="item in results.slice(0, 8)"
        :key="item.key"
        class="dropdown-item"
        @mousedown="selectResult(item)"
      >
        <span class="dd-name">{{ item.label }}</span>
        <span class="dd-meta">{{ item.meta }}</span>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useSocket, BLOOD_LABELS } from '../composables/useSocket'

const { alerts, searchState } = useSocket()

const keyword = ref('')
const bloodFilter = ref('')
const timeFilter = ref('')
const showDropdown = ref(false)
let hideTimer = null

// 中国主要城市坐标（用于地区搜索）
const CITIES = {
  '北京': [39.9042, 116.4074], '上海': [31.2304, 121.4737], '广州': [23.1291, 113.2644],
  '深圳': [22.5431, 114.0579], '成都': [30.5728, 104.0668], '杭州': [30.2741, 120.1551],
  '武汉': [30.5928, 114.3055], '西安': [34.3416, 108.9398], '重庆': [29.5630, 106.5516],
  '南京': [32.0603, 118.7969], '天津': [39.3434, 117.3616], '苏州': [31.2989, 120.5853],
  '长沙': [28.2282, 112.9388], '郑州': [34.7466, 113.6253], '青岛': [36.0671, 120.3826],
  '大连': [38.9140, 121.6147], '厦门': [24.4798, 118.0894], '福州': [26.0745, 119.2965],
  '昆明': [25.0389, 102.7183], '哈尔滨': [45.8038, 126.5350], '沈阳': [41.8057, 123.4315],
  '济南': [36.6512, 117.1201], '合肥': [31.8206, 117.2272], '南昌': [28.6829, 115.8579],
  '贵阳': [26.6470, 106.6302], '南宁': [22.8170, 108.3665], '石家庄': [38.0428, 114.5149],
  '太原': [37.8706, 112.5489], '兰州': [36.0611, 103.8343], '乌鲁木齐': [43.8256, 87.6168],
  '拉萨': [29.6500, 91.1409], '呼和浩特': [40.8414, 111.7519], '银川': [38.4872, 106.2309],
  '西宁': [36.6171, 101.7782], '长春': [43.8171, 125.3235],
  // 广东省内城市
  '东莞': [23.0209, 113.7518], '佛山': [23.0218, 113.1219], '珠海': [22.2769, 113.5678],
  '中山': [22.5171, 113.3927], '惠州': [23.1115, 114.4152], '汕头': [23.3540, 116.6824],
  '湛江': [21.2707, 110.3594], '肇庆': [23.0515, 112.4723], '江门': [22.5790, 113.0815],
  '茂名': [21.6630, 110.9255], '梅州': [24.2886, 116.1225], '韶关': [24.8103, 113.5977],
  '清远': [23.6813, 113.0561], '阳江': [21.8579, 111.9827], '潮州': [23.6567, 116.6228],
  '揭阳': [23.5438, 116.3724], '汕尾': [22.7867, 115.3753], '河源': [23.7431, 114.7009],
  '云浮': [22.9298, 112.0444],
}

// 搜索结果计算
const results = computed(() => {
  const kw = keyword.value.trim().toLowerCase()
  if (!kw && !bloodFilter.value && !statusFilter.value && !timeFilter.value) return []

  // 预计算：关键词是否命中某个城市
  const matchedCities = Object.entries(CITIES).filter(([city]) =>
    kw.includes(city.toLowerCase()) || city.toLowerCase().includes(kw)
  )
  const REGION_RADIUS = 0.5  // 城市匹配半径（约0.5度，~50km），避免相邻城市重叠

  const filtered = alerts.value.filter(sos => {
    // 关键词匹配
    if (kw) {
      const mp = sos.medicalProfile || {}
      const mac = (sos.senderMac || '').toLowerCase()
      const name = (mp.name || '').toLowerCase()
      const history = (mp.medicalHistory || '').toLowerCase()
      const allergies = (mp.allergies || '').toLowerCase()
      const contact = (mp.emergencyContact || '').toLowerCase()

      const matchKeyword = name.includes(kw) || mac.includes(kw) ||
        history.includes(kw) || allergies.includes(kw) || contact.includes(kw)

      // 地区匹配：必须求救者坐标在匹配城市附近才算
      const [sosLng, sosLat] = sos.location?.coordinates || [null, null]
      const matchRegion = sosLng != null && matchedCities.some(([, [cLat, cLng]]) =>
        Math.abs(sosLat - cLat) < REGION_RADIUS && Math.abs(sosLng - cLng) < REGION_RADIUS
      )

      if (!matchKeyword && !matchRegion) return false
    }

    // 血型过滤
    if (bloodFilter.value && String(sos.bloodType) !== bloodFilter.value) return false

    // 时间过滤
    if (timeFilter.value) {
      const hours = parseInt(timeFilter.value)
      const ageMs = Date.now() - new Date(sos.timestamp).getTime()
      if (ageMs > hours * 3600000) return false
    }

    return true
  })

  return filtered.map(sos => {
    const mp = sos.medicalProfile || {}
    const [lng, lat] = sos.location?.coordinates || [0, 0]
    const region = findNearestCity(lat, lng)
    const label = mp.name || sos.senderMac?.slice(-4) || '未知'
    const meta = `${region} · ${BLOOD_LABELS[String(sos.bloodType)] || '未知'} · ${sos.status === 'active' ? '待救援' : sos.status === 'rescued' ? '已救出' : '误报'}`
    return { key: `${sos.senderMac}|${sos.timestamp}`, label, meta, sos }
  })
})

function findNearestCity(lat, lng) {
  let nearest = ''
  let minDist = Infinity
  for (const [city, [cLat, cLng]] of Object.entries(CITIES)) {
    const dist = Math.sqrt((lat - cLat) ** 2 + (lng - cLng) ** 2)
    if (dist < minDist) { minDist = dist; nearest = city }
  }
  return nearest
}

function onInput() {
  showDropdown.value = true
  syncSearchState()
}

function applyFilters() {
  syncSearchState()
}

function clear() {
  keyword.value = ''
  bloodFilter.value = ''
  timeFilter.value = ''
  showDropdown.value = false
  syncSearchState()
}

function hideDropdown() {
  hideTimer = setTimeout(() => { showDropdown.value = false }, 200)
}

function syncSearchState() {
  const hasFilter = !!(keyword.value.trim() || bloodFilter.value || timeFilter.value)
  searchState.keyword = keyword.value.trim()
  searchState.blood = bloodFilter.value
  searchState.time = timeFilter.value
  searchState.hasFilter = hasFilter
  searchState.activeKeys.clear()
  results.value.forEach(r => searchState.activeKeys.add(r.key))
}

function selectResult(item) {
  showDropdown.value = false
  keyword.value = item.label
  syncSearchState()
  // 通知地图飞到目标
  window.dispatchEvent(new CustomEvent('map-flyto', { detail: item.sos }))
}
</script>

<style scoped>
.search-bar {
  display: flex;
  align-items: center;
  gap: 8px;
  flex: 1;
  max-width: 600px;
  margin: 0 auto;
  position: relative;
}

.search-input-wrap {
  flex: 1;
  display: flex;
  align-items: center;
  background: rgba(0, 20, 50, 0.8);
  border: 1px solid rgba(0, 200, 255, 0.25);
  border-radius: 6px;
  padding: 0 10px;
  transition: border-color 0.2s;
}
.search-input-wrap:focus-within {
  border-color: rgba(0, 200, 255, 0.6);
  box-shadow: 0 0 12px rgba(0, 200, 255, 0.15);
}

.search-icon {
  font-size: 14px;
  opacity: 0.5;
  margin-right: 6px;
}

.search-input {
  flex: 1;
  background: transparent;
  border: none;
  outline: none;
  color: #e0f4ff;
  font-family: 'Courier New', monospace;
  font-size: 0.8rem;
  padding: 6px 0;
  caret-color: #00e5ff;
}
.search-input::placeholder {
  color: rgba(0, 200, 255, 0.35);
}

.clear-btn {
  cursor: pointer;
  color: rgba(0, 200, 255, 0.4);
  font-size: 12px;
  padding: 2px 4px;
}
.clear-btn:hover { color: #00e5ff; }

.filters {
  display: flex;
  gap: 4px;
}

.filter-select {
  background: rgba(0, 20, 50, 0.8);
  border: 1px solid rgba(0, 200, 255, 0.2);
  border-radius: 4px;
  color: rgba(0, 200, 255, 0.7);
  font-family: 'Courier New', monospace;
  font-size: 0.7rem;
  padding: 4px 6px;
  cursor: pointer;
  outline: none;
}
.filter-select:hover { border-color: rgba(0, 200, 255, 0.5); }
.filter-select option {
  background: #0a1628;
  color: #e0f4ff;
}

/* 下拉结果 */
.dropdown {
  position: absolute;
  top: calc(100% + 6px);
  left: 0; right: 0;
  background: rgba(0, 12, 30, 0.97);
  border: 1px solid rgba(0, 200, 255, 0.3);
  border-radius: 6px;
  max-height: 280px;
  overflow-y: auto;
  z-index: 9999;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.6);
}

.dropdown-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 8px 12px;
  cursor: pointer;
  border-bottom: 1px solid rgba(0, 200, 255, 0.08);
  transition: background 0.15s;
}
.dropdown-item:last-child { border-bottom: none; }
.dropdown-item:hover {
  background: rgba(0, 200, 255, 0.1);
}

.dd-name {
  color: #00e5ff;
  font-weight: bold;
  font-size: 0.85rem;
}
.dd-meta {
  color: rgba(0, 200, 255, 0.5);
  font-size: 0.7rem;
}
</style>
