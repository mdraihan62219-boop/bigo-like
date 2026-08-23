import { Router } from 'express'
import { AdminController } from '../controllers/admin.controller'
import { AdminExpansionController } from '../controllers/adminExpansion.controller'
import { authenticate, requireAdmin } from '../middleware/auth'

const router = Router()

router.use(authenticate, requireAdmin)

router.get('/stats', AdminController.getStats)
router.get('/users', AdminController.getUsers)
router.post('/users/:id/ban', AdminController.banUser)
router.post('/users/:id/unban', AdminController.unbanUser)
router.get('/streams', AdminController.getStreams)
router.post('/streams/:id/ban', AdminController.banStream)
router.get('/reports', AdminController.getReports)
router.post('/reports/:id/resolve', AdminController.resolveReport)
router.get('/withdrawals', AdminController.getWithdrawals)
router.post('/withdrawals/:id/approve', AdminController.approveWithdrawal)
router.post('/withdrawals/:id/reject', AdminController.rejectWithdrawal)
router.get('/gifts', AdminController.getGifts)
router.post('/gifts', AdminController.createGift)
router.put('/gifts/:id', AdminController.updateGift)
router.delete('/gifts/:id', AdminController.deleteGift)
router.get('/coin-packages', AdminController.getCoinPackages)
router.post('/coin-packages', AdminController.createCoinPackage)

// ---- v2 expansion: shop / reseller / host apps / PK ----
router.get('/shop/items', AdminExpansionController.shopList)
router.post('/shop/items', AdminExpansionController.shopCreate)
router.put('/shop/items/:id', AdminExpansionController.shopUpdate)
router.delete('/shop/items/:id', AdminExpansionController.shopDelete)

router.get('/reseller/agents', AdminExpansionController.resellerAgents)
router.post('/reseller/agents', AdminExpansionController.resellerAgents)
router.get('/reseller/requests', AdminExpansionController.resellerRequests)
router.post('/reseller/requests/:id/approve', AdminExpansionController.resellerApprove)
router.post('/reseller/requests/:id/reject', AdminExpansionController.resellerReject)

router.get('/host-applications', AdminExpansionController.hostApplications)
router.post('/host-applications/:id/approve', AdminExpansionController.hostApplicationDecide)
router.post('/host-applications/:id/reject', AdminExpansionController.hostApplicationDecide)

router.post('/pk/dragon-stages', AdminExpansionController.pkDragonStages)

export default router