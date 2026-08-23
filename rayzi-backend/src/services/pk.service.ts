import { supabase } from '../config/database'

export class PkService {
  static async queue(streamId: string, hostId: string) {
    const { data: stream } = await supabase.from('streams').select('host_id,status').eq('id', streamId).single()
    if (!stream) return { ok: false as const, status: 404, message: 'Stream not found' }
    if (stream.host_id !== hostId) return { ok: false as const, status: 403, message: 'Not your stream' }
    if (stream.status !== 'live') return { ok: false as const, status: 400, message: 'Stream is not live' }

    // Already in an active battle?
    const { data: activeBattle } = await supabase.from('pk_battles')
      .select('id').eq('status', 'active')
      .or(`stream_id_1.eq.${streamId},stream_id_2.eq.${streamId}`).limit(1)
    if (activeBattle?.length) return { ok: false as const, status: 409, message: 'Stream already in a battle' }

    // Find an opponent already waiting.
    const { data: opponent } = await supabase.from('pk_matchmaking_queue')
      .select('stream_id').neq('stream_id', streamId).order('queued_at', { ascending: true }).limit(1)

    if (opponent?.length) {
      const opponentStreamId = opponent[0].stream_id as string
      await supabase.from('pk_matchmaking_queue').delete().in('stream_id', [streamId, opponentStreamId])
      const { data: battle, error } = await supabase.from('pk_battles').insert({
        stream_id_1: opponentStreamId, stream_id_2: streamId,
      }).select().single()
      if (error) throw new Error(error.message)
      return { ok: true as const, matched: true as const, battle }
    }

    const { error: qErr } = await supabase.from('pk_matchmaking_queue').upsert({ stream_id: streamId }, { onConflict: 'stream_id' })
    if (qErr) throw new Error(qErr.message)
    return { ok: true as const, matched: false as const }
  }

  static async cancelQueue(streamId: string, hostId: string) {
    const { data: stream } = await supabase.from('streams').select('host_id').eq('id', streamId).single()
    if (!stream || stream.host_id !== hostId) return { ok: false as const, status: 403, message: 'Not your stream' }
    await supabase.from('pk_matchmaking_queue').delete().eq('stream_id', streamId)
    return { ok: true as const }
  }

  static async battleState(battleId: string) {
    const thresholds = await this.dragonThresholds()
    const { data: battle, error } = await supabase.from('pk_battles').select('*').eq('id', battleId).single()
    if (error || !battle) return null
    return { ...battle, dragon_thresholds: thresholds }
  }

  static async dragonThresholds() {
    const { data } = await supabase.from('pk_dragon_stages').select('*').order('stage')
    return data ?? []
  }

  static async endBattle(battleId: string) {
    const { data: b } = await supabase.from('pk_battles').select('*').eq('id', battleId).single()
    if (!b) return { ok: false as const, message: 'Battle not found' }
    if (b.status === 'ended') return { ok: true as const, battle: b }
    let winnerHostId: string | null = null
    if (b.score_1 > b.score_2 && b.host_id_1) winnerHostId = b.host_id_1
    else if (b.score_2 > b.score_1 && b.host_id_2) winnerHostId = b.host_id_2
    else if (b.score_1 === b.score_2) winnerHostId = null
    else winnerHostId = b.status === 'forfeited' ? (b.host_id_1 ?? b.host_id_2) : null

    const { data: battle, error } = await supabase.from('pk_battles').update({
      status: b.status === 'forfeited' ? 'forfeited' : 'ended',
      winner_id: winnerHostId, ended_at: new Date().toISOString(),
    }).eq('id', battleId).select().single()
    if (error) return { ok: false as const, message: error.message }
    return { ok: true as const, battle }
  }

  static async forfeitIfStale() {
    // Auto-forfeit battles whose owner stream ended while battle stayed active.
    const { data: stale } = await supabase.from('pk_battles').select('id').eq('status', 'active')
      .lt('started_at', new Date(Date.now() - 30 * 60 * 1000).toISOString())
    for (const row of stale ?? []) {
      await supabase.from('pk_battles').update({ status: 'forfeited', ended_at: new Date().toISOString() }).eq('id', row.id)
    }
  }
}
