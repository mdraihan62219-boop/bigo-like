import { Response } from 'express'
import { supabase } from '../config/database'
import { success, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

export class NotificationController {
  static async list(req: AuthenticatedRequest, res: Response) {
    try {
      const { page = 1, limit = 20, is_read } = req.query
      let query = supabase.from('notifications')
        .select('*', { count: 'exact' })
        .eq('user_id', req.user!.id)

      if (is_read !== undefined) query = query.eq('is_read', is_read === 'true')

      const { data, count } = await query
        .order('created_at', { ascending: false })
        .range((+page - 1) * +limit, +page * +limit - 1)

      return success(res, data, undefined, { page: +page, limit: +limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async markRead(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const { error: dbError } = await supabase.from('notifications')
        .update({ is_read: true })
        .eq('id', id)
        .eq('user_id', req.user!.id)

      if (dbError) return error(res, 400, dbError.message)
      return success(res, null, 'Marked as read')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async markAllRead(req: AuthenticatedRequest, res: Response) {
    try {
      const { error: dbError } = await supabase.from('notifications')
        .update({ is_read: true })
        .eq('user_id', req.user!.id)
        .eq('is_read', false)

      if (dbError) return error(res, 400, dbError.message)
      return success(res, null, 'All marked as read')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async registerPushToken(req: AuthenticatedRequest, res: Response) {
    try {
      const { token, platform } = req.body
      const { error: dbError } = await supabase.from('push_tokens').upsert({
        user_id: req.user!.id, token, platform
      }, { onConflict: 'user_id,token' })

      if (dbError) return error(res, 400, dbError.message)
      return success(res, null, 'Token registered')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}