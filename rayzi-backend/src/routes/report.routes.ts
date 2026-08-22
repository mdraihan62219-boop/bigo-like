import { Router } from 'express'
import { ReportController } from '../controllers/report.controller'
import { authenticate } from '../middleware/auth'

const router = Router()

router.post('/', authenticate, ReportController.create)
router.get('/mine', authenticate, ReportController.getMyReports)

export default router