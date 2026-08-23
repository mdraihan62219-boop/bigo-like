import { Router } from 'express'
import { PkController } from '../controllers/pk.controller'
import { authenticate } from '../middleware/auth'

const router = Router()
router.use(authenticate)

router.post('/queue', PkController.queue)
router.delete('/queue', PkController.queue)
router.get('/battles/:id', PkController.state)
router.post('/battles/:id/end', PkController.end)
router.get('/dragon-stages', PkController.dragonStages)

export default router
