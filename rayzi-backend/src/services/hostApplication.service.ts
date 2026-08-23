import { supabase } from '../config/database'

export class HostApplicationService {
  static async apply(userId: string, body: Record<string, unknown>) {
    const fullName = typeof body.full_name === 'string' ? body.full_name.trim().slice(0, 120) : ''
    const phone = typeof body.phone_number === 'string' ? body.phone_number.trim().slice(0, 30) : ''
    if (!fullName || !phone) throw new Error('full_name and phone_number are required')
    const idDoc = typeof body.id_document_url === 'string' ? body.id_document_url.slice(0, 1000) : null
    const sampleVideo = typeof body.sample_video_url === 'string' ? body.sample_video_url.slice(0, 1000) : null

    const { data: pending } = await supabase
      .from('host_applications').select('id').eq('user_id', userId).eq('status', 'pending').limit(1)
    if (pending?.length) throw new Error('You already have a pending application')

    const { data, error } = await supabase.from('host_applications').insert({
      user_id: userId, full_name: fullName, phone_number: phone,
      id_document_url: idDoc, sample_video_url: sampleVideo,
    }).select().single()
    if (error) throw new Error(error.message)
    return data
  }

  static async myApplication(userId: string) {
    const { data, error } = await supabase
      .from('host_applications').select('*').eq('user_id', userId)
      .order('created_at', { ascending: false }).limit(1).maybeSingle()
    if (error) throw new Error(error.message)
    return data
  }

  static async adminList(status = 'pending') {
    const { data, error } = await supabase
      .from('host_applications')
      .select('*, profiles!host_applications_user_id_fkey(username, display_name)')
      .eq('status', status).order('created_at', { ascending: true })
    if (error) throw new Error(error.message)
    return data
  }

  static async adminDecide(id: string, adminId: string, approve: boolean, reason?: string) {
    const { data: app } = await supabase.from('host_applications').select('status,user_id').eq('id', id).single()
    if (!app) return { ok: false as const, message: 'Application not found' }
    if (app.status !== 'pending') return { ok: false as const, message: 'Already processed' }

    const patch: Record<string, unknown> = {
      status: approve ? 'approved' : 'rejected',
      reviewed_by: adminId, reviewed_at: new Date().toISOString(),
      rejection_reason: approve ? null : (reason ?? 'Does not meet requirements'),
    }
    const { error } = await supabase.from('host_applications').update(patch).eq('id', id)
    if (error) return { ok: false as const, message: error.message }

    if (approve) await supabase.from('profiles').update({ role: 'host' }).eq('id', app.user_id)
    return { ok: true as const }
  }
}
