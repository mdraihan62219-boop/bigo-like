import { Router } from 'express'
import { ShopController } from '../controllers/shop.controller'
import { authenticate } from '../middleware/auth'

const router = Router()
router.use(authenticate)

router.get('/items', ShopController.listItems)
router.post('/purchase', ShopController.purchase)

export default router
