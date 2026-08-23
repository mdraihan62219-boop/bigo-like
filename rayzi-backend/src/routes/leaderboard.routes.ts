import { Router } from 'express'
import { LeaderboardController } from '../controllers/leaderboard.controller'
import { authenticate } from '../middleware/auth'

const router = Router()
router.use(authenticate)
router.get('/', LeaderboardController.get)

export default router
