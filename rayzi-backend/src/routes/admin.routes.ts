import { Router } from 'express'
import { AdminController } from '../controllers/admin.controller'
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

export default router