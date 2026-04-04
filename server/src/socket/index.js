let _io = null;

function init(io) {
  _io = io;

  io.on('connection', (socket) => {
    console.log(`[Socket.io] Dashboard connected: ${socket.id}`);

    socket.on('disconnect', (reason) => {
      console.log(`[Socket.io] Dashboard disconnected (${socket.id}): ${reason}`);
    });
  });

  console.log('[Socket.io] Realtime push service is ready');
}

function broadcastNewSos(sosDoc) {
  if (!_io) {
    console.warn('[Socket.io] Socket server is not initialized, cannot broadcast new SOS');
    return;
  }

  _io.emit('new_sos_alert', sosDoc.toJSON());
  console.log(`[Socket.io] Broadcast new_sos_alert -> MAC: ${sosDoc.senderMac}`);
}

function broadcastDeletedSos(sosDoc) {
  if (!_io) {
    console.warn('[Socket.io] Socket server is not initialized, cannot broadcast deleted SOS');
    return;
  }

  _io.emit('sos_deleted', {
    id: String(sosDoc._id),
    senderMac: sosDoc.senderMac,
    timestamp: sosDoc.timestamp,
  });
  console.log(`[Socket.io] Broadcast sos_deleted -> MAC: ${sosDoc.senderMac}`);
}

module.exports = {
  init,
  broadcastNewSos,
  broadcastDeletedSos,
};
