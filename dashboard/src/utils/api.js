const API_BASE = (import.meta.env.VITE_API_BASE || '').trim()

function buildApiUrl(path) {
  if (/^https?:\/\//i.test(path)) {
    return path
  }

  const normalizedPath = path.startsWith('/') ? path : `/${path}`
  return `${API_BASE}${normalizedPath}`
}

export async function requestJson(path, options = {}) {
  const headers = {
    Accept: 'application/json',
    ...(options.body ? { 'Content-Type': 'application/json' } : {}),
    ...(options.headers || {}),
  }

  const response = await fetch(buildApiUrl(path), {
    ...options,
    headers,
  })

  const contentType = response.headers.get('content-type') || ''
  const rawText = await response.text()
  let payload = null

  if (rawText) {
    try {
      payload = JSON.parse(rawText)
    } catch (error) {
      payload = null
    }
  }

  const htmlLike = /^\s*</.test(rawText)
  if (!contentType.includes('application/json') && htmlLike) {
    throw new Error('接口返回了 HTML 页面，请检查后端服务端口或 VITE_API_BASE 配置')
  }

  if (!response.ok) {
    throw new Error(
      payload?.error
      || payload?.message
      || rawText
      || `请求失败 (${response.status})`
    )
  }

  if (payload === null) {
    throw new Error('接口未返回合法 JSON 数据')
  }

  return payload
}

export { buildApiUrl }
