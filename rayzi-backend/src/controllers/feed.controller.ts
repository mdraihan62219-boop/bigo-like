import { Response } from 'express'
import { FeedService } from '../services/feed.service'
import { success, created, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

export class FeedController {
  static async list(req: AuthenticatedRequest, res: Response) {
    try {
      const scope = req.query.scope === 'timeline' ? 'timeline' : 'all'
      const page = Math.max(1, +((req.query.page as string) ?? 1))
      const limit = Math.min(50, Math.max(1, +((req.query.limit as string) ?? 20)))
      const { data, total } = await FeedService.listPosts(req.user?.id ?? null, scope, page, limit)
      return success(res, data, undefined, { page, limit, total })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async create(req: AuthenticatedRequest, res: Response) {
    try {
      const post = await FeedService.createPost(req.user!.id, req.body)
      // Push to followers' rooms so their feeds refresh (notification only).
      try {
        const { supabase } = await import('../config/database')
        const { data: followers } = await supabase
          .from('follows').select('follower_id').eq('following_id', req.user!.id)
        const io = req.app.get('io')
        for (const f of followers ?? []) {
          io?.to(`user_${f.follower_id}`).emit('new-post', { postId: post.id, authorId: req.user!.id })
        }
      } catch (_) {
        // Feed push is best-effort.
      }
      return created(res, post, 'Post created')
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }

  static async remove(req: AuthenticatedRequest, res: Response) {
    try {
      const r = await FeedService.deletePost(req.user!.id, req.user?.role, req.params.id)
      if (!r.ok) return error(res, r.status, r.status === 403 ? 'Not allowed' : 'Post not found')
      return success(res, null, 'Post removed')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async like(req: AuthenticatedRequest, res: Response) {
    try {
      return success(res, null, await FeedService.like(req.user!.id, req.params.id))
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }

  static async unlike(req: AuthenticatedRequest, res: Response) {
    try {
      return success(res, null, await FeedService.unlike(req.user!.id, req.params.id))
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }

  static async comments(req: AuthenticatedRequest, res: Response) {
    try {
      if (req.method === 'POST') {
        const c = await FeedService.comment(req.user!.id, req.params.id, req.body)
        return created(res, c, 'Comment added')
      }
      const page = Math.max(1, +((req.query.page as string) ?? 1))
      const limit = Math.min(100, Math.max(1, +((req.query.limit as string) ?? 50)))
      const { data, total } = await FeedService.getComments(req.params.id, page, limit)
      return success(res, data, undefined, { page, limit, total })
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }

  static async stories(req: AuthenticatedRequest, res: Response) {
    try {
      if (req.method === 'POST') {
        const s = await FeedService.createStory(req.user!.id, req.body)
        return created(res, s, 'Story created')
      }
      return success(res, await FeedService.listStories())
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }

  static async viewStory(req: AuthenticatedRequest, res: Response) {
    try {
      return success(res, null, await FeedService.viewStory(req.user!.id, req.params.id))
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }
}
