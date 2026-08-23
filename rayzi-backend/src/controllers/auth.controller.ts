import { Request, Response } from 'express'
import jwt from 'jsonwebtoken'
import { supabase, createAuthClient } from '../config/database'
import { success, created, error } from '../utils/response'

export class AuthController {
  static async register(req: Request, res: Response) {
    // Fresh anon client — keeps login sessions OFF the shared service-role
    // client (a stored session would re-scope every later request).
    const auth = createAuthClient()
    try {
      const { email, password, username, display_name } = req.body

      const { data: existing } = await supabase.from('profiles').select('id').eq('username', username).single()
      if (existing) return error(res, 400, 'Username already taken')

      const { data, error: authError } = await auth.auth.signUp({
        email, password,
        options: { data: { username, display_name } }
      })

      if (authError) return error(res, 400, authError.message)

      const token = jwt.sign(
        { id: data.user!.id, email: data.user!.email },
        process.env.JWT_SECRET!, { expiresIn: '7d' }
      )

      return created(res, { user: data.user, token }, 'Registration successful')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async login(req: Request, res: Response) {
    const auth = createAuthClient()
    try {
      const { email, password } = req.body
      const { data, error: authError } = await auth.auth.signInWithPassword({ email, password })
      if (authError) return error(res, 401, authError.message)

      const token = jwt.sign(
        { id: data.user.id, email: data.user.email },
        process.env.JWT_SECRET!, { expiresIn: '7d' }
      )

      return success(res, { user: data.user, token }, 'Login successful')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async socialLogin(req: Request, res: Response) {
    const auth = createAuthClient()
    try {
      const { provider, token } = req.body
      const { data, error: authError } = await auth.auth.signInWithIdToken({ provider, token })
      if (authError) return error(res, 401, authError.message)

      const jwtToken = jwt.sign(
        { id: data.user.id, email: data.user.email },
        process.env.JWT_SECRET!, { expiresIn: '7d' }
      )

      return success(res, { user: data.user, token: jwtToken })
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async me(req: any, res: Response) {
    try {
      const { data: profile } = await supabase.from('profiles').select('*').eq('id', req.user.id).single()
      return success(res, profile)
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
