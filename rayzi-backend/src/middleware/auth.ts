import { Response, NextFunction } from 'express'
import jwt from 'jsonwebtoken'
import { AuthenticatedRequest } from '../types'
import { supabase } from '../config/database'

/**
 * Verifies the backend-issued JWT (signed with JWT_SECRET at login time,
 * after credentials were validated against Supabase). The previous
 * implementation forwarded this custom token to supabase.auth.getUser(),
 * which only accepts genuine Supabase access tokens — so every
 * authenticated request failed. Role and ban status are read live from
 * `profiles` so promotions/bans take effect without re-login.
 */
export const authenticate = async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const token = req.headers.authorization?.split(' ')[1]
    if (!token) return res.status(401).json({ success: false, error: 'No token provided' })

    const decoded = jwt.verify(token, process.env.JWT_SECRET!) as { id?: string; email?: string }
    if (!decoded?.id) return res.status(401).json({ success: false, error: 'Invalid token' })

    const { data: profile } = await supabase
      .from('profiles')
      .select('role, is_banned')
      .eq('id', decoded.id)
      .single()

    if (!profile) return res.status(401).json({ success: false, error: 'User not found' })
    if (profile.is_banned) return res.status(403).json({ success: false, error: 'Account banned' })

    req.user = {
      id: decoded.id,
      email: decoded.email ?? '',
      role: profile.role || 'user',
    }
    next()
  } catch (_err) {
    return res.status(401).json({ success: false, error: 'Authentication failed' })
  }
}

export const requireAdmin = (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  if (req.user?.role !== 'admin') {
    return res.status(403).json({ success: false, error: 'Admin access required' })
  }
  next()
}

/**
 * Like `authenticate`, but for public browse endpoints: attaches req.user
 * when a valid, non-banned token is present; otherwise continues as
 * anonymous instead of returning 401.
 */
export const optionalAuth = async (req: AuthenticatedRequest, _res: Response, next: NextFunction) => {
  try {
    const token = req.headers.authorization?.split(' ')[1]
    if (token && process.env.JWT_SECRET) {
      const decoded = jwt.verify(token, process.env.JWT_SECRET) as { id?: string; email?: string }
      if (decoded?.id) {
        const { data: profile } = await supabase
          .from('profiles')
          .select('role, is_banned')
          .eq('id', decoded.id)
          .single()

        if (profile && !profile.is_banned) {
          req.user = {
            id: decoded.id,
            email: decoded.email ?? '',
            role: profile.role || 'user',
          }
        }
      }
    }
  } catch (_err) {
    // Anonymous access — treated the same as no token.
  }
  next()
}
