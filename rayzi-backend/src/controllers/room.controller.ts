import { Response } from 'express'
import bcrypt from 'bcryptjs'
import { supabase } from '../config/database'
import { AgoraService, AgoraNotConfiguredError } from '../services/agora.service'
import { success, error } from '../utils/response'
import { pageParam, limitParam } from '../utils/pagination'
import { AuthenticatedRequest } from '../types'

const BCRYPT_ROUNDS = 10

/** Strips secrets that must never leave the server. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function sanitizeRoom<T extends Record<string, any>>(row: T | null) {
  if (!row) return row
  const { password: _password, ...safeRow } = row
  return safeRow
}

const isPositiveInt = (v: unknown): v is number =>
  typeof v === 'number' && Number.isInteger(v) && v > 0

export class RoomController {
  static async create(req: AuthenticatedRequest, res: Response) {
    try {
      const { title, description, category, max_participants, is_private, password } = req.body
      if (typeof title !== 'string' || !title.trim()) {
        return error(res, 400, 'Title is required')
      }
      if (max_participants !== undefined && !isPositiveInt(max_participants)) {
        return error(res, 400, 'max_participants must be a positive integer')
      }
      if (is_private && (typeof password !== 'string' || password.length < 4)) {
        return error(res, 400, 'Private rooms require a password of at least 4 characters')
      }

      // C5 fix: store a hash, never the plaintext.
      const hashedPassword = is_private && password
        ? await bcrypt.hash(password, BCRYPT_ROUNDS)
        : null

      const { data, error: insertError } = await supabase.from('rooms').insert({
        host_id: req.user!.id, title, description, category,
        max_participants, is_private, password: hashedPassword
      }).select().single()

      if (insertError) return error(res, 400, insertError.message)
      return success(res, sanitizeRoom(data), 'Room created')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  /**
   * Agora voice-channel token for an audio room. Mirrors the stream token
   * endpoint (same service, same uid derivation) — no second token path.
   * Channel name is derived deterministically (`room_<id>`) because the
   * rooms table has no channel column; host and participants therefore
   * always land in the same channel.
   * Role mapping: room host / 'speaker' participants publish audio;
   * 'listener' participants join as audience.
   */
  static async getToken(req: AuthenticatedRequest, res: Response) {
    try {
      const { roomId } = req.params
      const { data: room } = await supabase
        .from('rooms')
        .select('id, host_id, status, is_private, password')
        .eq('id', roomId).single()
      if (!room) return error(res, 404, 'Room not found')
      if (room.status !== 'active') return error(res, 400, 'Room is not active')

      const { data: participant } = await supabase
        .from('room_participants')
        .select('role')
        .eq('room_id', roomId)
        .eq('user_id', req.user!.id)
        .maybeSingle()

      const isHost = room.host_id === req.user!.id
      const participantRole = (participant?.role as string | undefined) ?? null

      // Private rooms require the password before a token is issued to
      // anyone but the host (same rule as streams).
      if (room.is_private && !isHost) {
        const supplied = typeof req.body?.password === 'string' && req.body.password
          ? req.body.password
          : typeof req.query.password === 'string' ? req.query.password : ''
        if (!supplied || !room.password || !(await bcrypt.compare(supplied, room.password))) {
          return error(res, 403, 'Room password required or incorrect')
        }
      }

      const canPublish = isHost || participantRole === 'host' || participantRole === 'speaker'
      const channelName = `room_${roomId}`
      const uid = parseInt(req.user!.id.replace(/-/g, '').slice(0, 8), 16)
      let token: string
      try {
        token = AgoraService.generateToken(channelName, uid, canPublish ? 'host' : 'audience')
      } catch (agoraErr) {
        if (agoraErr instanceof AgoraNotConfiguredError) {
          return error(res, 503, 'Agora not configured')
        }
        throw agoraErr
      }

      return success(res, {
        token,
        channel_name: channelName,
        uid,
        role: canPublish ? 'speaker' : 'listener',
        is_host: isHost,
      })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async list(req: AuthenticatedRequest, res: Response) {
    try {
      const page = pageParam(req.query.page)
      const limit = limitParam(req.query.limit)
      const { status = 'active', category } = req.query
      let query = supabase.from('rooms').select('*, profiles!rooms_host_id_fkey(*)', { count: 'exact' })

      if (status) query = query.eq('status', status)
      if (category) query = query.eq('category', category)

      const { data, count } = await query
        .order('created_at', { ascending: false })
        .range((page - 1) * limit, page * limit - 1)

      return success(
        res,
        (data ?? []).map((row) => sanitizeRoom(row)),
        undefined,
        { page, limit, total: count || 0 }
      )
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getById(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const { data } = await supabase
        .from('rooms')
        .select('*, profiles!rooms_host_id_fkey(*), room_participants(user_id, role, is_muted)')
        .eq('id', id).single()

      if (!data) return error(res, 404, 'Room not found')
      return success(res, sanitizeRoom(data))
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async join(req: AuthenticatedRequest, res: Response) {
    try {
      const { roomId } = req.params
      const supplied = typeof req.body?.password === 'string' ? req.body.password : ''
      const { data: room } = await supabase.from('rooms')
        .select('id, max_participants, is_private, password')
        .eq('id', roomId).single()
      if (!room) return error(res, 404, 'Room not found')

      if (room.is_private) {
        if (!supplied || !room.password || !(await bcrypt.compare(supplied, room.password))) {
          return error(res, 403, 'Room password required or incorrect')
        }
      }

      const { data: participants } = await supabase
        .from('room_participants').select('user_id').eq('room_id', roomId)

      if (participants && participants.length >= room.max_participants) {
        return error(res, 400, 'Room is full')
      }

      const { error: dbError } = await supabase.from('room_participants').upsert({
        room_id: roomId, user_id: req.user!.id, role: 'listener'
      })

      if (dbError) return error(res, 400, dbError.message)
      return success(res, null, 'Joined room')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async leave(req: AuthenticatedRequest, res: Response) {
    try {
      const { roomId } = req.params
      const { error: dbError } = await supabase.from('room_participants')
        .delete()
        .eq('room_id', roomId)
        .eq('user_id', req.user!.id)

      if (dbError) return error(res, 400, dbError.message)
      return success(res, null, 'Left room')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async updateParticipantRole(req: AuthenticatedRequest, res: Response) {
    try {
      const { roomId, userId } = req.params
      const { role, is_muted } = req.body

      const { data: room } = await supabase.from('rooms').select('host_id').eq('id', roomId).single()
      if (!room || room.host_id !== req.user!.id) return error(res, 403, 'Not authorized')

      const allowedRoles = ['listener', 'speaker', 'moderator']
      if (role !== undefined && !allowedRoles.includes(role)) {
        return error(res, 400, `role must be one of: ${allowedRoles.join(', ')}`)
      }

      const updates: Record<string, unknown> = {}
      if (role !== undefined) updates.role = role
      if (is_muted !== undefined) updates.is_muted = Boolean(is_muted)
      if (Object.keys(updates).length === 0) return error(res, 400, 'Nothing to update')

      const { error: dbError } = await supabase.from('room_participants')
        .update(updates)
        .eq('room_id', roomId)
        .eq('user_id', userId)

      if (dbError) return error(res, 400, dbError.message)
      return success(res, null, 'Participant updated')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async close(req: AuthenticatedRequest, res: Response) {
    try {
      const { roomId } = req.params
      const { data: room } = await supabase.from('rooms').select('host_id').eq('id', roomId).single()
      if (!room || room.host_id !== req.user!.id) return error(res, 403, 'Not authorized')

      const { error: dbError } = await supabase.from('rooms')
        .update({ status: 'closed' })
        .eq('id', roomId)

      if (dbError) return error(res, 400, dbError.message)
      return success(res, null, 'Room closed')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
