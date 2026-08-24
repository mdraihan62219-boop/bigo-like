import { Router } from 'express'
import { WalletController } from '../controllers/wallet.controller'
import { authenticate } from '../middleware/auth'

const router = Router()

router.get('/balance', authenticate, WalletController.getBalance)
router.get('/transactions', authenticate, WalletController.getTransactions)
// Audit-grade ledger (wallet_ledger) — own rows only.
router.get('/ledger', authenticate, WalletController.getLedger)
router.post('/purchase', authenticate, WalletController.purchaseCoins)

// Buy coins from a reseller (code-based professional flow)
router.get('/resellers', authenticate, WalletController.listResellers)
router.post('/recharge-by-code', authenticate, WalletController.createRechargeByCode)

// Withdraw (hold / reversal flow)
router.post('/withdraw', authenticate, WalletController.withdrawDiamonds) // legacy-compatible
router.post('/withdrawals', authenticate, WalletController.submitWithdrawal)
router.get('/withdrawals', authenticate, WalletController.myWithdrawals)

export default router
