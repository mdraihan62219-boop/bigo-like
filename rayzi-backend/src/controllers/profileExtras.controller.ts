import { Response } from 'express'
import { supabase } from '../config/database'
import { success, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

const SUMMARY_SELECT = `
  id, username, display_name, avatar_url, coins, diamonds, level, experience,
  follower_count, following_count, is_verified, role,
  equipped_frame_id, equipped_badge_id, equipped_theme_id, equipped_entry_animation_id,
  name_effect, camera_prefs,
  equipped_frame:shop_items!profiles_equipped_frame_id_fkey(id, tier, category),
  equipped_badge:shop_items!profiles_equipped_badge_id_fkey(id, tier, category)`

export class ProfileExtrasController {
  static async summary(req: AuthenticatedRequest, res: Response) {
    try {
      const userId = req.params.userId || req.user!.id
      const [profileRes, friendsRes] = await Promise.all([
        supabase.from('profiles').select(SUMMARY_SELECT).eq('id', userId).single(),
        supabase.from('friend_requests').select('*', { count: 'exact', head: true })
          .eq('status', 'accepted').or(`requester_id.eq.${userId},addressee_id.eq.${userId}`),
      ])
      if (profileRes.error) return error(res, 404, profileRes.error.message)
      return success(res, {
        ...profileRes.data,
        friends_count: friendsRes.count ?? 0,
      })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  /** PUT /profile/theme — must own the item (server-side ownership check). */
  static async setEquipped(req: AuthenticatedRequest, res: Response, kind: 'theme' | 'entry-animation' | 'camera-prefs') {
    try {
      const userId = req.user!.id
      if (kind === 'camera-prefs') {
        const prefs = typeof req.body?.filter === 'string' || typeof req.body?.beauty_level === 'number' || typeof req.body?.brightness === 'number'
          ? {
              filter: typeof req.body.filter === 'string' ? req.body.filter.slice(0, 40) : 'natural',
              beauty_level: Number.isFinite(Number(req.body.beauty_level)) ? Math.max(0, Math.min(100, Number(req.body.beauty_level))) : 0,
              brightness: Number.isFinite(Number(req.body.brightness)) ? Math.max(-100, Math.min(100, Number(req.body.brightness))) : 0,
            }
          : null
        if (!prefs) return error(res, 400, 'Invalid camera preferences')
        const { error: dbError } = await supabase.from('profiles').update({ camera_prefs: prefs }).eq('id', userId)
        if (dbError) return error(res, 400, dbError.message)
        return success(res, prefs, 'Camera preferences saved')
      }

      const itemId = typeof req.body.item_id === 'string' ? req.body.item_id : null
      const column = kind === 'theme' ? 'equipped_theme_id' : 'equipped_entry_animation_id'
      const category = kind === 'theme' ? 'theme' : 'entry_animation'

      if (itemId) {
        // Verify the user actually owns this exact item.
        const { data: owned } = await supabase.from('user_inventory')
          .select('id').eq('user_id', userId).eq('item_id', itemId).limit(1)
        if (!owned?.length) return error(res, 403, 'You do not own this item')
        const { data: item } = await supabase.from('shop_items').select('category').eq('id', itemId).single()
        if (!item || item.category !== category) return error(res, 400, 'Item category mismatch')
      }
      const { error: dbError } = await supabase.from('profiles').update({ [column]: itemId }).eq('id', userId)
      if (dbError) return error(res, 400, dbError.message)
      return success(res, { [column]: itemId }, 'Updated')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
