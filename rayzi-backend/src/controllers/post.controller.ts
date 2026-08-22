import { Response } from 'express'
import { supabase } from '../config/database'
import { success, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

export class PostController {
  static async create(req: AuthenticatedRequest, res: Response) {
    try {
      const { content, media_urls, media_type } = req.body
      const { data, error: insertError } = await supabase.from('posts').insert({
        user_id: req.user!.id, content, media_urls, media_type
      }).select().single()

      if (insertError) return error(res, 400, insertError.message)
      return success(res, data, 'Post created')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async list(req: AuthenticatedRequest, res: Response) {
    try {
      const { page = 1, limit = 20 } = req.query
      const { data, count } = await supabase
        .from('posts')
        .select('*, profiles!posts_user_id_fkey(username, display_name, avatar_url)', { count: 'exact' })
        .order('created_at', { ascending: false })
        .range((+page - 1) * +limit, +page * +limit - 1)

      return success(res, data, undefined, { page: +page, limit: +limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getById(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const { data } = await supabase
        .from('posts')
        .select('*, profiles!posts_user_id_fkey(*)')
        .eq('id', id).single()

      if (!data) return error(res, 404, 'Post not found')
      return success(res, data)
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async like(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const { error: dbError } = await supabase.from('post_likes').upsert({
        post_id: id, user_id: req.user!.id
      })
      if (dbError) return error(res, 400, dbError.message)
      return success(res, null, 'Liked')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async unlike(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const { error: dbError } = await supabase.from('post_likes')
        .delete()
        .eq('post_id', id)
        .eq('user_id', req.user!.id)
      if (dbError) return error(res, 400, dbError.message)
      return success(res, null, 'Unliked')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async comment(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const { content, parent_id } = req.body
      const { data, error: insertError } = await supabase.from('post_comments').insert({
        post_id: id, user_id: req.user!.id, content, parent_id
      }).select().single()

      if (insertError) return error(res, 400, insertError.message)
      return success(res, data, 'Comment added')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getComments(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const { page = 1, limit = 50 } = req.query
      const { data, count } = await supabase
        .from('post_comments')
        .select('*, profiles!post_comments_user_id_fkey(username, display_name, avatar_url)', { count: 'exact' })
        .eq('post_id', id)
        .is('parent_id', null)
        .order('created_at', { ascending: false })
        .range((+page - 1) * +limit, +page * +limit - 1)

      return success(res, data, undefined, { page: +page, limit: +limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}