import { Router } from 'express'
import authRoutes from './auth.routes'
import userRoutes from './user.routes'
import streamRoutes from './stream.routes'
import giftRoutes from './gift.routes'
import postRoutes from './post.routes'
import walletRoutes from './wallet.routes'
import roomRoutes from './room.routes'
import notificationRoutes from './notification.routes'
import reportRoutes from './report.routes'
import adminRoutes from './admin.routes'

const router = Router()

router.use('/auth', authRoutes)
router.use('/users', userRoutes)
router.use('/streams', streamRoutes)
router.use('/gifts', giftRoutes)
router.use('/posts', postRoutes)
router.use('/wallet', walletRoutes)
router.use('/rooms', roomRoutes)
router.use('/notifications', notificationRoutes)
router.use('/reports', reportRoutes)
router.use('/admin', adminRoutes)

export default router