import { Response } from 'express'
import { supabase } from '../config/database'
import { success, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

// Whitelist — never pass raw req.body to a service-role update, otherwise
// users could grant themselves coins/diamonds/verified/banned flags.
const EDITABLE_PROFILE_FIELDS = ['display_name', 'bio', 'avatar_url'] as const

export class UserController {
  static async getProfile(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const { data: profile } = await supabase
        .from('profiles')
        .select('id, username, display_name, bio, avatar_url, is_verified, coins, created_at, agencies(id, name)')
        .eq('id', id).single()

      if (!profile) return error(res, 404, 'User not found')
      return success(res, profile)
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async updateProfile(req: AuthenticatedRequest, res: Response) {
    try {
      const updates: Record<string, unknown> = {}
      for (const field of EDITABLE_PROFILE_FIELDS) {
        if (req.body[field] !== undefined) updates[field] = req.body[field]
      }
      if (Object.keys(updates).length === 0) {
        return error(res, 400, 'No editable fields provided')
      }

      const { data, error: updateError } = await supabase
        .from('profiles')
        .update(updates)
        .eq('id', req.user!.id)
        .select().single()

      if (updateError) return error(res, 400, updateError.message)
      return success(res, data, 'Profile updated')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async follow(req: AuthenticatedRequest, res: Response) {
    try {
      const { userId } = req.body
      if (userId === req.user!.id) return error(res, 400, 'Cannot follow yourself')

      const { error: dbError } = await supabase.from('follows').insert({
        follower_id: req.user!.id, following_id: userId
      })

      if (dbError) return error(res, 400, dbError.message)
      return success(res, null, 'Followed successfully')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async unfollow(req: AuthenticatedRequest, res: Response) {
    try {
      const { userId } = req.body
      const { error: dbError } = await supabase.from('follows')
        .delete()
        .eq('follower_id', req.user!.id)
        .eq('following_id', userId)

      if (dbError) return error(res, 400, dbError.message)
      return success(res, null, 'Unfollowed successfully')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getFollowers(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const { page = 1, limit = 20 } = req.query
      const { data, count } = await supabase
        .from('follows')
        .select('profiles!follows_follower_id_fkey(*)', { count: 'exact' })
        .eq('following_id', id)
        .range((+page - 1) * +limit, +page * +limit - 1)

      return success(res, data, undefined, { page: +page, limit: +limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getFollowing(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const { page = 1, limit = 20 } = req.query
      const { data, count } = await supabase
        .from('follows')
        .select('profiles!follows_following_id_fkey(*)', { count: 'exact' })
        .eq('follower_id', id)
        .range((+page - 1) * +limit, +page * +limit - 1)

      return success(res, data, undefined, { page: +page, limit: +limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async search(req: AuthenticatedRequest, res: Response) {
    try {
      const raw = typeof req.query.q === 'string' ? req.query.q.trim() : ''
      if (!raw) return error(res, 400, 'Query required')
      if (raw.length > 50) return error(res, 400, 'Query too long')

      // Escape PostgREST filter operators so user input cannot inject
      // additional `.or()` clauses (commas/parens are operator syntax).
      const q = raw.replace(/[,()]/g, ' ').replace(/\s+/g, ' ').trim()
      if (!q) return error(res, 400, 'Query required')

      const { data } = await supabase
        .from('profiles')
        .select('id, username, display_name, avatar_url, is_verified')
        .or(`username.ilike.%${q}%,display_name.ilike.%${q}%`)
        .limit(20)

      return success(res, data)
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getLeaderboard(req: AuthenticatedRequest, res: Response) {
    try {
      const { period = 'daily', category = 'streamer' } = req.query
      const { data } = await supabase
        .from('leaderboards')
        .select('*, profiles(username, display_name, avatar_url)')
        .eq('period', period)
        .eq('category', category)
        .eq('date', new Date().toISOString().split('T')[0])
        .order('rank', { ascending: true })
        .limit(100)

      return success(res, data)
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}