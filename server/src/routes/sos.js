const express = require('express');
const mongoose = require('mongoose');

const SosRecord = require('../models/SosRecord');
const socketService = require('../socket');

const router = express.Router();
const DEDUP_WINDOW_MS = 10 * 60 * 1000;

router.post('/sync', async (req, res) => {
  const { muleId, records } = req.body || {};

  if (!muleId || typeof muleId !== 'string') {
    return res.status(400).json({ error: 'muleId is required and must be a string.' });
  }

  if (!Array.isArray(records) || records.length === 0) {
    return res.status(400).json({ error: 'records must be a non-empty array.' });
  }

  if (records.length > 1000) {
    return res.status(400).json({ error: 'A single sync request cannot exceed 1000 records.' });
  }

  const normalizedMuleId = muleId.toUpperCase().trim();
  const details = [];
  let created = 0;
  let merged = 0;
  let invalid = 0;

  for (const rawRecord of records) {
    try {
      const normalizedRecord = normalizeRecord(rawRecord);
      const medicalProfile = normalizeMedicalProfile(rawRecord.medicalProfile);
      const result = await upsertSosRecord(
        normalizedRecord,
        normalizedMuleId,
        medicalProfile,
      );

      if (result.action === 'created') {
        created += 1;
        socketService.broadcastNewSos(result.doc);
      } else {
        merged += 1;
      }

      details.push({
        senderMac: normalizedRecord.senderMac,
        action: result.action,
        id: result.doc._id,
      });
    } catch (error) {
      invalid += 1;
      details.push({
        raw: rawRecord,
        action: 'invalid',
        reason: error.message,
      });
    }
  }

  return res.status(200).json({ created, merged, invalid, details });
});

router.get('/active', async (req, res) => {
  try {
    const activeSos = await SosRecord.find({ status: 'active' })
      .sort({ timestamp: -1 })
      .lean({ virtuals: true });

    return res.status(200).json({
      count: activeSos.length,
      data: activeSos,
    });
  } catch (error) {
    console.error('[GET /active]', error);
    return res.status(500).json({ error: 'Failed to load active SOS records.' });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    if (!mongoose.Types.ObjectId.isValid(req.params.id)) {
      return res.status(400).json({ error: 'Invalid SOS record id.' });
    }

    const deletedRecord = await SosRecord.findByIdAndDelete(req.params.id);
    if (!deletedRecord) {
      return res.status(404).json({ error: 'SOS record not found.' });
    }

    socketService.broadcastDeletedSos(deletedRecord);

    return res.status(200).json({
      success: true,
      id: req.params.id,
    });
  } catch (error) {
    console.error('[DELETE /:id]', error);
    return res.status(500).json({ error: 'Failed to delete SOS record.' });
  }
});

function normalizeRecord(raw) {
  const { senderMac, longitude, latitude, bloodType, timestamp } = raw || {};

  if (!senderMac || typeof senderMac !== 'string') {
    throw new Error('senderMac is required and must be a string.');
  }

  const longitudeNumber = Number.parseFloat(longitude);
  const latitudeNumber = Number.parseFloat(latitude);

  if (Number.isNaN(longitudeNumber) || Number.isNaN(latitudeNumber)) {
    throw new Error('longitude and latitude must be valid numbers.');
  }

  if (
    longitudeNumber < -180 ||
    longitudeNumber > 180 ||
    latitudeNumber < -90 ||
    latitudeNumber > 90
  ) {
    throw new Error('longitude or latitude is out of range.');
  }

  const parsedTimestamp = new Date(timestamp);
  if (Number.isNaN(parsedTimestamp.getTime())) {
    throw new Error('timestamp must be a valid date string.');
  }

  const parsedBloodType = Number.parseInt(bloodType, 10);

  return {
    senderMac: senderMac.toUpperCase().trim(),
    location: {
      type: 'Point',
      coordinates: [longitudeNumber, latitudeNumber],
    },
    bloodType: Number.isInteger(parsedBloodType) ? parsedBloodType : -1,
    timestamp: parsedTimestamp,
  };
}

function normalizeMedicalProfile(rawProfile) {
  if (!rawProfile || typeof rawProfile !== 'object') {
    return {};
  }

  const profile = {
    name: String(rawProfile.name || '').trim(),
    age: String(rawProfile.age || '').trim(),
    bloodTypeDetail: Number.isInteger(rawProfile.bloodTypeDetail)
      ? rawProfile.bloodTypeDetail
      : -1,
    medicalHistory: String(rawProfile.medicalHistory || '').trim(),
    allergies: String(rawProfile.allergies || '').trim(),
    emergencyContact: String(rawProfile.emergencyContact || '').trim(),
  };

  return Object.values(profile).some((value) => value !== '' && value !== -1)
    ? profile
    : {};
}

async function upsertSosRecord(record, muleId, medicalProfile = {}) {
  const windowStart = new Date(record.timestamp.getTime() - DEDUP_WINDOW_MS);
  const windowEnd = new Date(record.timestamp.getTime() + DEDUP_WINDOW_MS);

  const existingRecord = await SosRecord.findOne({
    senderMac: record.senderMac,
    timestamp: { $gte: windowStart, $lte: windowEnd },
  });

  if (existingRecord) {
    const update = {
      $addToSet: { reportedBy: muleId },
    };

    if (Object.keys(medicalProfile).length > 0) {
      update.$set = { medicalProfile };
    }

    await SosRecord.updateOne({ _id: existingRecord._id }, update);
    existingRecord.reportedBy = [...new Set([...existingRecord.reportedBy, muleId])];

    if (Object.keys(medicalProfile).length > 0) {
      existingRecord.medicalProfile = medicalProfile;
    }

    return { action: 'merged', doc: existingRecord };
  }

  const createdRecord = await SosRecord.create({
    ...record,
    reportedBy: [muleId],
    medicalProfile: Object.keys(medicalProfile).length > 0 ? medicalProfile : undefined,
  });

  return { action: 'created', doc: createdRecord };
}

module.exports = router;
