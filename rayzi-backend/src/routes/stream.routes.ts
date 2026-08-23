import { Router } from 'express'
import { StreamController } from '../controllers/stream.controller'
import { authenticate, optionalAuth } from '../middleware/auth'

const router = Router()

router.get('/', optionalAuth, StreamController.list)
router.post('/', authenticate, StreamController.create)
router.get('/:streamId', optionalAuth, StreamController.getById)
router.get('/:streamId/token', authenticate, StreamController.getToken)
router.post('/:streamId/join', authenticate, StreamController.join)
router.post('/:streamId/leave', authenticate, StreamController.leave)
router.post('/:streamId/end', authenticate, StreamController.end)
router.post('/:streamId/like', authenticate, StreamController.like)

export default router