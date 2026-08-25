import { Router } from 'express'
import { GamesController } from '../controllers/games.controller'
import { authenticate } from '../middleware/auth'

const router = Router()
router.use(authenticate)

router.get('/', GamesController.list)
router.post('/score', GamesController.submitScore)

export default router
