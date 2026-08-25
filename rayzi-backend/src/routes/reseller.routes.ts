import { Router } from 'express'
import { ResellerController } from '../controllers/reseller.controller'
import { authenticate } from '../middleware/auth'

const router = Router()
router.use(authenticate)

router.post('/recharge-request', ResellerController.createRequest)
router.get('/my-requests', ResellerController.myRequests)

// ---- Reseller Dashboard (scoping enforced server-side in the RPCs) ----
router.get('/dashboard', ResellerController.dashboard)
router.post('/requests/:id/approve', ResellerController.approveScoped)
router.post('/requests/:id/reject', ResellerController.rejectScoped)

export default router
