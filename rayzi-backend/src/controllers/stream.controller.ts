import { Response } from 'express'
import bcrypt from 'bcryptjs'
import { supabase } from '../config/database'
import { AgoraService } from '../services/agora.service'
import { NotificationService } from '../services/notification.service'
import { success, error } from '../utils/response'
import { pageParam, limitParam } from '../utils/pagination'
import { AuthenticatedRequest } from '../types'

const BCRYPT_ROUNDS = 10

/** Strips secrets that must never leave the server. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function sanitizeStream<T extends Record<string, any>>(row: T | null): Omit<T, 'password' | 'agora_token'> | null {
  if (!row) return row
  const { password: _password, agora_token: _agoraToken, ...safeRow } = row
  return safeRow
}

export class StreamController {
  static async create(req: AuthenticatedRequest, res: Response) {
    try {
      const { title, description, category, is_private, password } = req.body
      if (typeof title !== 'string' || !title.trim()) {
        return error(res, 400, 'Title is required')
      }
      if (is_private && (typeof password !== 'string' || password.length < 4)) {
        return error(res, 400, 'Private streams require a password of at least 4 characters')
      }

      const channelName = AgoraService.generateChannelName(req.user!.id)
      const agoraToken = AgoraService.generateToken(
        channelName,
        parseInt(req.user!.id.replace(/-/g, '').slice(0, 8), 16),
        'host'
      )

      // C5 fix: never persist the plaintext password.
      const hashedPassword = is_private && password
        ? await bcrypt.hash(password, BCRYPT_ROUNDS)
        : null

      const { data, error: insertError } = await supabase.from('streams').insert({
        host_id: req.user!.id, title, description, category,
        channel_name: channelName, agora_token: agoraToken,
        is_private, password: hashedPassword, status: 'live', started_at: new Date().toISOString()
      }).select().single()

      if (insertError) return error(res, 400, insertError.message)

      // Use display identity, not raw email, in follower notifications.
      const { data: profile } = await supabase
        .from('profiles').select('username').eq('id', req.user!.id).single()
      await NotificationService.broadcastToFollowers(
        req.user!.id, 'Stream Started',
        `${profile?.username ?? 'Someone you follow'} is now live!`,
        { stream_id: data.id, channel_name: channelName }
      )

      return success(res, sanitizeStream(data), 'Stream created')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async getToken(req: AuthenticatedRequest, res: Response) {
    try {
      const { streamId } = req.params
      const { data: stream } = await supabase.from('streams')
        .select('id, host_id, channel_name, is_private, password, status')
        .eq('id', streamId).single()
      if (!stream) return error(res, 404, 'Stream not found')

      const isHost = stream.host_id === req.user!.id

      // C5 fix: private streams now actually require the password (hashed
      // compare) before an Agora token is issued to anyone but the host.
      // Accept it from body or query so GET-based clients work too.
      if (stream.is_private && !isHost) {
        const supplied = typeof req.body?.password === 'string' && req.body.password
          ? req.body.password
          : typeof req.query.password === 'string' ? req.query.password : ''
        if (!supplied || !stream.password || !(await bcrypt.compare(supplied, stream.password))) {
          return error(res, 403, 'Stream password required or incorrect')
        }
      }

      const uid = parseInt(req.user!.id.replace(/-/g, '').slice(0, 8), 16)
      const token = AgoraService.generateToken(stream.channel_name, uid, isHost ? 'host' : 'audience')

      return success(res, { token, channel_name: stream.channel_name, is_host: isHost, uid })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async list(req: AuthenticatedRequest, res: Response) {
    try {
      const page = pageParam(req.query.page)
      const limit = limitParam(req.query.limit)
      const { status = 'live', category } = req.query
      let query = supabase.from('streams')
        .select('*, profiles!streams_host_id_fkey(*)', { count: 'exact' })

      if (status) query = query.eq('status', status)
      if (category) query = query.eq('category', category)

      const { data, count } = await query
        .order('started_at', { ascending: false })
        .range((page - 1) * limit, page * limit - 1)

      return success(
        res,
        (data ?? []).map((row) => sanitizeStream(row)),
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
        .from('streams')
        .select('*, profiles!streams_host_id_fkey(*), stream_viewers(user_id, joined_at)')
        .eq('id', id).single()

      if (!data) return error(res, 404, 'Stream not found')
      return success(res, sanitizeStream(data))
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async join(req: AuthenticatedRequest, res: Response) {
    try {
      const { streamId } = req.params
      const { error: dbError } = await supabase.from('stream_viewers').upsert({
        stream_id: streamId, user_id: req.user!.id, joined_at: new Date().toISOString()
      })

      if (dbError) return error(res, 400, dbError.message)
      return success(res, null, 'Joined stream')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async leave(req: AuthenticatedRequest, res: Response) {
    try {
      const { streamId } = req.params
      const { error: dbError } = await supabase.from('stream_viewers')
        .update({ left_at: new Date().toISOString() })
        .eq('stream_id', streamId)
        .eq('user_id', req.user!.id)

      if (dbError) return error(res, 400, dbError.message)
      return success(res, null, 'Left stream')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async end(req: AuthenticatedRequest, res: Response) {
    try {
      const { streamId } = req.params
      const { data: stream } = await supabase.from('streams').select('host_id').eq('id', streamId).single()
      if (!stream || stream.host_id !== req.user!.id) return error(res, 403, 'Not authorized')

      const { error: dbError } = await supabase.from('streams')
        .update({ status: 'ended', ended_at: new Date().toISOString() })
        .eq('id', streamId)

      if (dbError) return error(res, 400, dbError.message)
      return success(res, null, 'Stream ended')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async like(req: AuthenticatedRequest, res: Response) {
    try {
      const { streamId } = req.params
      const { error: rpcError } = await supabase.rpc('increment_stream_likes', { stream_id: streamId })
      if (rpcError) return error(res, 400, rpcError.message)
      return success(res, null, 'Liked')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
