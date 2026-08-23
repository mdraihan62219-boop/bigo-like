import { Router } from 'express'
import { PostController } from '../controllers/post.controller'
import { authenticate, optionalAuth } from '../middleware/auth'

const router = Router()

router.get('/', optionalAuth, PostController.list)
router.post('/', authenticate, PostController.create)
router.get('/:id', optionalAuth, PostController.getById)
router.post('/:id/like', authenticate, PostController.like)
router.delete('/:id/like', authenticate, PostController.unlike)
router.post('/:id/comments', authenticate, PostController.comment)
router.get('/:id/comments', authenticate, PostController.getComments)

export default router