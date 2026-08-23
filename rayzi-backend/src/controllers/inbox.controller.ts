import { Response } from 'express'
import { InboxService } from '../services/inbox.service'
import { success, created, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

/** Stable numeric uid for Agora from a string id. */
function hashId(id: string): number {
  let h = 0
  for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) | 0
  return h % 1000000
}

export class InboxController {
  /** Logs a call attempt and returns an Agora token for a 1-to-1 channel. */
  static async startCall(req: AuthenticatedRequest, res: Response) {
    try {
      const conv = await InboxService.getConversation(req.user!.id, req.params.id)
      if (!conv) return error(res, 404, 'Conversation not found')
      const callType = req.body?.call_type === 'video' ? 'video' : 'audio'
      const { AgoraService, AgoraNotConfiguredError } = await import('../services/agora.service')
      // Channel name is deterministic so both sides join the same room.
      const channel = `inbox_${conv.id}`
      let token: string
      try {
        token = AgoraService.generateToken(channel, Math.abs(hashId(req.user!.id)), 'host')
      } catch (agoraErr) {
        if (agoraErr instanceof AgoraNotConfiguredError) {
          return error(res, 503, 'Agora not configured')
        }
        throw agoraErr
      }
      await InboxService.sendMessage(req.user!.id, conv.id, {
        message_type: 'call_log', call_type: callType,
      })
      req.app.get('io')?.to(`conversation:${conv.id}`).emit('inbox-call-incoming', {
        conversationId: conv.id, callerId: req.user!.id, callType,
      })
      return created(res, { channel, token, call_type: callType }, 'Call started')
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }

  static async endCall(req: AuthenticatedRequest, res: Response) {
    try {
      const conv = await InboxService.getConversation(req.user!.id, req.params.id)
      if (!conv) return error(res, 404, 'Conversation not found')
      const dur = Math.max(0, Number(req.body?.duration_seconds ?? 0))
      await InboxService.sendMessage(req.user!.id, conv.id, {
        message_type: 'call_log', call_type: req.body?.call_type === 'video' ? 'video' : 'audio',
        call_duration_seconds: Number.isInteger(dur) && dur >= 0 ? dur : 0,
      })
      req.app.get('io')?.to(`conversation:${conv.id}`).emit('inbox-call-ended', {
        conversationId: conv.id, durationSeconds: dur,
      })
      return success(res, null, 'Call ended')
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }

  static async conversations(req: AuthenticatedRequest, res: Response) {
    try {
      return success(res, await InboxService.listConversations(req.user!.id))
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async open(req: AuthenticatedRequest, res: Response) {
    try {
      const r = await InboxService.openConversation(req.user!.id, req.params.userId)
      if (!r.ok) return error(res, r.status, r.message)
      return res.status(r.status).json({ success: true, data: r.data })
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }

  static async messages(req: AuthenticatedRequest, res: Response) {
    try {
      const conv = await InboxService.getConversation(req.user!.id, req.params.id)
      if (!conv) return error(res, 404, 'Conversation not found')

      if (req.method === 'POST') {
        const msg = await InboxService.sendMessage(req.user!.id, conv.id, req.body)
        req.app.get('io')?.to(`conversation:${conv.id}`).emit('inbox-message', {
          conversationId: conv.id, message: msg,
        })
        return created(res, msg, 'Sent')
      }
      if (req.method === 'PUT') {
        return success(res, null, await InboxService.markRead(conv.id, req.user!.id))
      }
      const page = Math.max(1, +((req.query.page as string) ?? 1))
      const limit = Math.min(100, Math.max(1, +((req.query.limit as string) ?? 50)))
      return success(res, await InboxService.listMessages(conv.id, page, limit), undefined, { page, limit })
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }
}
