import rateLimit from 'express-rate-limit'
import { RedisStore } from 'rate-limit-redis'
import Redis from 'ioredis'

/**
 * Rate limiters.
 *
 * - Store: shared Redis when REDIS_HOST is configured (multi-instance safe),
 *   in-memory fallback for local dev.
 * - /health must stay exempt so container HEALTHCHECKs and external
 *   monitors can never exhaust the shared bucket.
 */

const redisClient = process.env.REDIS_HOST ? new Redis({
  host: process.env.REDIS_HOST,
  port: +(process.env.REDIS_PORT || 6379),
  password: process.env.REDIS_PASSWORD || undefined,
  lazyConnect: true,
  maxRetriesPerRequest: 1,
}) : null

if (redisClient) {
  redisClient.connect().catch((err) =>
    console.warn(`[WARN] Redis connect failed, rate limiting falls back to in-memory: ${err.message}`)
  )
}

const store = redisClient
  ? new RedisStore({
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      sendCommand: (...args: string[]) => (redisClient as any).call(...args) as any,
    })
  : undefined

export const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: +(process.env.RATE_LIMIT_MAX || 600),
  standardHeaders: true,
  legacyHeaders: false,
  ...(store ? { store } : {}),
  message: { success: false, error: 'Too many requests, please try again later' }
})

export const authLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: +(process.env.AUTH_RATE_LIMIT_MAX || 10),
  standardHeaders: true,
  legacyHeaders: false,
  ...(store ? { store } : {}),
  message: { success: false, error: 'Too many auth attempts, please try again later' }
})
