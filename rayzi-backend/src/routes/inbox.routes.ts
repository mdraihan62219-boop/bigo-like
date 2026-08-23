import { Router } from 'express'
import { InboxController } from '../controllers/inbox.controller'
import { authenticate } from '../middleware/auth'

const router = Router()
router.use(authenticate)

router.get('/conversations', InboxController.conversations)
router.post('/conversations/open/:userId', InboxController.open)
router.get('/conversations/:id/messages', InboxController.messages)
router.post('/conversations/:id/messages', InboxController.messages)
router.put('/conversations/:id/read', InboxController.messages)
router.post('/conversations/:id/call', InboxController.startCall)
router.post('/conversations/:id/end-call', InboxController.endCall)

export default router
