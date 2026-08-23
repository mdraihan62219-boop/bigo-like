import 'dotenv/config'
import express from 'express'
import http from 'http'
import cors from 'cors'
import helmet from 'helmet'
import morgan from 'morgan'
import compression from 'compression'
import routes from './routes'
import healthRoutes from './routes/health.routes'
import { errorHandler } from './middleware/errorHandler'
import { apiLimiter } from './middleware/rateLimiter'
import { initSocket } from './socket'
import { LeaderboardService } from './services/leaderboard.service'
import { logger } from './utils/logger'
import { getAllowedOrigins } from './config/cors'

// ---------------------------------------------------------------------------
// Startup validation — fail fast with a clear message instead of limping on
// undefined secrets until some request hits an obscure error.
// ---------------------------------------------------------------------------
const REQUIRED_ENV = ['JWT_SECRET', 'SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY']
const missing = REQUIRED_ENV.filter((k) => !process.env[k])
if (missing.length > 0 && process.env.NODE_ENV !== 'test') {
  logger.error(`Missing required environment variables: ${missing.join(', ')}`)
  process.exit(1)
}

// Fail-fast WARNINGS for optional integrations still on placeholders —
// the endpoints themselves return 503 instead of silently misbehaving.
{
  const placeholder = (v?: string) => !v || /your-|placeholder|xxx|changeme/i.test(v)
  if (placeholder(process.env.AGORA_APP_ID) || placeholder(process.env.AGORA_APP_CERTIFICATE)) {
    logger.warn('[WARN] AGORA_APP_ID / AGORA_APP_CERTIFICATE are missing or placeholders — live streaming, calls and PK tokens will return 503 until real credentials are set.')
  }
  if (!process.env.FIREBASE_PROJECT_ID || !process.env.FIREBASE_PRIVATE_KEY || !process.env.FIREBASE_CLIENT_EMAIL) {
    logger.warn('[WARN] Firebase env vars not set — push notifications disabled.')
  }
}

const app = express()
const server = http.createServer(app)

// Single reverse-proxy hop (nginx). Without this, express-rate-limit buckets
// every user behind the proxy into one shared IP.
app.set('trust proxy', 1)
const io = initSocket(server)
// Expose the socket server to REST controllers (feed/reseller/host/pk events).
app.set('io', io)

app.use(helmet())
app.use(cors({ origin: getAllowedOrigins(), credentials: true }))
app.use(compression())
app.use(morgan('combined', { skip: (req) => req.path === '/health' }))
app.use(express.json({ limit: '1mb' }))
app.use(express.urlencoded({ extended: true }))

// Health check BEFORE the global limiter so it can never be throttled.
app.use(healthRoutes)

app.use(apiLimiter)
app.use('/api/v1', routes)

// 404 for unmatched API routes (previously fell through to Express default).
app.use((_req, res) => {
  res.status(404).json({ success: false, error: 'Not found' })
})

app.use(errorHandler)

LeaderboardService.init()

const PORT = process.env.PORT || 3000
server.listen(PORT, () => {
  logger.info(`Server running on port ${PORT}`)
})

// ---------------------------------------------------------------------------
// Process-level resilience + graceful shutdown
// ---------------------------------------------------------------------------
process.on('unhandledRejection', (reason) => {
  logger.error(`Unhandled rejection: ${reason}`)
})

process.on('uncaughtException', (err) => {
  logger.error(`Uncaught exception: ${err.message}`)
  shutdown(1)
})

let shuttingDown = false
function shutdown(code = 0) {
  if (shuttingDown) return
  shuttingDown = true
  logger.info('Shutting down gracefully…')
  server.close(() => {
    io.close()
    process.exit(code)
  })
  // Force-exit if connections refuse to drain.
  setTimeout(() => process.exit(code), 10_000).unref()
}

process.on('SIGTERM', () => shutdown(0))
process.on('SIGINT', () => shutdown(0))

export { app, server }
