/**
 * 璺緞瑙勫垝鏈嶅姟
 * 鎻愪緵涓ょ偣涔嬮棿鐨勮矾绾胯绠椼€佽窛绂汇€侀璁℃椂闂寸瓑鍔熻兘
 * 
 * 鏀寔鐨勫湴鍥炬湇鍔″晢锛?
 * - 楂樺痉鍦板浘 (AMap) - 鎺ㄨ崘鍥藉唴浣跨敤
 * - 鐧惧害鍦板浘 (Baidu) - 澶囬€?
 */

// ============================================================================
// 馃攽 API 閰嶇疆鍖哄煙 - 璇峰湪姝ゅ濉叆鎮ㄧ殑 API Key
// ============================================================================

/**
 * 銆愬繀濉€戦珮寰峰湴鍥?Web Service API Key锛堜笌鍦扮悊缂栫爜鍏辩敤锛?
 * 宸插湪 geocodingService.js 涓厤缃紝姝ゅ澶嶇敤
 */
const AMAP_API_KEY = process.env.AMAP_API_KEY || 'YOUR_AMAP_API_KEY_HERE';

/**
 * 銆愬彲閫夈€戠櫨搴﹀湴鍥?AK锛堜笌鍦扮悊缂栫爜鍏辩敤锛?
 */
const BAIDU_MAP_AK = process.env.BAIDU_MAP_AK || 'YOUR_BAIDU_MAP_AK_HERE';

/**
 * 銆愬彲閫夈€戞槸鍚﹀惎鐢ㄧ紦瀛?
 */
const ENABLE_ROUTECACHE = process.env.ENABLE_ROUTECACHE === 'true';
const { wgs84ToGcj02 } = require('../utils/coordTransform');

// ============================================================================
// 鏈嶅姟瀹炵幇
// ============================================================================

let redisClient = null;

if (ENABLE_ROUTECACHE) {
  try {
    const redis = require('redis');
    redisClient = redis.createClient({
      url: process.env.REDIS_URL || 'redis://localhost:6379',
    });
    redisClient.connect().catch(console.error);
  } catch (err) {
    console.warn('[Routing] Redis 杩炴帴澶辫触锛岀紦瀛樺姛鑳藉凡绂佺敤:', err.message);
  }
}

/**
 * 浠庣紦瀛樿幏鍙栬矾绾匡紙濡傛灉鍚敤锛?
 */
async function getCachedRoute(cacheKey) {
  if (!ENABLE_ROUTECACHE || !redisClient) return null;
  
  try {
    const cached = await redisClient.get(cacheKey);
    return cached ? JSON.parse(cached) : null;
  } catch (err) {
    console.warn('[Routing] 缂撳瓨璇诲彇澶辫触:', err.message);
    return null;
  }
}

/**
 * 鍐欏叆缂撳瓨锛堝鏋滃惎鐢級
 */
async function setCachedRoute(cacheKey, data, ttlSeconds = 3600) {
  if (!ENABLE_ROUTECACHE || !redisClient) return;
  
  try {
    await redisClient.setEx(cacheKey, ttlSeconds, JSON.stringify(data));
  } catch (err) {
    console.warn('[Routing] 缂撳瓨鍐欏叆澶辫触:', err.message);
  }
}

/**
 * 浣跨敤楂樺痉鍦板浘璁＄畻椹捐溅璺嚎
 * @param {number} originLng - 璧风偣缁忓害
 * @param {number} originLat - 璧风偣绾害
 * @param {number} destLng - 缁堢偣缁忓害
 * @param {number} destLat - 缁堢偣绾害
 * @param {Object} [options] - 鍙€夊弬鏁?
 * @param {string} [options.strategy='0'] - 璺緞绛栫暐 (0=閫熷害浼樺厛, 1=璐圭敤浼樺厛, 2=璺濈浼樺厛绛?
 * @param {boolean} [options.avoidHighway=false] - 鏄惁閬垮紑楂橀€?
 * @returns {Promise<Object>} 璺嚎淇℃伅瀵硅薄
 */
async function calculateDrivingRoute(originLng, originLat, destLng, destLat, options = {}) {
  const cacheKey = `route:amap:${originLng.toFixed(5)},${originLat.toFixed(5)}-${destLng.toFixed(5)},${destLat.toFixed(5)}-${options.strategy || '0'}`;
  
  // 灏濊瘯浠庣紦瀛樿幏鍙?
  const cached = await getCachedRoute(cacheKey);
  if (cached) {
    return cached;
  }
  
  if (AMAP_API_KEY === 'YOUR_AMAP_API_KEY_HERE') {
    throw new Error('AMAP_API_KEY 鏈厤缃紝璇峰湪 server/.env 涓坊鍔犻珮寰峰湴鍥?API Key');
  }
  
  const [originGcjLng, originGcjLat] = wgs84ToGcj02(originLng, originLat);
  const [destGcjLng, destGcjLat] = wgs84ToGcj02(destLng, destLat);
  const baseUrl = 'https://restapi.amap.com/v3/direction/driving';
  const params = new URLSearchParams({
    origin: `${originGcjLng},${originGcjLat}`,
    destination: `${destGcjLng},${destGcjLat}`,
    key: AMAP_API_KEY,
    strategy: options.strategy || '0',
    avoidhighway: options.avoidHighway ? '1' : '0',
    show_fields: 'cost,polyline',
  });
  
  const response = await fetch(`${baseUrl}?${params}`);
  const data = await response.json();
  
  if (data.status !== '1') {
    throw new Error(`楂樺痉鍦板浘璺緞瑙勫垝閿欒 (${data.infocode}): ${data.info}`);
  }
  
  if (!data.route.paths || data.route.paths.length === 0) {
    throw new Error('未找到可行路线');
  }
  
  const path = data.route.paths[0]; // 鍙栫涓€鏉¤矾绾?
  
  const result = {
    provider: 'amap',
    distance: parseInt(path.distance), // 绫?
    duration: parseInt(path.duration), // 绉?
    tolls: parseFloat(path.tolls || 0), // 杩囪矾璐瑰厓
    trafficLights: parseInt(path.traffic_lights || 0), // 绾㈢豢鐏暟
    
    // 璺嚎姒傝
    overview: {
      startAddress: data.route.origin?.name || '',
      endAddress: data.route.destination?.name || '',
      taxiCost: parseFloat(path.taxi_cost || 0), // 鎵撹溅璐圭敤浼扮畻
    },
    
    // 璇︾粏姝ラ
    steps: (path.steps || []).map((step, idx) => ({
      stepIndex: idx + 1,
      instruction: step.instruction, // 瀵艰埅鎸囦护鏂囨湰
      action: step.action, // 鍔ㄤ綔绫诲瀷
      orientation: step.orientation, // 鏂瑰悜
      road: step.road, // 閬撹矾鍚嶇О
      distance: parseInt(step.distance), // 鏈璺濈锛堢背锛?
      duration: parseInt(step.duration), // 鏈鏃堕棿锛堢锛?
      polyline: step.polyline, // keep AMap native GCJ-02 polyline for frontend AMap rendering
      assistNodes: step.assist_nodes || [], // 杈呭姪鑺傜偣
    })),
    
    // 鍘熷鏁版嵁锛堜緵璋冭瘯锛?
    raw: path,
  };
  
  // 鍐欏叆缂撳瓨
  await setCachedRoute(cacheKey, result);
  
  return result;
}

/**
 * 浣跨敤鐧惧害鍦板浘璁＄畻椹捐溅璺嚎锛堝鐢ㄦ柟妗堬級
 * @param {number} originLng - 璧风偣缁忓害
 * @param {number} originLat - 璧风偣绾害
 * @param {number} destLng - 缁堢偣缁忓害
 * @param {number} destLat - 缁堢偣绾害
 * @returns {Promise<Object>} 璺嚎淇℃伅瀵硅薄
 */
async function calculateDrivingRouteWithBaidu(originLng, originLat, destLng, destLat) {
  const cacheKey = `route:baidu:${originLng.toFixed(5)},${originLat.toFixed(5)}-${destLng.toFixed(5)},${destLat.toFixed(5)}`;
  
  // 灏濊瘯浠庣紦瀛樿幏鍙?
  const cached = await getCachedRoute(cacheKey);
  if (cached) {
    return cached;
  }
  
  if (BAIDU_MAP_AK === 'YOUR_BAIDU_MAP_AK_HERE') {
    throw new Error('BAIDU_MAP_AK 鏈厤缃紝璇峰湪 server/.env 涓坊鍔犵櫨搴﹀湴鍥?AK');
  }
  
  const baseUrl = 'https://api.map.baidu.com/directionlite/v1/driving';
  const params = new URLSearchParams({
    ak: BAIDU_MAP_AK,
    origin: `${originLat},${originLng}`, // 娉ㄦ剰锛氱櫨搴︽槸 lat,lng 椤哄簭
    destination: `${destLat},${destLng}`,
    coord_type_input: 'wgs84',
    coord_type_output: 'bd09ll',
  });
  
  const response = await fetch(`${baseUrl}?${params}`);
  const data = await response.json();
  
  if (data.status !== 0) {
    throw new Error(`鐧惧害鍦板浘璺緞瑙勫垝閿欒 (${data.status}): ${data.message}`);
  }
  
  const result_data = data.result.routes[0];
  
  return {
    provider: 'baidu',
    distance: parseInt(result_data.distance),
    duration: parseInt(result_data.duration),
    tolls: 0, // 鐧惧害鍏嶈垂鐗堜笉鎻愪緵杩囪矾璐?
    trafficLights: 0,
    
    overview: {
      startAddress: '',
      endAddress: '',
      taxiCost: 0,
    },
    
    steps: (result_data.steps || []).map((step, idx) => ({
      stepIndex: idx + 1,
      instruction: step.instructions,
      action: '',
      orientation: '',
      road: step.road_name || '',
      distance: parseInt(step.distance),
      duration: parseInt(step.duration),
      polyline: step.polyline,
      assistNodes: [],
    })),
    
    raw: result_data,
  };
}

/**
 * 缁熶竴鐨勮矾寰勮鍒掓帴鍙?
 * @param {number} originLng - 璧风偣缁忓害
 * @param {number} originLat - 璧风偣绾害
 * @param {number} destLng - 缁堢偣缁忓害
 * @param {number} destLat - 缁堢偣绾害
 * @param {Object} [options] - 鍙€夊弬鏁?
 * @param {string} [options.provider='amap'] - 鍦板浘鎻愪緵鍟?
 * @param {string} [options.strategy='0'] - 璺緞绛栫暐
 * @returns {Promise<Object>} 璺嚎淇℃伅瀵硅薄
 */
async function calculateRoute(originLng, originLat, destLng, destLat, options = {}) {
  // 楠岃瘉鍧愭爣
  const isValidCoord = (lng, lat) => 
    lng >= -180 && lng <= 180 && lat >= -90 && lat <= 90;
  
  if (!isValidCoord(originLng, originLat) || !isValidCoord(destLng, destLat)) {
    throw new Error(`鏃犳晥鍧愭爣: origin=[${originLng}, ${originLat}], dest=[${destLng}, ${destLat}]`);
  }
  
  const provider = options.provider || 'amap';
  
  try {
    switch (provider.toLowerCase()) {
      case 'amap':
      case 'gaode':
        return await calculateDrivingRoute(originLng, originLat, destLng, destLat, options);
      case 'baidu':
        return await calculateDrivingRouteWithBaidu(originLng, originLat, destLng, destLat);
      default:
        throw new Error(`涓嶆敮鎸佺殑鍦板浘鎻愪緵鍟? ${provider}`);
    }
  } catch (err) {
    console.error(`[Routing] ${provider} 璺緞瑙勫垝澶辫触:`, err.message);
    
    // 濡傛灉鏄富鎻愪緵鍟嗗け璐ワ紝灏濊瘯澶囩敤鏂规
    if (provider === 'amap' && BAIDU_MAP_AK !== 'YOUR_BAIDU_MAP_AK_HERE') {
      console.log('[Routing] 灏濊瘯鍒囨崲鍒扮櫨搴﹀湴鍥?..');
      return await calculateDrivingRouteWithBaidu(originLng, originLat, destLng, destLat);
    }
    
    throw err;
  }
}

/**
 * 鎵归噺璁＄畻璺嚎锛堢敤浜庡鐩爣浼樺寲锛?
 * @param {Object} origin - 璧风偣 {lng, lat}
 * @param {Array} destinations - 缁堢偣鏁扮粍 [{lng, lat, id}, ...]
 * @param {number} [concurrency=3] - 骞跺彂鏁?
 * @returns {Promise<Array>} 璺嚎缁撴灉鏁扮粍
 */
async function batchCalculateRoutes(origin, destinations, concurrency = 3) {
  const results = [];
  const queue = [...destinations];
  const inProgress = new Set();
  
  return new Promise((resolve, reject) => {
    const processNext = async () => {
      if (queue.length === 0 && inProgress.size === 0) {
        resolve(results);
        return;
      }
      
      while (inProgress.size < concurrency && queue.length > 0) {
        const dest = queue.shift();
        const index = destinations.indexOf(dest);
        inProgress.add(index);
        
        calculateRoute(origin.lng, origin.lat, dest.lng, dest.lat)
          .then(route => {
            results[index] = {
              ...dest,
              route,
              success: true,
            };
          })
          .catch(err => {
            results[index] = {
              ...dest,
              error: err.message,
              success: false,
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

/**
 * 璁＄畻鐩寸嚎璺濈锛圚aversine鍏紡锛屾棤闇€API锛?
 * @param {number} lng1 - 璧风偣缁忓害
 * @param {number} lat1 - 璧风偣绾害
 * @param {number} lng2 - 缁堢偣缁忓害
 * @param {number} lat2 - 缁堢偣绾害
 * @returns {number} 璺濈锛堢背锛?
 */
function calculateStraightDistance(lng1, lat1, lng2, lat2) {
  const R = 6371e3; // 鍦扮悆鍗婂緞锛堢背锛?
  const 蠁1 = (lat1 * Math.PI) / 180;
  const 蠁2 = (lat2 * Math.PI) / 180;
  const 螖蠁 = ((lat2 - lat1) * Math.PI) / 180;
  const 螖位 = ((lng2 - lng1) * Math.PI) / 180;
  
  const a = Math.sin(螖蠁 / 2) * Math.sin(螖蠁 / 2) +
            Math.cos(蠁1) * Math.cos(蠁2) *
            Math.sin(螖位 / 2) * Math.sin(螖位 / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  
  return Math.round(R * c);
}

module.exports = {
  calculateRoute,
  batchCalculateRoutes,
  calculateDrivingRoute,
  calculateDrivingRouteWithBaidu,
  calculateStraightDistance,
};


