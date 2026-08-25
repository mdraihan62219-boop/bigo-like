import { Router } from 'express'
import { RoomController } from '../controllers/room.controller'
import { authenticate } from '../middleware/auth'

const router = Router()

router.get('/', authenticate, RoomController.list)
router.post('/', authenticate, RoomController.create)
router.get('/:id', authenticate, RoomController.getById)
router.get('/:roomId/token', authenticate, RoomController.getToken)
router.post('/:roomId/join', authenticate, RoomController.join)
router.post('/:roomId/leave', authenticate, RoomController.leave)
router.put('/:roomId/participants/:userId', authenticate, RoomController.updateParticipantRole)
router.post('/:roomId/close', authenticate, RoomController.close)

export default router