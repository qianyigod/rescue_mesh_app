/**
 * 地理编码服务
 * 提供坐标到地址的转换功能
 * 
 * 支持的地图服务商：
 * - 高德地图 (AMap) - 推荐国内使用
 * - 百度地图 (Baidu) - 备选
 * - OpenStreetMap (Nominatim) - 免费但限流严格
 */

// ============================================================================
// 🔑 API 配置区域 - 请在此处填入您的 API Key
// ============================================================================

/**
 * 【必填】高德地图 Web Service API Key
 * 申请地址：https://lbs.amap.com/api/webservice/guide/create-project/get-key
 * 免费额度：每日 5000 次请求
 * 
 * 使用方法：
 * 1. 注册高德开放平台账号
 * 2. 创建应用，添加"Web服务"类型的Key
 * 3. 将获得的 Key 填入下方引号内
 */
const AMAP_API_KEY = process.env.AMAP_API_KEY || 'YOUR_AMAP_API_KEY_HERE';

/**
 * 【可选】百度地图 AK
 * 申请地址：https://lbsyun.baidu.com/apiconsole/key#/home
 * 如果高德不可用，可切换到此备用方案
 */
const BAIDU_MAP_AK = process.env.BAIDU_MAP_AK || 'YOUR_BAIDU_MAP_AK_HERE';

/**
 * 【可选】是否启用缓存（需要 Redis）
 * 设置为 true 可减少重复的地理编码请求
 */
const ENABLE_GEOCACHE = process.env.ENABLE_GEOCACHE === 'true';
const { gcj02ToWgs84, wgs84ToGcj02 } = require('../utils/coordTransform');

// ============================================================================
// 服务实现
// ============================================================================

let redisClient = null;

if (ENABLE_GEOCACHE) {
  try {
    const redis = require('redis');
    redisClient = redis.createClient({
      url: process.env.REDIS_URL || 'redis://localhost:6379',
    });
    redisClient.connect().catch(console.error);
  } catch (err) {
    console.warn('[GeoCoding] Redis 连接失败，缓存功能已禁用:', err.message);
  }
}

/**
 * 从缓存获取地址（如果启用）
 */
async function getCachedAddress(cacheKey) {
  if (!ENABLE_GEOCACHE || !redisClient) return null;
  
  try {
    const cached = await redisClient.get(cacheKey);
    return cached ? JSON.parse(cached) : null;
  } catch (err) {
    console.warn('[GeoCoding] 缓存读取失败:', err.message);
    return null;
  }
}

/**
 * 写入缓存（如果启用）
 */
async function setCachedAddress(cacheKey, data, ttlSeconds = 86400) {
  if (!ENABLE_GEOCACHE || !redisClient) return;
  
  try {
    await redisClient.setEx(cacheKey, ttlSeconds, JSON.stringify(data));
  } catch (err) {
    console.warn('[GeoCoding] 缓存写入失败:', err.message);
  }
}

/**
 * 使用高德地图进行逆地理编码
 * @param {number} lng - 经度
 * @param {number} lat - 纬度
 * @returns {Promise<Object>} 地址信息对象
 */
async function reverseGeocodeWithAMap(lng, lat) {
  const cacheKey = `geocode:amap:${lng.toFixed(6)},${lat.toFixed(6)}`;
  
  // 尝试从缓存获取
  const cached = await getCachedAddress(cacheKey);
  if (cached) {
    return cached;
  }
  
  if (AMAP_API_KEY === 'YOUR_AMAP_API_KEY_HERE') {
    throw new Error('AMAP_API_KEY 未配置，请在 server/.env 中添加高德地图 API Key');
  }
  
  const [gcjLng, gcjLat] = wgs84ToGcj02(lng, lat);
  const baseUrl = 'https://restapi.amap.com/v3/geocode/regeo';
  const params = new URLSearchParams({
    location: `${gcjLng},${gcjLat}`,
    key: AMAP_API_KEY,
    radius: '1000',
    extensions: 'all',
    roadlevel: '1',
  });
  
  const response = await fetch(`${baseUrl}?${params}`);
  const data = await response.json();
  
  if (data.status !== '1') {
    throw new Error(`高德地图API错误 (${data.infocode}): ${data.info}`);
  }
  
  const regeocode = data.regeocode;
  const result = {
    provider: 'amap',
    formattedAddress: regeocode.formatted_address,
    addressComponent: {
      country: regeocode.addressComponent.country,
      province: regeocode.addressComponent.province,
      city: regeocode.addressComponent.city,
      district: regeocode.addressComponent.district,
      township: regeocode.addressComponent.township,
      village: regeocode.addressComponent.towncode,
      street: regeocode.addressComponent.streetNumber?.street || '',
      streetNumber: regeocode.addressComponent.streetNumber?.number || '',
    },
    pois: (regeocode.pois || []).slice(0, 5).map(poi => {
      const [poiLng, poiLat] = poi.location.split(',').map(Number);
      const [wgsLng, wgsLat] = gcj02ToWgs84(poiLng, poiLat);
      return {
        id: poi.id,
        name: poi.name,
        type: poi.type,
        typeCode: poi.typecode,
        distance: parseInt(poi.distance),
        direction: poi.direction,
        location: [wgsLng, wgsLat],
      };
    }),
    roads: (regeocode.roads || []).slice(0, 3).map(road => ({
      name: road.name,
      distance: parseInt(road.distance),
      direction: road.direction,
    })),
    raw: regeocode, // 保留原始数据供调试
  };
  
  // 写入缓存
  await setCachedAddress(cacheKey, result);
  
  return result;
}

function normalizeAmapKeywords(keywords, fallback = []) {
  if (Array.isArray(keywords)) {
    return keywords.map((item) => String(item || '').trim()).filter(Boolean);
  }

  return String(keywords || '')
    .split(/[\s,，]+/)
    .map((item) => item.trim())
    .filter(Boolean)
    .concat(fallback)
    .filter(Boolean);
}

function mapAmapPoiToWgs(poi) {
  const gcjLocation = String(poi?.location || '')
    .split(',')
    .map((item) => Number(item));

  if (!Array.isArray(gcjLocation) || gcjLocation.length !== 2 || !Number.isFinite(gcjLocation[0]) || !Number.isFinite(gcjLocation[1])) {
    return null;
  }

  const [wgsLng, wgsLat] = gcj02ToWgs84(gcjLocation[0], gcjLocation[1]);
  return {
    id: poi.id,
    name: poi.name,
    type: poi.type,
    typeCode: poi.typecode,
    address: poi.address || '',
    tel: poi.tel || '',
    distance: parseInt(poi.distance || 0, 10),
    location: [wgsLng, wgsLat],
    businessArea: poi.business_area || '',
  };
}

async function searchNearbyHospitalsWithAMap(lng, lat, options = {}) {
  const {
    radius = 5000,
    pageSize = 20,
    keywords = '医院',
  } = options;

  const normalizedKeywords = normalizeAmapKeywords(keywords);
  const queryKeywords = normalizedKeywords.length > 0 ? normalizedKeywords : ['医院'];
  const normalizedRadius = Math.min(Math.max(parseInt(radius, 10) || 5000, 1000), 50000);
  const cacheKey = `hospital:amap:${lng.toFixed(6)},${lat.toFixed(6)}:${normalizedRadius}:${pageSize}:${queryKeywords.join('|')}`;
  const cached = await getCachedAddress(cacheKey);
  if (cached) {
    return cached;
  }

  if (AMAP_API_KEY === 'YOUR_AMAP_API_KEY_HERE') {
    throw new Error('AMAP_API_KEY 鏈厤缃紝璇峰湪 server/.env 涓坊鍔犻珮寰峰湴鍥?API Key');
  }

  {
    const [gcjLng, gcjLat] = wgs84ToGcj02(lng, lat);
    const baseUrl = 'https://restapi.amap.com/v3/place/around';
    const allPois = [];
    const seen = new Set();

    for (const keyword of queryKeywords) {
      const params = new URLSearchParams({
        key: AMAP_API_KEY,
        location: `${gcjLng},${gcjLat}`,
        radius: String(normalizedRadius),
        keywords: keyword,
        types: '090000',
        sortrule: 'distance',
        offset: String(pageSize),
        page: '1',
        extensions: 'all',
      });

      const response = await fetch(`${baseUrl}?${params}`);
      const data = await response.json();

      if (data.status !== '1') {
        throw new Error(`妤傛ê鐥夐崷鏉挎禈POI API闁挎瑨顕?(${data.infocode}): ${data.info}`);
      }

      const pois = (data.pois || []).map(mapAmapPoiToWgs).filter(Boolean);

      for (const poi of pois) {
        const key = `${poi.id || poi.name}:${poi.location[0]},${poi.location[1]}`;
        if (seen.has(key)) {
          continue;
        }

        seen.add(key);
        allPois.push(poi);
      }
    }

    const mergedPois = allPois.sort((a, b) => a.distance - b.distance).slice(0, pageSize);
    await setCachedAddress(cacheKey, mergedPois);
    return mergedPois;
  }

  const baseUrl = 'https://restapi.amap.com/v3/place/around';
  const params = new URLSearchParams({
    key: AMAP_API_KEY,
    location: `${lng},${lat}`,
    radius: String(radius),
    keywords,
    types: '090100|090101|090102|090104',
    sortrule: 'distance',
    offset: String(pageSize),
    page: '1',
    extensions: 'all',
  });

  const response = await fetch(`${baseUrl}?${params}`);
  const data = await response.json();

  if (data.status !== '1') {
    throw new Error(`楂樺痉鍦板浘POI API閿欒 (${data.infocode}): ${data.info}`);
  }

  const pois = (data.pois || []).map((poi) => ({
    id: poi.id,
    name: poi.name,
    type: poi.type,
    typeCode: poi.typecode,
    address: poi.address || '',
    tel: poi.tel || '',
    distance: parseInt(poi.distance || 0, 10),
    location: String(poi.location || '')
      .split(',')
      .map((item) => Number(item)),
    businessArea: poi.business_area || '',
  })).filter((poi) => Array.isArray(poi.location) && poi.location.length === 2 && Number.isFinite(poi.location[0]) && Number.isFinite(poi.location[1]));

  await setCachedAddress(cacheKey, pois);
  return pois;
}

async function searchHospitalsByKeywordWithAMap(lng, lat, options = {}) {
  const {
    city = '',
    district = '',
    pageSize = 10,
    maxPages = 2,
    maxDistanceMeters = 50000,
    maxResults = 8,
    keywords = [
      '\u4e09\u7ea7\u7532\u7b49\u533b\u9662',
      '\u4eba\u6c11\u533b\u9662',
      '\u4e2d\u5fc3\u533b\u9662',
      '\u9644\u5c5e\u533b\u9662',
      '\u603b\u533b\u9662',
      '\u7efc\u5408\u533b\u9662',
      '\u6025\u6551\u4e2d\u5fc3',
    ],
  } = options;

  const queryKeywords = normalizeAmapKeywords(keywords);
  const cityHints = [district, city].map((item) => String(item || '').trim()).filter(Boolean);
  const cacheKey = `hospital:text:${lng.toFixed(6)},${lat.toFixed(6)}:${cityHints.join('|')}:${pageSize}:${maxPages}:${maxDistanceMeters}:${queryKeywords.join('|')}`;
  const cached = await getCachedAddress(cacheKey);
  if (cached) {
    return cached;
  }

  if (AMAP_API_KEY === 'YOUR_AMAP_API_KEY_HERE') {
    throw new Error('AMAP_API_KEY is not configured');
  }

  const baseUrl = 'https://restapi.amap.com/v3/place/text';
  const allPois = [];
  const seen = new Set();

  outer:
  for (const keyword of queryKeywords) {
    for (const cityHint of (cityHints.length > 0 ? cityHints : [''])) {
      for (let page = 1; page <= maxPages; page += 1) {
        const params = new URLSearchParams({
          key: AMAP_API_KEY,
          keywords: keyword,
          types: '090000',
          city: cityHint,
          citylimit: cityHint ? 'true' : 'false',
          offset: String(pageSize),
          page: String(page),
          extensions: 'all',
        });

        const response = await fetch(`${baseUrl}?${params}`);
        const data = await response.json();
        if (data.status !== '1') {
          throw new Error(`AMap text search failed (${data.infocode}): ${data.info}`);
        }

        const pois = (data.pois || [])
          .map(mapAmapPoiToWgs)
          .filter(Boolean)
          .map((poi) => ({
            ...poi,
            approxDistance: Math.round(Math.sqrt(((poi.location[0] - lng) * 111320 * Math.cos(lat * Math.PI / 180)) ** 2 + ((poi.location[1] - lat) * 110540) ** 2)),
          }))
          .filter((poi) => !Number.isFinite(maxDistanceMeters) || poi.approxDistance <= maxDistanceMeters);

        for (const poi of pois) {
          const key = `${poi.id || poi.name}:${poi.location[0]},${poi.location[1]}`;
          if (seen.has(key)) {
            continue;
          }

          seen.add(key);
          allPois.push(poi);
          if (allPois.length >= maxResults) {
            break outer;
          }
        }
      }
    }
  }

  const mergedPois = allPois
    .sort((a, b) => (a.approxDistance || Infinity) - (b.approxDistance || Infinity))
    .slice(0, maxResults);
  await setCachedAddress(cacheKey, mergedPois);
  return mergedPois;
}

/**
 * 使用百度地图进行逆地理编码（备用方案）
 * @param {number} lng - 经度
 * @param {number} lat - 纬度
 * @returns {Promise<Object>} 地址信息对象
 */
async function reverseGeocodeWithBaidu(lng, lat) {
  const cacheKey = `geocode:baidu:${lng.toFixed(6)},${lat.toFixed(6)}`;
  
  // 尝试从缓存获取
  const cached = await getCachedAddress(cacheKey);
  if (cached) {
    return cached;
  }
  
  if (BAIDU_MAP_AK === 'YOUR_BAIDU_MAP_AK_HERE') {
    throw new Error('BAIDU_MAP_AK 未配置，请在 server/.env 中添加百度地图 AK');
  }
  
  const baseUrl = 'https://api.map.baidu.com/reverse_geocoding/v3/';
  const params = new URLSearchParams({
    ak: BAIDU_MAP_AK,
    output: 'json',
    coordtype: 'wgs84ll',
    location: `${lat},${lng}`, // 注意：百度是 lat,lng 顺序
    radius: '1000',
    extensions_poi: '1',
  });
  
  const response = await fetch(`${baseUrl}?${params}`);
  const data = await response.json();
  
  if (data.status !== 0) {
    throw new Error(`百度地图API错误 (${data.status}): ${data.msg}`);
  }
  
  const result = data.result;
  return {
    provider: 'baidu',
    formattedAddress: result.formatted_address,
    addressComponent: {
      country: result.addressComponent.country,
      province: result.addressComponent.province,
      city: result.addressComponent.city,
      district: result.addressComponent.district,
      town: result.addressComponent.town,
      street: result.addressComponent.street,
      streetNumber: result.addressComponent.street_number,
    },
    pois: (result.pois || []).slice(0, 5).map(poi => ({
      name: poi.name,
      tag: poi.tag,
      distance: parseInt(poi.detail_info?.distance || 0),
      location: [parseFloat(poi.point.x), parseFloat(poi.point.y)],
    })),
    raw: result,
  };
}

/**
 * 统一的逆地理编码接口（自动选择提供商）
 * @param {number} lng - 经度
 * @param {number} lat - 纬度
 * @param {string} [provider='amap'] - 指定提供商 ('amap' | 'baidu')
 * @returns {Promise<Object>} 地址信息对象
 */
async function reverseGeocode(lng, lat, provider = 'amap') {
  // 验证坐标范围
  if (lng < -180 || lng > 180 || lat < -90 || lat > 90) {
    throw new Error(`无效的坐标: [${lng}, ${lat}]`);
  }
  
  try {
    switch (provider.toLowerCase()) {
      case 'amap':
      case 'gaode':
        return await reverseGeocodeWithAMap(lng, lat);
      case 'baidu':
        return await reverseGeocodeWithBaidu(lng, lat);
      default:
        throw new Error(`不支持的地图提供商: ${provider}`);
    }
  } catch (err) {
    console.error(`[GeoCoding] ${provider} 解析失败:`, err.message);
    
    // 如果是主提供商失败，尝试备用方案
    if (provider === 'amap' && BAIDU_MAP_AK !== 'YOUR_BAIDU_MAP_AK_HERE') {
      console.log('[GeoCoding] 尝试切换到百度地图...');
      return await reverseGeocodeWithBaidu(lng, lat);
    }
    
    throw err;
  }
}

/**
 * 批量逆地理编码（带并发控制）
 * @param {Array} locations - 位置数组 [{lng, lat}, ...]
 * @param {number} [concurrency=5] - 并发数
 * @returns {Promise<Array>} 地址结果数组
 */
async function batchReverseGeocode(locations, concurrency = 5) {
  const results = [];
  const queue = [...locations];
  const inProgress = new Set();
  
  return new Promise((resolve, reject) => {
    const processNext = async () => {
      if (queue.length === 0 && inProgress.size === 0) {
        resolve(results);
        return;
      }
      
      while (inProgress.size < concurrency && queue.length > 0) {
        const location = queue.shift();
        const index = locations.indexOf(location);
        inProgress.add(index);
        
        reverseGeocode(location.lng, location.lat)
          .then(result => {
            results[index] = { ...location, address: result, success: true };
          })
          .catch(err => {
            results[index] = { 
              ...location, 
              error: err.message, 
              success: false 
            };
          })
          .finally(() => {
            inProgress.delete(index);
            processNext();
          });
      }
    };
    
    processNext();
  });
}

module.exports = {
  reverseGeocode,
  batchReverseGeocode,
  reverseGeocodeWithAMap,
  reverseGeocodeWithBaidu,
  searchNearbyHospitalsWithAMap,
  searchHospitalsByKeywordWithAMap,
};
