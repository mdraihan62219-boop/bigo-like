import { Router } from 'express'
import { FriendController } from '../controllers/friend.controller'
import { authenticate } from '../middleware/auth'

const router = Router()
router.use(authenticate)

router.post('/request/:userId', FriendController.sendRequest)
router.post('/accept/:requestId', FriendController.respond)
router.post('/reject/:requestId', FriendController.respond)
router.get('/', FriendController.list)
router.get('/requests', FriendController.requests)
router.get('/count/:userId', FriendController.count)

export default router
