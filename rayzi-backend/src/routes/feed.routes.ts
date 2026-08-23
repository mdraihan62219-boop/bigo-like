import { Router } from 'express'
import { FeedController } from '../controllers/feed.controller'
import { authenticate } from '../middleware/auth'

const router = Router()
router.use(authenticate)

router.get('/posts', FeedController.list)
router.post('/posts', FeedController.create)
router.delete('/posts/:id', FeedController.remove)
router.post('/posts/:id/like', FeedController.like)
router.delete('/posts/:id/like', FeedController.unlike)
router.get('/posts/:id/comments', FeedController.comments)
router.post('/posts/:id/comments', FeedController.comments)
router.get('/stories', FeedController.stories)
router.post('/stories', FeedController.stories)
router.post('/stories/:id/view', FeedController.viewStory)

export default router
