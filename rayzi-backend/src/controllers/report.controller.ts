import { Response } from 'express'
import { supabase } from '../config/database'
import { success, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

export class ReportController {
  static async create(req: AuthenticatedRequest, res: Response) {
    try {
      const { reported_id, stream_id, post_id, reason, description } = req.body
      const { data, error: insertError } = await supabase.from('reports').insert({
        reporter_id: req.user!.id, reported_id, stream_id, post_id, reason, description
      }).select().single()

      if (insertError) return error(res, 400, insertError.message)
      return success(res, data, 'Report submitted')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getMyReports(req: AuthenticatedRequest, res: Response) {
    try {
      const { page = 1, limit = 20 } = req.query
      const { data, count } = await supabase
        .from('reports')
        .select('*, profiles!reports_reported_id_fkey(username, display_name, avatar_url)', { count: 'exact' })
        .eq('reporter_id', req.user!.id)
        .order('created_at', { ascending: false })
        .range((+page - 1) * +limit, +page * +limit - 1)

      return success(res, data, undefined, { page: +page, limit: +limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}