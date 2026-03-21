const mongoose = require('mongoose');

/**
 * SOS 求救记录 Schema
 *
 * senderMac   - 发送者蓝牙 MAC 地址（唯一标识一台设备）
 * location    - GeoJSON Point，存储经纬度，支持 2dsphere 空间索引
 * bloodType   - 血型编号 (0=A, 1=B, 2=AB, 3=O, -1=未知)
 * timestamp   - 设备端产生求救信号的时间（非服务器入库时间）
 * status      - 'active'（待救援）| 'rescued'（已救援）| 'false_alarm'（误报）
 * reportedBy  - 上报过该信号的"数据骡子"MAC 地址列表（长度即为置信度）
 * createdAt   - 服务器首次入库时间（由 timestamps 自动生成）
 */
const sosRecordSchema = new mongoose.Schema(
  {
    senderMac: {
      type: String,
      required: [true, 'senderMac 为必填项'],
      uppercase: true,
      trim: true,
    },
    location: {
      type: {
        type: String,
        enum: ['Point'],
        required: true,
        default: 'Point',
      },
      coordinates: {
        // GeoJSON 标准：[longitude, latitude]
        type: [Number],
        required: true,
        validate: {
          validator: (v) =>
            Array.isArray(v) &&
            v.length === 2 &&
            v[0] >= -180 && v[0] <= 180 &&
            v[1] >= -90  && v[1] <= 90,
          message: 'coordinates 必须为合法的 [longitude, latitude]',
        },
      },
    },
    bloodType: {
      type: Number,
      enum: [-1, 0, 1, 2, 3],
      default: -1,
    },
    timestamp: {
      type: Date,
      required: [true, 'timestamp 为必填项'],
      index: true,
    },
    status: {
      type: String,
      enum: ['active', 'rescued', 'false_alarm'],
      default: 'active',
      index: true,
    },
    reportedBy: {
      type: [String],
      default: [],
    },
  },
  {
    timestamps: true, // 自动添加 createdAt / updatedAt
    versionKey: false,
  }
);

// 2dsphere 空间索引，支持地理位置查询
sosRecordSchema.index({ location: '2dsphere' });

// 复合索引：按 senderMac + timestamp 快速做去重查询
sosRecordSchema.index({ senderMac: 1, timestamp: 1 });

/**
 * 虚拟字段：置信度 = reportedBy 去重后的长度
 * （同一骡子多次上报只算一次）
 */
sosRecordSchema.virtual('confidence').get(function () {
  return new Set(this.reportedBy).size;
});

sosRecordSchema.set('toJSON', { virtuals: true });
sosRecordSchema.set('toObject', { virtuals: true });

module.exports = mongoose.model('SosRecord', sosRecordSchema);
