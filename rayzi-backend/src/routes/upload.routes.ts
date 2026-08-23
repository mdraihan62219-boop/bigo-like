import { Router } from 'express'
import { UploadController } from '../controllers/upload.controller'
import { authenticate } from '../middleware/auth'

const router = Router()

// Larger body allowance for multipart; file size itself is capped by multer.
router.post('/', authenticate, UploadController.handler)

export default router
