let _io = null;

/**
 * 初始化 Socket.io 实例（在 index.js 中调用一次）
 */
function init(io) {
  _io = io;

  io.on('connection', (socket) => {
    console.log(`[Socket.io] 大屏客户端已连接: ${socket.id}`);

    socket.on('disconnect', (reason) => {
      console.log(`[Socket.io] 客户端断开 (${socket.id}): ${reason}`);
    });
  });

  console.log('[Socket.io] 实时推送服务已就绪');
}

/**
 * 向所有已连接的大屏广播新 SOS 告警
 *
 * @param {object} sosDoc - Mongoose SosRecord 文档（会自动序列化为 JSON）
 */
function broadcastNewSos(sosDoc) {
  if (!_io) {
    console.warn('[Socket.io] 尚未初始化，无法广播');
    return;
  }
  _io.emit('new_sos_alert', sosDoc.toJSON());
  console.log(`[Socket.io] 广播 new_sos_alert -> MAC: ${sosDoc.senderMac}`);
}

function broadcastSosUpdate(sosDoc) {
  if (!_io) {
    console.warn('[Socket.io] 尚未初始化，无法广播更新');
    return;
  }

  const payload = typeof sosDoc?.toJSON === 'function' ? sosDoc.toJSON() : sosDoc;
  _io.emit('sos_updated', payload);
  console.log(`[Socket.io] 广播 sos_updated -> MAC: ${payload.senderMac}`);
}

module.exports = { init, broadcastNewSos, broadcastSosUpdate };
