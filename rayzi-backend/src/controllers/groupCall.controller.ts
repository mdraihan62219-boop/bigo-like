import { Response } from 'express'
import { supabase } from '../config/database'
import { AgoraService, AgoraNotConfiguredError } from '../services/agora.service'
import { success, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

export class GroupCallController {
  static async create(req: AuthenticatedRequest, res: Response) {
    try {
      const { title, description, category, max_seats, is_private, password } = req.body
      if (typeof title !== 'string' || !title.trim()) {
        return error(res, 400, 'Title is required')
      }
      const seats = typeof max_seats === 'number' && max_seats > 0 && max_seats <= 12 ? max_seats : 9

      const { data, error: rpcError } = await supabase.rpc('create_group_call_room', {
        p_title: title.trim(),
        p_description: description || '',
        p_category: category || 'general',
        p_max_seats: seats,
        p_is_private: !!is_private,
        p_password: password || null,
      })

      if (rpcError) return error(res, 400, rpcError.message)
      return success(res, data, 'Group call room created')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async list(req: AuthenticatedRequest, res: Response) {
    try {
      const { category } = req.query
      let query = supabase
        .from('group_call_rooms')
        .select('*, profiles!group_call_rooms_host_id_fkey(id, username, display_name, avatar_url, is_verified)')
        .eq('status', 'active')
        .order('created_at', { ascending: false })
        .limit(50)

      if (typeof category === 'string' && category) {
        query = query.eq('category', category)
      }

      const { data, error: dbError } = await query
      if (dbError) return error(res, 400, dbError.message)

      const rooms = await Promise.all(
        (data ?? []).map(async (room) => {
          const { data: seats } = await supabase
            .from('group_call_seats')
            .select('seat_index, user_id, role, is_muted, video_enabled, profiles(id, username, display_name, avatar_url, is_verified)')
            .eq('room_id', room.id)
            .order('seat_index')

          return { ...room, seats: seats ?? [] }
        })
      )

      return success(res, rooms)
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getById(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const { data: room, error: dbError } = await supabase
        .from('group_call_rooms')
        .select('*, profiles!group_call_rooms_host_id_fkey(id, username, display_name, avatar_url, is_verified)')
        .eq('id', id)
        .single()

      if (dbError || !room) return error(res, 404, 'Room not found')

      const { data: seats } = await supabase
        .from('group_call_seats')
        .select('seat_index, user_id, role, is_muted, video_enabled, profiles(id, username, display_name, avatar_url, is_verified)')
        .eq('room_id', id)
        .order('seat_index')

      return success(res, { ...room, seats: seats ?? [] })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getToken(req: AuthenticatedRequest, res: Response) {
    try {
      const { roomId } = req.params
      const { data: room } = await supabase
        .from('group_call_rooms')
        .select('id, host_id, channel_name, status, is_private, password')
        .eq('id', roomId)
        .single()

      if (!room) return error(res, 404, 'Room not found')
      if (room.status !== 'active') return error(res, 400, 'Room is not active')

      const { data: seat } = await supabase
        .from('group_call_seats')
        .select('role')
        .eq('room_id', roomId)
        .eq('user_id', req.user!.id)
        .maybeSingle()

      const isHost = room.host_id === req.user!.id
      const canPublish = isHost || seat?.role === 'host' || seat?.role === 'co_host'

      const uid = parseInt(req.user!.id.replace(/-/g, '').slice(0, 8), 16)
      let token: string
      try {
        token = AgoraService.generateToken(room.channel_name, uid, canPublish ? 'host' : 'audience')
      } catch (agoraErr) {
        if (agoraErr instanceof AgoraNotConfiguredError) {
          return error(res, 503, 'Agora not configured')
        }
        throw agoraErr
      }

      return success(res, {
        token,
        channel_name: room.channel_name,
        uid,
        role: canPublish ? 'publisher' : 'audience',
        is_host: isHost,
      })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async joinSeat(req: AuthenticatedRequest, res: Response) {
    try {
      const { roomId } = req.params
      const { seat_index } = req.body
      if (typeof seat_index !== 'number' || seat_index < 0 || seat_index >= 12) {
        return error(res, 400, 'seat_index must be 0-11')
      }

      const { data, error: rpcError } = await supabase.rpc('join_group_call_seat', {
        p_room_id: roomId,
        p_seat_index: seat_index,
      })

      if (rpcError) return error(res, 400, rpcError.message)
      return success(res, data, 'Joined seat')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async leaveSeat(req: AuthenticatedRequest, res: Response) {
    try {
      const { roomId } = req.params
      const { error: rpcError } = await supabase.rpc('leave_group_call_seat', {
        p_room_id: roomId,
      })

      if (rpcError) return error(res, 400, rpcError.message)
      return success(res, null, 'Left seat')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async kickSeat(req: AuthenticatedRequest, res: Response) {
    try {
      const { roomId, userId } = req.params

      const { error: rpcError } = await supabase.rpc('kick_group_call_seat', {
        p_room_id: roomId,
        p_user_id: userId,
      })

      if (rpcError) return error(res, 400, rpcError.message)
      return success(res, null, 'User kicked')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async swapHost(req: AuthenticatedRequest, res: Response) {
    try {
      const { roomId, userId } = req.params

      const { error: rpcError } = await supabase.rpc('swap_group_call_host', {
        p_room_id: roomId,
        p_new_host_id: userId,
      })

      if (rpcError) return error(res, 400, rpcError.message)
      return success(res, null, 'Host swapped')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async toggleSeat(req: AuthenticatedRequest, res: Response) {
    try {
      const { roomId, userId } = req.params
      const { field, value } = req.body
      if (field !== 'is_muted' && field !== 'video_enabled') {
        return error(res, 400, 'field must be is_muted or video_enabled')
      }

      const { error: rpcError } = await supabase.rpc('toggle_group_call_seat', {
        p_room_id: roomId,
        p_user_id: userId,
        p_field: field,
        p_value: !!value,
      })

      if (rpcError) return error(res, 400, rpcError.message)
      return success(res, null, 'Seat toggled')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async grantCoHost(req: AuthenticatedRequest, res: Response) {
    try {
      const { roomId, userId } = req.params
      const { grant } = req.body

      const { error: rpcError } = await supabase.rpc('grant_group_call_co_host', {
        p_room_id: roomId,
        p_user_id: userId,
        p_grant: grant !== false,
      })

      if (rpcError) return error(res, 400, rpcError.message)
      return success(res, null, grant !== false ? 'Co-host granted' : 'Co-host revoked')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async end(req: AuthenticatedRequest, res: Response) {
    try {
      const { roomId } = req.params
      const { error: rpcError } = await supabase.rpc('end_group_call', {
        p_room_id: roomId,
      })

      if (rpcError) return error(res, 400, rpcError.message)
      return success(res, null, 'Group call ended')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
