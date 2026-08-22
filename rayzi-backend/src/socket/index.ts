import { Server as SocketServer } from 'socket.io'
import { Server } from 'http'
import { supabase } from '../config/database'
import { logger } from '../utils/logger'
import { GiftService } from '../services/gift.service'
import { getAllowedOrigins } from '../config/cors'
import jwt from 'jsonwebtoken'

/** Wraps async socket handlers so a rejection can never crash the process. */
const safe = (handler: (...args: any[]) => Promise<void>) =>
  (...args: any[]) => {
    handler(...args).catch((err) => logger.error(`Socket handler error: ${err?.message || err}`))
  }

export const initSocket = (server: Server) => {
  const io = new SocketServer(server, {
    cors: { origin: getAllowedOrigins(), methods: ['GET', 'POST'], credentials: true }
  })

  io.use(async (socket, next) => {
    try {
      const token = socket.handshake.auth.token
      if (!token) return next(new Error('Authentication required'))

      const decoded = jwt.verify(token, process.env.JWT_SECRET!) as any
      if (!decoded?.id) return next(new Error('Invalid token'))
      socket.data.user = decoded
      next()
    } catch (_err) {
      next(new Error('Invalid token'))
    }
  })

  io.on('connection', (socket) => {
    const userId: string = socket.data.user.id
    logger.info(`User connected: ${userId}`)
    socket.join(`user_${userId}`)

    // Resolve display identity once — broadcasting raw emails to chat rooms
    // was a PII leak.
    let username = 'user'
    void (async () => {
      try {
        const { data } = await supabase.from('profiles').select('username').eq('id', userId).single()
        if (data?.username) username = data.username
      } catch { /* keep fallback */ }
    })()

    socket.on('join-stream', safe(async (streamId: unknown) => {
      if (typeof streamId !== 'string' || !streamId) return
      socket.join(`stream_${streamId}`)

      const { data: messages } = await supabase
        .from('chat_messages')
        .select('*, profiles!chat_messages_user_id_fkey(username, avatar_url)')
        .eq('stream_id', streamId)
        .order('created_at', { ascending: false })
        .limit(50)

      socket.emit('chat-history', messages?.reverse() || [])
      socket.to(`stream_${streamId}`).emit('user-joined', { userId })
    }))

    socket.on('leave-stream', (streamId: unknown) => {
      if (typeof streamId !== 'string' || !streamId) return
      socket.leave(`stream_${streamId}`)
      socket.to(`stream_${streamId}`).emit('user-left', { userId })
    })

    socket.on('chat-message', safe(async (data: unknown) => {
      const payload = data as { streamId?: unknown; message?: unknown }
      const streamId = payload?.streamId
      const message = payload?.message
      if (typeof streamId !== 'string' || typeof message !== 'string') return
      const text = message.trim().slice(0, 500)
      if (!text) return

      // Persist first; only broadcast when the insert actually succeeded so
      // history and live feed can never diverge.
      const { error: insertError } = await supabase.from('chat_messages').insert({
        stream_id: streamId, user_id: userId,
        message_type: 'text', content: text
      })
      if (insertError) throw insertError

      io.to(`stream_${streamId}`).emit('chat-message', {
        userId, username,
        message: text, timestamp: new Date().toISOString()
      })
    }))

    // Economy path: identical rules as POST /gifts/send — coins are actually
    // deducted and a gift_transactions row is recorded before any broadcast.
    socket.on('send-gift', safe(async (data: unknown, ack?: (res: { ok: boolean; error?: string }) => void) => {
      const payload = data as { streamId?: unknown; giftId?: unknown; receiverId?: unknown; quantity?: unknown }
      try {
        const tx = await GiftService.sendGift({
          senderId: userId,
          receiverId: String(payload?.receiverId ?? ''),
          streamId: payload?.streamId === undefined ? null : String(payload.streamId),
          giftId: String(payload?.giftId ?? ''),
          quantity: Number(payload?.quantity ?? 1),
        })

        if (tx === null) {
          ack?.({ ok: false, error: 'Gift not found' })
          return
        }

        io.to(`stream_${payload?.streamId}`).emit('gift-received', {
          senderId: userId,
          receiverId: payload?.receiverId,
          giftId: tx.gift_id,
          quantity: tx.quantity,
          total_coins: tx.total_coins,
          timestamp: new Date().toISOString()
        })
        ack?.({ ok: true })
      } catch (err: any) {
        logger.warn(`send-gift rejected for ${userId}: ${err.message}`)
        ack?.({ ok: false, error: err.message })
      }
    }))

    socket.on('join-room', (roomId: unknown) => {
      if (typeof roomId !== 'string' || !roomId) return
      socket.join(`room_${roomId}`)
      socket.to(`room_${roomId}`).emit('user-joined-room', { userId })
    })

    socket.on('leave-room', (roomId: unknown) => {
      if (typeof roomId !== 'string' || !roomId) return
      socket.leave(`room_${roomId}`)
      socket.to(`room_${roomId}`).emit('user-left-room', { userId })
    })

    socket.on('room-message', (data: unknown) => {
      const payload = data as { roomId?: unknown; message?: unknown }
      if (typeof payload?.roomId !== 'string' || typeof payload?.message !== 'string') return
      const text = payload.message.trim().slice(0, 500)
      if (!text) return
      io.to(`room_${payload.roomId}`).emit('room-message', {
        userId, username, message: text,
        timestamp: new Date().toISOString()
      })
    })

    socket.on('private-message', safe(async (data: unknown) => {
      const payload = data as { to?: unknown; message?: unknown }
      if (typeof payload?.to !== 'string' || typeof payload?.message !== 'string') return
      const text = payload.message.trim().slice(0, 1000)
      if (!text) return

      const { error: insertError } = await supabase.from('private_messages').insert({
        sender_id: userId, receiver_id: payload.to, content: text
      })
      if (insertError) throw insertError

      io.to(`user_${payload.to}`).emit('private-message', {
        from: userId, message: text,
        timestamp: new Date().toISOString()
      })
    }))

    socket.on('disconnect', () => {
      logger.info(`User disconnected: ${userId}`)
    })
  })

  return io
}
