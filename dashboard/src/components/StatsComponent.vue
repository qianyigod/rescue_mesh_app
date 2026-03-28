<template>
  <div class="panel stats-panel">
    <!-- 医疗档案统计（新增） -->
    <div class="panel-title">
      <span class="icon">◆</span> 医疗档案概览
    </div>
    <div class="medical-stats">
      <div class="stat-row">
        <span class="stat-label">有档案:</span>
        <span class="stat-value hi-green">{{ medicalStats.totalWithProfile }}</span>
      </div>
      <div class="stat-row">
        <span class="stat-label">过敏史:</span>
        <span class="stat-value hi-orange">{{ medicalStats.allergyCount }}</span>
      </div>
      <div class="stat-row">
        <span class="stat-label">病史:</span>
        <span class="stat-value hi-blue">{{ medicalStats.historyCount }}</span>
      </div>
    </div>

    <!-- 南丁格尔玫瑰图 -->
    <div class="panel-title divider">
      <span class="icon">◆</span> 血型分布态势
    </div>
    <div ref="roseEl" class="chart"></div>

    <!-- 12小时趋势折线 -->
    <div class="panel-title divider">
      <span class="icon">◆</span> 12小时信号趋势
    </div>
    <div ref="lineEl" class="chart"></div>
  </div>
</template>

<script setup>
import { ref, watch, onMounted, onUnmounted } from 'vue'
import * as echarts from 'echarts'
import { useSocket } from '../composables/useSocket'

const { bloodCounts, hourlyCounts, medicalStats } = useSocket()
const roseEl = ref(null)
const lineEl = ref(null)
let roseChart = null
let lineChart = null
let ro = null

// ── 血型配色 ────────────────────────────────────────────────
const BT_NAMES  = ['A型',    'B型',    'AB型',   'O型',    '未知']
const BT_KEYS   = ['0',      '1',      '2',      '3',      '-1']
const BT_COLORS = ['#FF6B6B','#4BC0C0','#FFCE56','#00E5FF','#9966FF']

// ── 玫瑰图 option ────────────────────────────────────────────
function roseOpt() {
  let data = BT_KEYS.map((k, i) => ({
    name: BT_NAMES[i],
    value: bloodCounts[k] || 0,
    itemStyle: { color: BT_COLORS[i] },
  })).filter(d => d.value > 0)

  if (!data.length) {
    data = [{ name: '暂无数据', value: 1, itemStyle: { color: 'rgba(100,150,200,0.15)' } }]
  }

  return {
    backgroundColor: 'transparent',
    tooltip: {
      trigger: 'item',
      backgroundColor: 'rgba(0,8,22,0.92)',
      borderColor: 'rgba(0,200,255,0.3)',
      textStyle: { color: '#e0f4ff', fontSize: 11 },
      formatter: '{b}: {c} 人 ({d}%)',
    },
    legend: {
      bottom: 4,
      textStyle: { color: 'rgba(160,210,255,0.65)', fontSize: 10 },
      itemWidth: 10, itemHeight: 10,
    },
    series: [{
      type: 'pie',
      roseType: 'area',
      radius: ['18%', '62%'],
      center: ['50%', '46%'],
      label: {
        color: 'rgba(180,220,255,0.8)',
        fontSize: 10,
        formatter: '{b}\n{d}%',
      },
      labelLine: { lineStyle: { color: 'rgba(0,200,255,0.35)' } },
      emphasis: {
        itemStyle: { shadowBlur: 12, shadowColor: 'rgba(0,200,255,0.4)' },
      },
      data,
    }],
  }
}

// ── 折线图 option ────────────────────────────────────────────
function lineOpt() {
  const now = new Date()
  const xLabels = Array.from({ length: 12 }, (_, i) => {
    const h = new Date(now)
    h.setHours(h.getHours() - (11 - i))
    return `${String(h.getHours()).padStart(2, '0')}时`
  })

  return {
    backgroundColor: 'transparent',
    tooltip: {
      trigger: 'axis',
      backgroundColor: 'rgba(0,8,22,0.92)',
      borderColor: 'rgba(0,200,255,0.3)',
      textStyle: { color: '#e0f4ff', fontSize: 11 },
      formatter: (p) => `${p[0].axisValue}：${p[0].value} 次求救`,
    },
    grid: { top: 18, right: 14, bottom: 32, left: 34 },
    xAxis: {
      type: 'category',
      data: xLabels,
      axisLabel: { color: 'rgba(150,200,255,0.5)', fontSize: 9 },
      axisLine:  { lineStyle: { color: 'rgba(0,200,255,0.2)' } },
      splitLine: { show: false },
    },
    yAxis: {
      type: 'value',
      minInterval: 1,
      axisLabel: { color: 'rgba(150,200,255,0.5)', fontSize: 9 },
      splitLine: { lineStyle: { color: 'rgba(0,200,255,0.07)', type: 'dashed' } },
    },
    series: [{
      type: 'line',
      data: hourlyCounts.value,
      smooth: 0.4,
      symbol: 'circle',
      symbolSize: 5,
      lineStyle: { color: '#00e5ff', width: 2 },
      itemStyle: { color: '#00e5ff', borderColor: '#001428', borderWidth: 2 },
      areaStyle: {
        color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
          { offset: 0, color: 'rgba(0,229,255,0.35)' },
          { offset: 1, color: 'rgba(0,229,255,0.02)' },
        ]),
      },
    }],
  }
}

// ── 生命周期 ────────────────────────────────────────────────
onMounted(() => {
  roseChart = echarts.init(roseEl.value, null, { renderer: 'svg' })
  lineChart = echarts.init(lineEl.value, null, { renderer: 'svg' })
  roseChart.setOption(roseOpt())
  lineChart.setOption(lineOpt())

  ro = new ResizeObserver(() => {
    roseChart?.resize()
    lineChart?.resize()
  })
  ro.observe(roseEl.value.parentElement)
})

watch(bloodCounts,  () => roseChart?.setOption(roseOpt()), { deep: true })
watch(hourlyCounts, () => lineChart?.setOption(lineOpt()),  { deep: true })

onUnmounted(() => {
  roseChart?.dispose()
  lineChart?.dispose()
  ro?.disconnect()
})
</script>

<style scoped>
.stats-panel { height: 100%; }
.chart { flex: 1; min-height: 0; }
.divider { border-top: 1px solid rgba(0, 200, 255, 0.1); }
.icon { font-size: 0.6rem; }

/* 医疗档案统计面板 */
.medical-stats {
  padding: 12px 16px;
  background: rgba(0, 30, 60, 0.3);
  border-bottom: 1px solid rgba(0, 200, 255, 0.1);
}
.stat-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 6px 0;
  font-size: 0.75rem;
}
.stat-label {
  color: rgba(160, 210, 255, 0.7);
}
.stat-value {
  font-weight: bold;
  font-size: 0.9rem;
}
.hi-green { color: #00ff88; }
.hi-orange { color: #ffa500; }
.hi-blue { color: #00e5ff; }
</style>
