import { Response } from 'express'
import { supabase } from '../config/database'
import { success, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

export class AnnouncementController {
  static async getActiveAnnouncements(_req: AuthenticatedRequest, res: Response) {
    try {
      const now = new Date().toISOString()
      const { data, error: dbError } = await supabase
        .from('announcements')
        .select('id, message, is_active, starts_at, ends_at')
        .eq('is_active', true)
        .or(`starts_at.is.null,starts_at.lte.${now}`)
        .or(`ends_at.is.null,ends_at.gte.${now}`)
        .order('created_at', { ascending: false })

      if (dbError) return error(res, 400, dbError.message)
      return success(res, data ?? [])
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async list(_req: AuthenticatedRequest, res: Response) {
    try {
      const { data, error: dbError } = await supabase
        .from('announcements')
        .select('*')
        .order('created_at', { ascending: false })

      if (dbError) return error(res, 400, dbError.message)
      return success(res, data ?? [])
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async create(req: AuthenticatedRequest, res: Response) {
    try {
      const { message, is_active, starts_at, ends_at } = req.body
      if (typeof message !== 'string' || !message.trim()) {
        return error(res, 400, 'Message is required')
      }
      const { data, error: dbError } = await supabase
        .from('announcements')
        .insert({ message: message.trim(), is_active, starts_at, ends_at })
        .select()
        .single()

      if (dbError) return error(res, 400, dbError.message)
      return success(res, data, 'Announcement created')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async update(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const { message, is_active, starts_at, ends_at } = req.body
      const patch: Record<string, unknown> = {}
      if (message !== undefined) patch.message = message.trim()
      if (is_active !== undefined) patch.is_active = is_active
      if (starts_at !== undefined) patch.starts_at = starts_at
      if (ends_at !== undefined) patch.ends_at = ends_at
      patch.updated_at = new Date().toISOString()

      const { data, error: dbError } = await supabase
        .from('announcements')
        .update(patch)
        .eq('id', id)
        .select()
        .single()

      if (dbError) return error(res, 400, dbError.message)
      return success(res, data, 'Announcement updated')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async remove(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const { error: dbError } = await supabase
        .from('announcements')
        .delete()
        .eq('id', id)

      if (dbError) return error(res, 400, dbError.message)
      return success(res, null, 'Announcement deleted')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
