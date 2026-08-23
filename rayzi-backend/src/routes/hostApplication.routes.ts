import { Router } from 'express'
import { HostApplicationController } from '../controllers/hostApplication.controller'
import { authenticate } from '../middleware/auth'

const router = Router()
router.use(authenticate)

router.post('/', HostApplicationController.apply)
router.get('/me', HostApplicationController.mine)

export default router
