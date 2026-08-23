import { Router } from 'express'
import { ProfileExtrasController } from '../controllers/profileExtras.controller'
import { authenticate } from '../middleware/auth'

const router = Router()
router.use(authenticate)

router.get('/summary', ProfileExtrasController.summary)
router.get('/summary/:userId', ProfileExtrasController.summary)
router.put('/theme', (req, res, next) => { res.locals.kind = 'theme'; next() },
  (req, res) => ProfileExtrasController.setEquipped(req as any, res, 'theme'))
router.put('/entry-animation',
  (req, res) => ProfileExtrasController.setEquipped(req as any, res, 'entry-animation'))
router.put('/camera-prefs',
  (req, res) => ProfileExtrasController.setEquipped(req as any, res, 'camera-prefs'))

export default router
