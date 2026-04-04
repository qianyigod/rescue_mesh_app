<template>
  <div class="panel stats-panel">
    <div class="panel-title">
      <span class="icon">●</span> 医疗档案概览
    </div>
    <div class="medical-stats">
      <div class="stat-row">
        <span class="stat-label">已建档</span>
        <span class="stat-value hi-green">{{ medicalStats.totalWithProfile }}</span>
      </div>
      <div class="stat-row">
        <span class="stat-label">过敏风险</span>
        <span class="stat-value hi-orange">{{ medicalStats.allergyCount }}</span>
      </div>
      <div class="stat-row">
        <span class="stat-label">病史提示</span>
        <span class="stat-value hi-blue">{{ medicalStats.historyCount }}</span>
      </div>
    </div>

    <div class="panel-title divider">
      <span class="icon">●</span> 指挥建议
    </div>
    <div class="advice-card">
      <template v-if="selectedAlert">
        <div class="advice-title">{{ selectedAlert.medicalProfile?.name || selectedAlert.senderMac }}</div>
        <div class="advice-line">优先关注：{{ adviceSummary }}</div>
        <div class="advice-line">处置建议：{{ actionSummary }}</div>
      </template>
      <template v-else>
        <div class="advice-line muted">选中左侧告警后，这里会给出现场处置建议。</div>
      </template>
    </div>

    <div class="panel-title divider">
      <span class="icon">●</span> 血型分布态势
    </div>
    <div ref="roseEl" class="chart"></div>

    <div class="panel-title divider">
      <span class="icon">●</span> 12 小时信号趋势
    </div>
    <div ref="lineEl" class="chart"></div>
  </div>
</template>

<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import * as echarts from 'echarts'
import { useSocket } from '../composables/useSocket'

const { bloodCounts, hourlyCounts, medicalStats, selectedAlert } = useSocket()
const roseEl = ref(null)
const lineEl = ref(null)
let roseChart = null
let lineChart = null
let resizeObserver = null

const bloodTypeNames = ['A型', 'B型', 'AB型', 'O型', '未知']
const bloodTypeKeys = ['0', '1', '2', '3', '-1']
const bloodTypeColors = ['#FF6B6B', '#4BC0C0', '#FFCE56', '#00E5FF', '#9966FF']

const adviceSummary = computed(() => {
  if (!selectedAlert.value) {
    return ''
  }

  const profile = selectedAlert.value.medicalProfile || {}
  if (profile.allergies) {
    return `存在过敏信息，医疗处置前务必二次确认：${profile.allergies}`
  }
  if (profile.medicalHistory) {
    return `存在病史记录，建议医疗组先查看：${profile.medicalHistory}`
  }
  if (profile.emergencyContact) {
    return `可尝试联系紧急联系人：${profile.emergencyContact}`
  }
  return '暂无高风险医疗备注，优先快速定位并建立现场通信。'
})

const actionSummary = computed(() => {
  if (!selectedAlert.value) {
    return ''
  }

  const relayCount = selectedAlert.value.reportedBy?.length || 1
  if (relayCount >= 3) {
    return '信号可信度较高，建议优先调度最近救援单元前往。'
  }
  if (relayCount === 2) {
    return '已存在中继确认，可先派侦察小组并同步医疗待命。'
  }
  return '当前仅单点上报，建议结合地图位置和历史轨迹进行复核。'
})

function createRoseOption() {
  let data = bloodTypeKeys
    .map((key, index) => ({
      name: bloodTypeNames[index],
      value: bloodCounts[key] || 0,
      itemStyle: { color: bloodTypeColors[index] },
    }))
    .filter((item) => item.value > 0)

  if (!data.length) {
    data = [
      {
        name: '暂无数据',
        value: 1,
        itemStyle: { color: 'rgba(100,150,200,0.15)' },
      },
    ]
  }

  return {
    backgroundColor: 'transparent',
    tooltip: {
      trigger: 'item',
      backgroundColor: 'rgba(0,8,22,0.92)',
      borderColor: 'rgba(0,200,255,0.3)',
      textStyle: { color: '#e0f4ff', fontSize: 11 },
      formatter: '{b}: {c} 条 ({d}%)',
    },
    legend: {
      bottom: 4,
      textStyle: { color: 'rgba(160,210,255,0.65)', fontSize: 10 },
      itemWidth: 10,
      itemHeight: 10,
    },
    series: [
      {
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
      },
    ],
  }
}

function createLineOption() {
  const now = new Date()
  const labels = Array.from({ length: 12 }, (_, index) => {
    const time = new Date(now)
    time.setHours(time.getHours() - (11 - index))
    return `${String(time.getHours()).padStart(2, '0')}时`
  })

  return {
    backgroundColor: 'transparent',
    tooltip: {
      trigger: 'axis',
      backgroundColor: 'rgba(0,8,22,0.92)',
      borderColor: 'rgba(0,200,255,0.3)',
      textStyle: { color: '#e0f4ff', fontSize: 11 },
      formatter: (params) => `${params[0].axisValue}：${params[0].value} 次上报`,
    },
    grid: { top: 18, right: 14, bottom: 32, left: 34 },
    xAxis: {
      type: 'category',
      data: labels,
      axisLabel: { color: 'rgba(150,200,255,0.5)', fontSize: 9 },
      axisLine: { lineStyle: { color: 'rgba(0,200,255,0.2)' } },
      splitLine: { show: false },
    },
    yAxis: {
      type: 'value',
      minInterval: 1,
      axisLabel: { color: 'rgba(150,200,255,0.5)', fontSize: 9 },
      splitLine: { lineStyle: { color: 'rgba(0,200,255,0.07)', type: 'dashed' } },
    },
    series: [
      {
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
      },
    ],
  }
}

onMounted(() => {
  roseChart = echarts.init(roseEl.value, null, { renderer: 'svg' })
  lineChart = echarts.init(lineEl.value, null, { renderer: 'svg' })
  roseChart.setOption(createRoseOption())
  lineChart.setOption(createLineOption())

  resizeObserver = new ResizeObserver(() => {
    roseChart?.resize()
    lineChart?.resize()
  })
  resizeObserver.observe(roseEl.value.parentElement)
})

watch(bloodCounts, () => roseChart?.setOption(createRoseOption()), { deep: true })
watch(hourlyCounts, () => lineChart?.setOption(createLineOption()), { deep: true })

onUnmounted(() => {
  roseChart?.dispose()
  lineChart?.dispose()
  resizeObserver?.disconnect()
})
</script>

<style scoped>
.stats-panel {
  height: 100%;
}

.chart {
  flex: 1;
  min-height: 0;
}

.divider {
  border-top: 1px solid rgba(0, 200, 255, 0.1);
}

.icon {
  font-size: 0.6rem;
}

.medical-stats,
.advice-card {
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
  font-weight: 700;
  font-size: 0.92rem;
}

.advice-title {
  color: #eafcff;
  font-weight: 700;
  margin-bottom: 8px;
}

.advice-line {
  color: rgba(210, 236, 255, 0.82);
  font-size: 0.74rem;
  line-height: 1.65;
}

.muted {
  color: rgba(160, 210, 255, 0.6);
}

.hi-green {
  color: #00ff88;
}

.hi-orange {
  color: #ffa500;
}

.hi-blue {
  color: #00e5ff;
}
</style>
