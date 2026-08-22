import { Router } from 'express'
import { UserController } from '../controllers/user.controller'
import { authenticate } from '../middleware/auth'

const router = Router()

router.get('/search', authenticate, UserController.search)
router.get('/leaderboard', authenticate, UserController.getLeaderboard)
router.get('/:id', authenticate, UserController.getProfile)
router.put('/profile', authenticate, UserController.updateProfile)
router.post('/follow', authenticate, UserController.follow)
router.post('/unfollow', authenticate, UserController.unfollow)
router.get('/:id/followers', authenticate, UserController.getFollowers)
router.get('/:id/following', authenticate, UserController.getFollowing)

export default router