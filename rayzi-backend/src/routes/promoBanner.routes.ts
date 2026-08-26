import { Router } from 'express'
import { PromoBannerController } from '../controllers/promoBanner.controller'
import { authenticate, requireAdmin } from '../middleware/auth'

const router = Router()

// Public: get active promo banners
router.get('/active', PromoBannerController.getActive)

// Admin CRUD
router.get('/', authenticate, requireAdmin, PromoBannerController.list)
router.post('/', authenticate, requireAdmin, PromoBannerController.create)
router.put('/:id', authenticate, requireAdmin, PromoBannerController.update)
router.delete('/:id', authenticate, requireAdmin, PromoBannerController.remove)

export default router
