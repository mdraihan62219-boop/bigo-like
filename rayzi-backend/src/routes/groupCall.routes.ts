import { Router } from 'express'
import { GroupCallController } from '../controllers/groupCall.controller'
import { authenticate, optionalAuth } from '../middleware/auth'

const router = Router()

router.get('/', optionalAuth, GroupCallController.list)
router.post('/', authenticate, GroupCallController.create)
router.get('/:id', optionalAuth, GroupCallController.getById)
router.get('/:roomId/token', authenticate, GroupCallController.getToken)
router.post('/:roomId/join', authenticate, GroupCallController.joinSeat)
router.post('/:roomId/leave', authenticate, GroupCallController.leaveSeat)
router.post('/:roomId/kick/:userId', authenticate, GroupCallController.kickSeat)
router.post('/:roomId/swap-host/:userId', authenticate, GroupCallController.swapHost)
router.post('/:roomId/toggle/:userId', authenticate, GroupCallController.toggleSeat)
router.post('/:roomId/grant-co-host/:userId', authenticate, GroupCallController.grantCoHost)
router.post('/:roomId/end', authenticate, GroupCallController.end)

export default router
