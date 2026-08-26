import { Response } from 'express'
import { supabase } from '../config/database'
import { success, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

export class PromoBannerController {
  static async getActive(_req: AuthenticatedRequest, res: Response) {
    try {
      const { data, error: dbError } = await supabase
        .from('promo_banners')
        .select('id, image_url, link_url, banner_type, sort_order')
        .eq('is_active', true)
        .order('sort_order', { ascending: true })

      if (dbError) return error(res, 400, dbError.message)
      return success(res, data ?? [])
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async list(_req: AuthenticatedRequest, res: Response) {
    try {
      const { data, error: dbError } = await supabase
        .from('promo_banners')
        .select('*')
        .order('sort_order', { ascending: true })

      if (dbError) return error(res, 400, dbError.message)
      return success(res, data ?? [])
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async create(req: AuthenticatedRequest, res: Response) {
    try {
      const { image_url, link_url, banner_type, sort_order } = req.body
      if (typeof image_url !== 'string' || !image_url.trim()) {
        return error(res, 400, 'image_url is required')
      }
      if (!['promo', 'agency', 'top_host'].includes(banner_type)) {
        return error(res, 400, 'banner_type must be promo, agency, or top_host')
      }
      const { data, error: dbError } = await supabase
        .from('promo_banners')
        .insert({ image_url: image_url.trim(), link_url, banner_type, sort_order: sort_order ?? 0 })
        .select()
        .single()

      if (dbError) return error(res, 400, dbError.message)
      return success(res, data, 'Banner created')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async update(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const { image_url, link_url, banner_type, sort_order, is_active } = req.body
      const patch: Record<string, unknown> = { updated_at: new Date().toISOString() }
      if (image_url !== undefined) patch.image_url = image_url
      if (link_url !== undefined) patch.link_url = link_url
      if (banner_type !== undefined) patch.banner_type = banner_type
      if (sort_order !== undefined) patch.sort_order = sort_order
      if (is_active !== undefined) patch.is_active = is_active

      const { data, error: dbError } = await supabase
        .from('promo_banners')
        .update(patch)
        .eq('id', id)
        .select()
        .single()

      if (dbError) return error(res, 400, dbError.message)
      return success(res, data, 'Banner updated')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async remove(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params
      const { error: dbError } = await supabase
        .from('promo_banners')
        .delete()
        .eq('id', id)

      if (dbError) return error(res, 400, dbError.message)
      return success(res, null, 'Banner deleted')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
