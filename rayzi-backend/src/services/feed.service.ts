import { supabase } from '../config/database'

const POST_SELECT = `*, profiles!posts_user_id_fkey(username, display_name, avatar_url, equipped_frame_id, equipped_badge_id, name_effect)`

export class FeedService {
  static async listPosts(viewerId: string | null, scope: string, page: number, limit: number) {
    let query = supabase
      .from('posts')
      .select(POST_SELECT, { count: 'exact' })
      .order('created_at', { ascending: false })

    if (scope === 'timeline') {
      if (!viewerId) return { data: [], total: 0 }
      const { data: follows } = await supabase.from('follows').select('following_id').eq('follower_id', viewerId)
      const ids = (follows ?? []).map((f: { following_id: string }) => f.following_id)
      query = query.in('user_id', [...ids, viewerId])
    }

    const { data, count, error } = await query.range((page - 1) * limit, page * limit - 1)
    if (error) throw new Error(error.message)
    return { data: data ?? [], total: count ?? 0 }
  }

  static async createPost(userId: string, body: Record<string, unknown>) {
    const content = typeof body.content === 'string' ? body.content.slice(0, 2000) : ''
    const mediaUrls = Array.isArray(body.media_urls) ? body.media_urls.filter((u): u is string => typeof u === 'string').slice(0, 10) : []
    const mediaType = mediaUrls.length === 0 ? null : (body.media_type === 'video' ? 'video' : 'image')
    const visibility = body.visibility === 'followers' ? 'followers' : 'public'
    if (!content && mediaUrls.length === 0) throw new Error('Post must have content or media')

    const { data, error } = await supabase.from('posts').insert({
      user_id: userId, content, media_urls: mediaUrls,
      ...(mediaType ? { media_type: mediaType } : {}), visibility,
    }).select(POST_SELECT).single()
    if (error) throw new Error(error.message)
    return data
  }

  static async deletePost(userId: string, role: string | undefined, postId: string) {
    const { data: post } = await supabase.from('posts').select('user_id').eq('id', postId).single()
    if (!post) return { ok: false as const, status: 404 }
    if (post.user_id !== userId && role !== 'admin') return { ok: false as const, status: 403 }
    // Soft-remove keeps comment threads intact for moderation review.
    const { error } = await supabase.from('posts').update({ is_removed: true }).eq('id', postId)
    if (error) return { ok: false as const, status: 400 }
    return { ok: true as const }
  }

  static async like(userId: string, postId: string) {
    const { error } = await supabase.from('post_likes').upsert({ post_id: postId, user_id: userId })
    if (error) throw new Error(error.message)
    return 'Liked'
  }

  static async unlike(userId: string, postId: string) {
    const { error } = await supabase.from('post_likes').delete().eq('post_id', postId).eq('user_id', userId)
    if (error) throw new Error(error.message)
    return 'Unliked'
  }

  static async getComments(postId: string, page: number, limit: number) {
    const { data, count, error } = await supabase
      .from('post_comments')
      .select('*, profiles!post_comments_user_id_fkey(username, display_name, avatar_url)', { count: 'exact' })
      .eq('post_id', postId).is('parent_id', null)
      .order('created_at', { ascending: false })
      .range((page - 1) * limit, page * limit - 1)
    if (error) throw new Error(error.message)
    return { data: data ?? [], total: count ?? 0 }
  }

  static async comment(userId: string, postId: string, body: Record<string, unknown>) {
    const content = typeof body.content === 'string' ? body.content.trim().slice(0, 500) : ''
    if (!content) throw new Error('Comment content required')
    const { data, error } = await supabase.from('post_comments').insert({
      post_id: postId, user_id: userId, content,
    }).select().single()
    if (error) throw new Error(error.message)
    return data
  }

  static async listStories() {
    const { data, error } = await supabase
      .from('stories')
      .select('*, profiles!stories_author_id_fkey(id, username, display_name, avatar_url)')
      .gt('expires_at', new Date().toISOString())
      .order('created_at', { ascending: false })
    if (error) throw new Error(error.message)

    const grouped: Record<string, { author: unknown; stories: unknown[] }> = {}
    for (const s of data ?? []) {
      const key = s.author_id as string
      grouped[key] ??= { author: s.profiles, stories: [] }
      grouped[key].stories.push(s)
    }
    return Object.entries(grouped).map(([authorId, g]) => ({ author_id: authorId, ...g }))
  }

  static async createStory(userId: string, body: Record<string, unknown>) {
    const mediaUrl = typeof body.media_url === 'string' ? body.media_url : ''
    if (!mediaUrl) throw new Error('media_url required')
    const mediaType = body.media_type === 'video' ? 'video' : 'image'
    const { data, error } = await supabase.from('stories').insert({
      author_id: userId, media_url: mediaUrl, media_type: mediaType,
    }).select().single()
    if (error) throw new Error(error.message)
    return data
  }

  static async viewStory(userId: string, storyId: string) {
    const { error } = await supabase.from('story_views').upsert({ story_id: storyId, viewer_id: userId })
    if (error) throw new Error(error.message)
    return 'Viewed'
  }
}
