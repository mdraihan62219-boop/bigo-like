import { Router } from 'express'
import { AnnouncementController } from '../controllers/announcement.controller'
import { authenticate, requireAdmin } from '../middleware/auth'

const router = Router()

// Public: get active announcements
router.get('/active', AnnouncementController.getActiveAnnouncements)

// Admin CRUD
router.get('/', authenticate, requireAdmin, AnnouncementController.list)
router.post('/', authenticate, requireAdmin, AnnouncementController.create)
router.put('/:id', authenticate, requireAdmin, AnnouncementController.update)
router.delete('/:id', authenticate, requireAdmin, AnnouncementController.remove)

export default router
