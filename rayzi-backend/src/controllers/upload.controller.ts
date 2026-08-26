import { Request, Response } from 'express'
import multer from 'multer'
import { supabase } from '../config/database'
import { success, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

/**
 * Authenticated upload proxy.
 *
 * App users hold a custom backend JWT, not a Supabase session, so direct
 * client → Storage uploads evaluate as `anon` and are denied by storage RLS
 * (by design). Uploads therefore flow through here: JWT-authenticated,
 * bucket/mime/size whitelisted, written with the service role, public URL
 * returned for display.
 */

const BUCKET_RULES: Record<string, { mimes: RegExp; exts: string[] }> = {
  avatars: { mimes: /^image\/(jpeg|png|webp)$/, exts: ['jpg', 'jpeg', 'png', 'webp'] },
  'stream-thumbnails': { mimes: /^image\/(jpeg|png|webp)$/, exts: ['jpg', 'jpeg', 'png', 'webp'] },
  'post-media': {
    mimes: /^image\/(jpeg|png|webp)$|^video\/(mp4|quicktime|webm)$/,
    exts: ['jpg', 'jpeg', 'png', 'webp', 'mp4', 'mov', 'webm'],
  },
  'gift-animations': { mimes: /^image\/(gif|webp|png)$|^video\/mp4$/, exts: ['gif', 'webp', 'png', 'mp4'] },
  'room-covers': { mimes: /^image\/(jpeg|png|webp)$/, exts: ['jpg', 'jpeg', 'png', 'webp'] },
  'banners': { mimes: /^image\/(jpeg|png|webp)$/, exts: ['jpg', 'jpeg', 'png', 'webp'] },
}

const MAX_FILE_BYTES = 10 * 1024 * 1024 // 10 MB

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_FILE_BYTES, files: 1 },
}).single('file')

export class UploadController {
  static handler(req: Request, res: Response) {
    upload(req, res, (err?: unknown) => {
      if (err instanceof multer.MulterError) {
        return error(res, 400, err.code === 'LIMIT_FILE_SIZE' ? 'File exceeds 10 MB limit' : `Upload error: ${err.code}`)
      }
      if (err) return error(res, 400, 'Invalid upload')
      void UploadController.process(req as AuthenticatedRequest, res)
    })
  }

  private static async process(req: AuthenticatedRequest, res: Response) {
    try {
      const file = req.file as Express.Multer.File | undefined
      const bucket = typeof req.body?.bucket === 'string' ? req.body.bucket : ''
      const rules = BUCKET_RULES[bucket]
      if (!rules) return error(res, 400, `bucket must be one of: ${Object.keys(BUCKET_RULES).join(', ')}`)
      if (!file) return error(res, 400, 'file field is required')

      const ext = (file.originalname.split('.').pop() ?? '').toLowerCase()
      if (!rules.mimes.test(file.mimetype) || !rules.exts.includes(ext)) {
        return error(res, 400, `File type not allowed in ${bucket}`)
      }

      // Content-addressable-ish path per user; collisions handled by upsert.
      const objectPath = `${req.user!.id}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`
      const { error: uploadError } = await supabase.storage
        .from(bucket)
        .upload(objectPath, file.buffer, { contentType: file.mimetype, upsert: false })
      if (uploadError) return error(res, 500, uploadError.message)

      const { data } = supabase.storage.from(bucket).getPublicUrl(objectPath)
      return success(res, { url: data.publicUrl, bucket, path: objectPath }, 'Uploaded')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
