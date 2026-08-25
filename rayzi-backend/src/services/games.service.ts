import { supabase } from '../config/database'

/** Shape of one row in game_config. */
export interface GameConfigRow {
  game_key: string
  display_name: string
  is_active: boolean
  coins_per_100_pts: number
  max_coins_per_session: number
  min_moves_to_score: number
  score_cap_per_move: number
  max_sessions_per_day: number
}

export interface AwardResult {
  session_id: string
  coins_awarded: number
  balance_after: number | null
  capped: boolean
  sessions_used_today: number
  max_sessions_per_day: number
}

export class GamesService {
  /** Public catalogue for the games home screen. */
  static async listGames() {
    const { data, error } = await supabase
      .from('game_config')
      .select('game_key, display_name, is_active, max_coins_per_session, max_sessions_per_day')
      .eq('is_active', true)
      .order('game_key', { ascending: true })
    if (error) throw new Error(error.message)
    return data ?? []
  }

  /**
   * Submit a finished game. ALL payout math (plausibility bounds, per-session
   * cap, daily limit, ledger write) happens inside the award_game_coins RPC —
   * the client-submitted score is never trusted here.
   */
  static async submitScore(
    userId: string,
    body: Record<string, unknown>
  ): Promise<AwardResult> {
    const bad = (msg: string): never => {
      const e = new Error(msg) as Error & { status?: number }
      e.status = 400
      throw e
    }
    const gameKey = typeof body.game_key === 'string' ? body.game_key.trim() : ''
    if (!gameKey) bad('game_key is required')

    // Reject non-integer / NaN / stringly scores before they reach the RPC.
    const score = Number(body.score)
    const moves = Number(body.moves)
    if (!Number.isInteger(score) || score < 0 || score > 100_000_000) {
      bad('score must be a non-negative integer')
    }
    if (!Number.isInteger(moves) || moves < 0 || moves > 1_000_000) {
      bad('moves must be a non-negative integer')
    }

    const { data, error } = await supabase.rpc('award_game_coins', {
      p_user_id: userId,
      p_game_key: gameKey,
      p_score: score,
      p_moves: moves,
    })
    if (error) {
      // Plausibility rejections surface as HTTP 422 so the app can show a
      // clear "score rejected" message instead of a generic failure.
      const e = new Error(error.message) as Error & { status?: number }
      e.status = 422
      throw e
    }
    return data as AwardResult
  }
}
