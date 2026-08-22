import { Response } from 'express'
import { supabase } from '../config/database'
import { success, error } from '../utils/response'
import { pageParam, limitParam } from '../utils/pagination'
import { AuthenticatedRequest } from '../types'

const escapePostgrest = (input: string): string =>
  input.replace(/[,()]/g, ' ').replace(/\s+/g, ' ').trim()

export class AdminController {
  static async getStats(req: AuthenticatedRequest, res: Response) {
    try {
      const { count: users } = await supabase.from('profiles').select('*', { count: 'exact', head: true })
      const { count: streams } = await supabase.from('streams').select('*', { count: 'exact', head: true })
      const { count: liveStreams } = await supabase.from('streams').select('*', { count: 'exact', head: true }).eq('status', 'live')
      const { count: posts } = await supabase.from('posts').select('*', { count: 'exact', head: true })
      const { count: reports } = await supabase.from('reports').select('*', { count: 'exact', head: true }).eq('status', 'pending')
      const { data: revenue } = await supabase.from('wallet_transactions')
        .select('amount').eq('type', 'purchase').eq('currency', 'coins')

      const totalRevenue = revenue?.reduce((sum, r) => sum + r.amount, 0) || 0

      return success(res, {
        users: users || 0,
        streams: streams || 0,
        liveStreams: liveStreams || 0,
        posts: posts || 0,
        pendingReports: reports || 0,
        totalRevenue
      })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getUsers(req: AuthenticatedRequest, res: Response) {
    try {
      const page = pageParam(req.query.page)
      const limit = limitParam(req.query.limit)
      let query = supabase.from('profiles').select('*', { count: 'exact' })

      const search = typeof req.query.search === 'string' ? escapePostgrest(req.query.search.slice(0, 50)) : ''
      if (search) query = query.or(`username.ilike.%${search}%,display_name.ilike.%${search}%`)
      if (req.query.is_banned !== undefined) query = query.eq('is_banned', req.query.is_banned === 'true')

      const { data, count } = await query
        .order('created_at', { ascending: false })
        .range((page - 1) * limit, page * limit - 1)

      return success(res, data, undefined, { page, limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async banUser(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      if (!/^[0-9a-f-]{36}$/i.test(id)) return error(res, 400, 'Invalid user id')
      const reason = typeof req.body.reason === 'string' ? req.body.reason.slice(0, 500) : null

      // Guard rail: admins must not be bannable through the API.
      const { data: target } = await supabase.from('profiles').select('role').eq('id', id).single()
      if (target?.role === 'admin') return error(res, 403, 'Cannot ban an admin')

      const until = typeof req.body.until === 'string' ? req.body.until : null
      const { error: dbError } = await supabase.from('profiles').update({
        is_banned: true, ban_reason: reason, ban_until: until
      }).eq('id', id)

      if (dbError) return error(res, 400, dbError.message)
      return success(res, null, 'User banned')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async unbanUser(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      if (!/^[0-9a-f-]{36}$/i.test(id)) return error(res, 400, 'Invalid user id')

      const { error: dbError } = await supabase.from('profiles').update({
        is_banned: false, ban_reason: null, ban_until: null
      }).eq('id', id)

      if (dbError) return error(res, 400, dbError.message)
      return success(res, null, 'User unbanned')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  // --- Streams ---------------------------------------------------------------

  static async getStreams(req: AuthenticatedRequest, res: Response) {
    try {
      const page = pageParam(req.query.page)
      const limit = limitParam(req.query.limit)
      const status = typeof req.query.status === 'string' ? req.query.status : ''

      let query = supabase.from('streams')
        .select('id, title, status, category, is_private, started_at, current_viewers, likes, profiles!streams_host_id_fkey(username, display_name, avatar_url)', { count: 'exact' })

      if (status) query = query.eq('status', status)

      const { data, count } = await query
        .order('started_at', { ascending: false })
        .range((page - 1) * limit, page * limit - 1)

      return success(res, data, undefined, { page, limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async banStream(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      if (!/^[0-9a-f-]{36}$/i.test(id)) return error(res, 400, 'Invalid stream id')

      const { error: dbError } = await supabase.from('streams')
        .update({ status: 'banned', ended_at: new Date().toISOString() })
        .eq('id', id)

      if (dbError) return error(res, 400, dbError.message)
      return success(res, null, 'Stream banned')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  // --- Reports ---------------------------------------------------------------

  static async getReports(req: AuthenticatedRequest, res: Response) {
    try {
      const page = pageParam(req.query.page)
      const limit = limitParam(req.query.limit)
      const status = typeof req.query.status === 'string' ? req.query.status : 'pending'
      const allowedStatuses = ['pending', 'reviewing', 'resolved', 'dismissed']
      if (status && !allowedStatuses.includes(status)) {
        return error(res, 400, `status must be one of: ${allowedStatuses.join(', ')}`)
      }

      let query = supabase.from('reports')
        .select('*, reporter:profiles!reports_reporter_id_fkey(id, username, display_name), reported:profiles!reports_reported_id_fkey(id, username, display_name)', { count: 'exact' })

      if (status) query = query.eq('status', status)

      const { data, count } = await query
        .order('created_at', { ascending: false })
        .range((page - 1) * limit, page * limit - 1)

      return success(res, data, undefined, { page, limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async resolveReport(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      if (!/^[0-9a-f-]{36}$/i.test(id)) return error(res, 400, 'Invalid report id')

      const allowedStatuses = ['reviewing', 'resolved', 'dismissed']
      if (!allowedStatuses.includes(req.body.status)) {
        return error(res, 400, `status must be one of: ${allowedStatuses.join(', ')}`)
      }
      const notes = typeof req.body.admin_notes === 'string' ? req.body.admin_notes.slice(0, 1000) : null

      const { error: dbError } = await supabase.from('reports').update({
        status: req.body.status, admin_notes: notes, resolved_at: new Date().toISOString()
      }).eq('id', id)

      if (dbError) return error(res, 400, dbError.message)
      return success(res, null, 'Report resolved')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  // --- Gifts -----------------------------------------------------------------

  static async getGifts(_req: AuthenticatedRequest, res: Response) {
    try {
      const { data } = await supabase.from('gifts').select('*').order('sort_order')
      return success(res, data)
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async createGift(req: AuthenticatedRequest, res: Response) {
    try {
      const { name, description, image_url, animation_url, price_coins, diamond_value, category, is_limited } = req.body

      if (typeof name !== 'string' || !name.trim()) return error(res, 400, 'Gift name is required')
      const price = Number(price_coins ?? 0)
      const diamonds = Number(diamond_value ?? 0)
      if (!Number.isInteger(price) || price < 0) return error(res, 400, 'price_coins must be a non-negative integer')
      if (!Number.isInteger(diamonds) || diamonds < 0) return error(res, 400, 'diamond_value must be a non-negative integer')

      const { data, error: insertError } = await supabase.from('gifts').insert({
        name, description, image_url, animation_url,
        price_coins: price, diamond_value: diamonds,
        category, is_limited
      }).select().single()

      if (insertError) return error(res, 400, insertError.message)
      return success(res, data, 'Gift created')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async updateGift(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      if (!/^[0-9a-f-]{36}$/i.test(id)) return error(res, 400, 'Invalid gift id')

      // Whitelist editable fields — never forward raw req.body.
      const EDITABLE_GIFT_FIELDS = ['name', 'description', 'image_url', 'animation_url', 'price_coins', 'diamond_value', 'category', 'is_active', 'is_limited', 'sort_order'] as const
      const updates: Record<string, unknown> = {}
      for (const field of EDITABLE_GIFT_FIELDS) {
        if (req.body[field] !== undefined) updates[field] = req.body[field]
      }
      if (Object.keys(updates).length === 0) return error(res, 400, 'No editable fields provided')

      const { data, error: updateError } = await supabase.from('gifts')
        .update(updates).eq('id', id).select().single()

      if (updateError) return error(res, 400, updateError.message)
      return success(res, data, 'Gift updated')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async deleteGift(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      if (!/^[0-9a-f-]{36}$/i.test(id)) return error(res, 400, 'Invalid gift id')
      const { error: dbError } = await supabase.from('gifts').delete().eq('id', id)
      if (dbError) return error(res, 400, dbError.message)
      return success(res, null, 'Gift deleted')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getCoinPackages(_req: AuthenticatedRequest, res: Response) {
    try {
      const { data } = await supabase.from('coin_packages').select('*').order('coins')
      return success(res, data)
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async createCoinPackage(req: AuthenticatedRequest, res: Response) {
    try {
      const { coins, price } = req.body
      const c = Number(coins)
      const p = Number(price)
      if (!Number.isInteger(c) || c <= 0) return error(res, 400, 'coins must be a positive integer')
      if (!(typeof p === 'number' && p > 0)) return error(res, 400, 'price must be a positive number')

      const { data, error: insertError } = await supabase.from('coin_packages')
        .insert({ ...req.body, coins: c, price: p }).select().single()
      if (insertError) return error(res, 400, insertError.message)
      return success(res, data, 'Package created')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  // --- Withdrawals (wallet_transactions type='withdrawal') --------------------

  static async getWithdrawals(req: AuthenticatedRequest, res: Response) {
    try {
      const page = pageParam(req.query.page)
      const limit = limitParam(req.query.limit)
      const status = typeof req.query.status === 'string' ? req.query.status : 'pending'
      const allowed = ['pending', 'completed', 'failed']
      if (status && !allowed.includes(status)) {
        return error(res, 400, `status must be one of: ${allowed.join(', ')}`)
      }

      let query = supabase.from('wallet_transactions')
        .select('*, profiles!wallet_transactions_user_id_fkey(id, username, display_name)', { count: 'exact' })
        .eq('type', 'withdrawal')

      if (status) query = query.eq('status', status)

      const { data, count } = await query
        .order('created_at', { ascending: false })
        .range((page - 1) * limit, page * limit - 1)

      return success(res, data, undefined, { page, limit, total: count || 0 })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async approveWithdrawal(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      if (!/^[0-9a-f-]{36}$/i.test(id)) return error(res, 400, 'Invalid withdrawal id')

      const { data: tx } = await supabase.from('wallet_transactions')
        .select('user_id, amount, currency, status')
        .eq('id', id).eq('type', 'withdrawal').single()

      if (!tx) return error(res, 404, 'Withdrawal not found')
      if (tx.currency !== 'diamonds') return error(res, 400, 'Only diamond withdrawals can be approved')
      if (tx.status !== 'pending') return error(res, 409, `Withdrawal already ${tx.status}`)

      const { error: dbError } = await supabase.from('wallet_transactions')
        .update({ status: 'completed' })
        .eq('id', id).eq('status', 'pending') // conditional: idempotency guard

      if (dbError) return error(res, 400, dbError.message)
      return success(res, null, 'Withdrawal approved')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async rejectWithdrawal(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      if (!/^[0-9a-f-]{36}$/i.test(id)) return error(res, 400, 'Invalid withdrawal id')

      const { data: tx } = await supabase.from('wallet_transactions')
        .select('user_id, amount, currency, status')
        .eq('id', id).eq('type', 'withdrawal').single()

      if (!tx) return error(res, 404, 'Withdrawal not found')
      if (tx.currency !== 'diamonds') return error(res, 400, 'Only diamond withdrawals can be rejected')
      if (tx.status !== 'pending') return error(res, 409, `Withdrawal already ${tx.status}`)

      // Refund the diamonds that were deducted when the withdrawal was requested.
      const refundAmount = Math.abs(tx.amount)
      const { error: refundError } = await supabase.rpc('add_diamonds', {
        p_user_id: tx.user_id, p_amount: refundAmount
      })
      if (refundError) return error(res, 500, `Refund failed: ${refundError.message}`)

      const { error: dbError } = await supabase.from('wallet_transactions')
        .update({ status: 'failed' })
        .eq('id', id).eq('status', 'pending')

      if (dbError) return error(res, 400, dbError.message)
      return success(res, null, 'Withdrawal rejected and diamonds refunded')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}