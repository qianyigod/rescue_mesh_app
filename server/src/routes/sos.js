const express = require('express');
const router = express.Router();
const SosRecord = require('../models/SosRecord');
const socketService = require('../socket');

// 去重时间容差：10 分钟（毫秒）
const DEDUP_WINDOW_MS = 10 * 60 * 1000;

/**
 * POST /api/sos/sync
 *
 * "数据骡子"恢复网络后批量上传暂存的 SOS 信号。
 *
 * 请求体示例：
 * {
 *   "muleId": "AA:BB:CC:DD:EE:FF",        // 骡子自身 MAC
 *   "records": [
 *     {
 *       "senderMac": "11:22:33:44:55:66",
 *       "longitude": 116.3974,
 *       "latitude":  39.9093,
 *       "bloodType": 0,
 *       "timestamp": "2024-06-15T08:30:00.000Z"
 *     },
 *     ...
 *   ]
 * }
 *
 * 响应体：
 * {
 *   "created": 3,    // 新插入条数
 *   "merged":  2,    // 已存在、仅追加骡子 ID 的条数
 *   "invalid": 1,    // 解析/校验失败条数
 *   "details": [...]  // 每条记录的处理结果
 * }
 */
router.post('/sync', async (req, res) => {
  const { muleId, records } = req.body;

  // ── 基础校验 ──────────────────────────────────────────────
  if (!muleId || typeof muleId !== 'string') {
    return res.status(400).json({ error: 'muleId 为必填字符串' });
  }
  if (!Array.isArray(records) || records.length === 0) {
    return res.status(400).json({ error: 'records 必须为非空数组' });
  }
  if (records.length > 1000) {
    return res.status(400).json({ error: '单次上传不得超过 1000 条' });
  }

  const normalizedMuleId = muleId.toUpperCase().trim();
  const details = [];
  let created = 0, merged = 0, invalid = 0;

  // ── 逐条处理（串行保证同一批次内不会互相重复插入）──────────
  for (const raw of records) {
    try {
      const record = normalizeRecord(raw);   // 标准化并校验字段
      const result = await upsertSosRecord(record, normalizedMuleId);

      if (result.action === 'created') {
        created++;
        // 立刻广播新 SOS 到前端大屏
        socketService.broadcastNewSos(result.doc);
      } else {
        merged++;
      }

      details.push({
        senderMac: record.senderMac,
        action: result.action,
        id: result.doc._id,
      });
    } catch (err) {
      invalid++;
      details.push({ raw, action: 'invalid', reason: err.message });
    }
  }

  return res.status(200).json({ created, merged, invalid, details });
});

/**
 * GET /api/sos/active
 *
 * 返回所有 status === 'active' 的求救点，供大屏初次渲染地图使用。
 * 按 timestamp 降序（最新的排在前面）。
 */
router.get('/active', async (req, res) => {
  try {
    const activeSos = await SosRecord.find({ status: 'active' })
      .sort({ timestamp: -1 })
      .lean({ virtuals: true }); // lean 提升读性能，virtuals:true 保留 confidence

    return res.status(200).json({
      count: activeSos.length,
      data: activeSos,
    });
  } catch (err) {
    console.error('[GET /active]', err);
    return res.status(500).json({ error: '服务器内部错误' });
  }
});

// ════════════════════════════════════════════════════════════
//  工具函数
// ════════════════════════════════════════════════════════════

/**
 * 将请求体中的单条原始记录标准化为写入 DB 的格式。
 * 抛出 Error 表示校验失败。
 */
function normalizeRecord(raw) {
  const { senderMac, longitude, latitude, bloodType, timestamp } = raw;

  if (!senderMac || typeof senderMac !== 'string') {
    throw new Error('senderMac 缺失或类型错误');
  }
  const lon = parseFloat(longitude);
  const lat = parseFloat(latitude);
  if (isNaN(lon) || isNaN(lat)) {
    throw new Error('longitude / latitude 必须为数字');
  }
  if (lon < -180 || lon > 180 || lat < -90 || lat > 90) {
    throw new Error('经纬度超出合法范围');
  }

  const ts = new Date(timestamp);
  if (isNaN(ts.getTime())) {
    throw new Error('timestamp 不是合法的日期字符串');
  }

  return {
    senderMac: senderMac.toUpperCase().trim(),
    location: { type: 'Point', coordinates: [lon, lat] },
    bloodType: Number.isInteger(bloodType) ? bloodType : -1,
    timestamp: ts,
  };
}

/**
 * 核心去重逻辑：
 *   - 在 [timestamp - DEDUP_WINDOW_MS, timestamp + DEDUP_WINDOW_MS] 窗口内
 *     查找同一 senderMac 的记录。
 *   - 找到 → 追加骡子 ID（$addToSet 防止同一骡子重复记录）。
 *   - 未找到 → 新建文档。
 *
 * @returns {{ action: 'created'|'merged', doc: mongoose.Document }}
 */
async function upsertSosRecord(record, muleId) {
  const windowStart = new Date(record.timestamp.getTime() - DEDUP_WINDOW_MS);
  const windowEnd   = new Date(record.timestamp.getTime() + DEDUP_WINDOW_MS);

  const existing = await SosRecord.findOne({
    senderMac: record.senderMac,
    timestamp: { $gte: windowStart, $lte: windowEnd },
  });

  if (existing) {
    // 已存在：追加骡子 MAC，提升置信度
    await SosRecord.updateOne(
      { _id: existing._id },
      { $addToSet: { reportedBy: muleId } }
    );
    existing.reportedBy = [...new Set([...existing.reportedBy, muleId])];
    return { action: 'merged', doc: existing };
  }

  // 全新求救：插入并广播
  const newDoc = await SosRecord.create({
    ...record,
    reportedBy: [muleId],
  });
  return { action: 'created', doc: newDoc };
}

module.exports = router;
