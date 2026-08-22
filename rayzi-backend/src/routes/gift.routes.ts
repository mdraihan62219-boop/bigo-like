import { Router } from 'express'
import { GiftController } from '../controllers/gift.controller'
import { authenticate } from '../middleware/auth'

const router = Router()

router.get('/', authenticate, GiftController.list)
router.post('/send', authenticate, GiftController.send)
router.get('/transactions', authenticate, GiftController.getTransactions)

export default router