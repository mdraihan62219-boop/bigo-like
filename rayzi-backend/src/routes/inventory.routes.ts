import { Router } from 'express'
import { ShopController } from '../controllers/shop.controller'
import { authenticate } from '../middleware/auth'

const router = Router()
router.use(authenticate)

router.get('/', ShopController.inventory)
router.post('/:itemId/equip', ShopController.equip)
router.delete('/:itemId/equip', ShopController.equip)

export default router
