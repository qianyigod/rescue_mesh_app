require('dotenv').config();
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const http = require('http');
const { Server } = require('socket.io');

const sosRoutes = require('./routes/sos');
const socketService = require('./socket');

const app = express();
const server = http.createServer(app);

// Middleware
app.use(cors());
app.use(express.json());

// Socket.io setup
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST']
  }
});

// Initialize Socket.io
socketService.init(io);

// Routes
app.use('/api/sos', sosRoutes);

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// MongoDB connection
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/rescue_mesh';
const PORT = process.env.PORT || 3000;

mongoose.connect(MONGODB_URI)
  .then(() => {
    console.log('[Server] MongoDB connected');
    
    // Start server only after DB connection
    server.listen(PORT, '0.0.0.0', () => {
      console.log(`[Server] Listening on http://0.0.0.0:${PORT}`);
    });
  })
  .catch((error) => {
    console.error('[Server] MongoDB connection error:', error);
    process.exit(1);
  });

// Graceful shutdown
process.on('SIGINT', async () => {
  console.log('[Server] Shutting down gracefully...');
  server.close(() => {
    mongoose.connection.close(() => {
      process.exit(0);
    });
  });
});
