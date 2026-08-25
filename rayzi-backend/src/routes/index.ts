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
import feedRoutes from './feed.routes'
import shopRoutes from './shop.routes'
import inventoryRoutes from './inventory.routes'
import leaderboardRoutes from './leaderboard.routes'
import resellerRoutes from './reseller.routes'
import hostApplicationRoutes from './hostApplication.routes'
import friendRoutes from './friend.routes'
import profileExtrasRoutes from './profileExtras.routes'
import pkRoutes from './pk.routes'
import inboxRoutes from './inbox.routes'
import uploadRoutes from './upload.routes'
import gamesRoutes from './games.routes'
import groupCallRoutes from './groupCall.routes'

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
router.use('/feed', feedRoutes)
router.use('/shop', shopRoutes)
router.use('/inventory', inventoryRoutes)
router.use('/leaderboard', leaderboardRoutes)
router.use('/reseller', resellerRoutes)
router.use('/host-application', hostApplicationRoutes)
router.use('/friends', friendRoutes)
router.use('/profile', profileExtrasRoutes)
router.use('/pk', pkRoutes)
router.use('/inbox', inboxRoutes)
router.use('/uploads', uploadRoutes)
router.use('/games', gamesRoutes)
router.use('/group-calls', groupCallRoutes)

export default router
