import { Router } from 'express'

const startedAt = Date.now()

const router = Router()

router.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    uptimeSeconds: Math.floor((Date.now() - startedAt) / 1000),
    timestamp: new Date().toISOString(),
    env: process.env.NODE_ENV || 'development',
  })
})

export default router
