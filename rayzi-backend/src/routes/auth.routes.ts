import { Router } from 'express'
import { AuthController } from '../controllers/auth.controller'
import { authLimiter } from '../middleware/rateLimiter'
import { authenticate } from '../middleware/auth'

const router = Router()

router.post('/register', authLimiter, AuthController.register)
router.post('/login', authLimiter, AuthController.login)
router.post('/social', authLimiter, AuthController.socialLogin)
router.get('/me', authenticate, AuthController.me)

export default router