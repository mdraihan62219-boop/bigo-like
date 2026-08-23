import { Router } from 'express'
import { ResellerController } from '../controllers/reseller.controller'
import { authenticate } from '../middleware/auth'

const router = Router()
router.use(authenticate)

router.post('/recharge-request', ResellerController.createRequest)
router.get('/my-requests', ResellerController.myRequests)

export default router
