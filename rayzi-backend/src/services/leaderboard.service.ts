import { supabase } from '../config/database'
import cron from 'node-cron'

export class LeaderboardService {
  static init() {
    cron.schedule('0 0 * * *', () => this.calculate('daily'))
    cron.schedule('0 0 * * 0', () => this.calculate('weekly'))
    cron.schedule('0 0 1 * *', () => this.calculate('monthly'))
  }

  static async calculate(period: 'daily' | 'weekly' | 'monthly') {
    const date = new Date().toISOString().split('T')[0]

    const { data: streamers } = await supabase.rpc('get_top_streamers', { period })
    if (streamers) {
      for (let i = 0; i < streamers.length; i++) {
        await supabase.from('leaderboards').upsert({
          user_id: streamers[i].user_id, period, category: 'streamer',
          score: streamers[i].score, rank: i + 1, date
        })
      }
    }

    const { data: gifters } = await supabase.rpc('get_top_gifters', { period })
    if (gifters) {
      for (let i = 0; i < gifters.length; i++) {
        await supabase.from('leaderboards').upsert({
          user_id: gifters[i].user_id, period, category: 'gifter',
          score: gifters[i].score, rank: i + 1, date
        })
      }
    }
  }
}