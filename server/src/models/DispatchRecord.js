const mongoose = require('mongoose');

const dispatchRecordSchema = new mongoose.Schema(
  {
    sosRecordId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'SosRecord',
      required: true,
      index: true,
    },
    actionType: {
      type: String,
      enum: ['reported', 'relay_merged', 'acknowledged', 'dispatch', 'closed'],
      required: true,
      index: true,
    },
    actorType: {
      type: String,
      enum: ['system', 'relay', 'dispatcher'],
      default: 'dispatcher',
    },
    actorName: {
      type: String,
      default: '',
      trim: true,
    },
    note: {
      type: String,
      default: '',
      trim: true,
    },
    meta: {
      workflowStatus: { type: String, default: '' },
      status: { type: String, default: '' },
      muleId: { type: String, default: '', trim: true },
      teamName: { type: String, default: '', trim: true },
      hospitalName: { type: String, default: '', trim: true },
      etaMinutes: { type: Number, default: null },
      resultStatus: { type: String, default: '', trim: true },
    },
  },
  {
    timestamps: true,
    versionKey: false,
  }
);

dispatchRecordSchema.index({ sosRecordId: 1, createdAt: -1 });

module.exports = mongoose.model('DispatchRecord', dispatchRecordSchema);
