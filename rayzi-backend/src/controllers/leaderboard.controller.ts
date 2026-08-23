import { Response } from 'express'
import { supabase } from '../config/database'
import { success, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

const PROFILE_JOIN = `id, username, display_name, avatar_url, is_verified, role, equipped_frame_id, equipped_badge_id, name_effect, equipped_frame:shop_items!profiles_equipped_frame_id_fkey(id, tier)`

export class LeaderboardController {
  static async get(req: AuthenticatedRequest, res: Response) {
    try {
      const type = req.query.type === 'hosts' ? 'hosts' : 'gifters'
      const period = ['daily', 'weekly', 'monthly', 'all'].includes(req.query.period as string)
        ? (req.query.period as string) : 'daily'
      const rewardable = req.query.rewardable === 'true'

      const { data, error: rpcError } = await supabase.rpc('get_leaderboard', {
        p_type: type, p_period: period, p_rewardable: rewardable,
      })
      if (rpcError) return error(res, 400, rpcError.message)

      const rows = data ?? []
      if (rows.length === 0) return success(res, [], undefined, { type, period, rewardable })

      // Join display info for ranked users.
      const ids = rows.map((r: any) => r.user_id).filter(Boolean)
      const { data: profiles } = await supabase.from('profiles').select(PROFILE_JOIN).in('id', ids)
      const byId = new Map((profiles ?? []).map((p: any) => [p.id, p]))

      return success(res, rows.map((r: any, i: number) => ({
        rank: r.rank ?? i + 1,
        score: r.score ?? 0,
        user: byId.get(r.user_id) ?? null,
      })), undefined, { type, period, rewardable })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
