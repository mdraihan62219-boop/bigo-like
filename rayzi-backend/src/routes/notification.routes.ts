import { Router } from 'express'
import { NotificationController } from '../controllers/notification.controller'
import { authenticate } from '../middleware/auth'

const router = Router()

router.get('/', authenticate, NotificationController.list)
router.post('/:id/read', authenticate, NotificationController.markRead)
router.post('/read-all', authenticate, NotificationController.markAllRead)
router.post('/push-token', authenticate, NotificationController.registerPushToken)

export default router