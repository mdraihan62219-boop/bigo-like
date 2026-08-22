import Redis from 'ioredis'

let _redis: Redis | null = null

if (process.env.REDIS_HOST) {
  _redis = new Redis({
    host: process.env.REDIS_HOST,
    port: parseInt(process.env.REDIS_PORT || '6379'),
    password: process.env.REDIS_PASSWORD,
    retryStrategy: (times) => Math.min(times * 50, 2000)
  })

  _redis.on('connect', () => console.log('Redis connected'))
  _redis.on('error', (err) => console.error('Redis error:', err.message))
} else {
  console.log('Redis not configured - caching disabled')
}

export const redis = _redis as Redis | null