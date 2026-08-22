import { Router } from 'express'
import { WalletController } from '../controllers/wallet.controller'
import { authenticate } from '../middleware/auth'

const router = Router()

router.get('/balance', authenticate, WalletController.getBalance)
router.get('/transactions', authenticate, WalletController.getTransactions)
router.post('/purchase', authenticate, WalletController.purchaseCoins)
router.post('/withdraw', authenticate, WalletController.withdrawDiamonds)

export default router