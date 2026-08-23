import { Response } from 'express'
import { supabase } from '../config/database'
import { PkService } from '../services/pk.service'
import { success, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

export class PkController {
  static async queue(req: AuthenticatedRequest, res: Response) {
    try {
      if (req.method === 'DELETE') {
        const r = await PkService.cancelQueue(req.body.stream_id ?? req.query.stream_id, req.user!.id)
        if (!r.ok) return error(res, r.status, r.message)
        return success(res, null, 'Removed from queue')
      }
      const streamId = typeof req.body.stream_id === 'string' ? req.body.stream_id : ''
      if (!streamId) return error(res, 400, 'stream_id required')
      const r = await PkService.queue(streamId, req.user!.id)
      if (!r.ok) return error(res, r.status, r.message)
      if (r.matched && 'battle' in r && r.battle) {
        // Notify both hosts' rooms about the pairing (notification only —
        // battle state is fetched over REST).
        const io = req.app.get('io')
        const payload = {
          battleId: r.battle.id,
          streamA: r.battle.stream_id_1,
          streamB: r.battle.stream_id_2,
        }
        io?.to(`user_${r.battle.host_id_1}`).emit('pk-matched', payload)
        io?.to(`user_${r.battle.host_id_2}`).emit('pk-matched', payload)
        return success(res, { matched: true, battle: r.battle }, 'Matched!')
      }
      return success(res, { matched: false, battle: null }, 'Searching for opponent…')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async state(req: AuthenticatedRequest, res: Response) {
    try {
      const battle = await PkService.battleState(req.params.id)
      if (!battle) return error(res, 404, 'Battle not found')
      return success(res, battle)
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async end(req: AuthenticatedRequest, res: Response) {
    try {
      const r = await PkService.endBattle(req.params.id)
      if (!r.ok) return error(res, 400, r.message)
      return success(res, r.battle, 'Battle ended')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async dragonStages(req: AuthenticatedRequest, res: Response) {
    try {
      if (req.method === 'POST') {
        const stage = Number(req.body.stage)
        const threshold = Number(req.body.score_threshold)
        const label = typeof req.body.label === 'string' ? req.body.label.slice(0, 40) : null
        if (!Number.isInteger(stage) || stage < 0 || stage > 4 || !Number.isInteger(threshold) || !label) {
          return error(res, 400, 'stage(0-4), label and score_threshold required')
        }
        const patch: Record<string, unknown> = { label, score_threshold: threshold }
        if (typeof req.body.animation_url === 'string') patch.animation_url = req.body.animation_url.slice(0, 1000)
        const { data, error: dbError } = await supabase
          .from('pk_dragon_stages').upsert({ stage, ...patch }, { onConflict: 'stage' }).select().single()
        if (dbError) return error(res, 400, dbError.message)
        return success(res, data, 'Dragon stage updated')
      }
      return success(res, await PkService.dragonThresholds())
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
