import request from 'supertest'
import express from 'express'
import jwt from 'jsonwebtoken'

// --- Supabase client mocks -------------------------------------------------
const mockSingle = jest.fn()
const mockEq = jest.fn()
const mockSelect = jest.fn()
const mockFrom = jest.fn()
const mockSignUp = jest.fn()
const mockSignInWithPassword = jest.fn()

jest.mock('../config/database', () => ({
  supabase: {
    from: (...args: unknown[]) => mockFrom(...args),
    auth: {
      signUp: (...args: unknown[]) => mockSignUp(...args),
      signInWithPassword: (...args: unknown[]) => mockSignInWithPassword(...args),
    },
  },
}))

import routes from '../routes'

const app = express()
app.use(express.json())
app.use('/api/v1', routes)

beforeEach(() => {
  jest.clearAllMocks()
  // Default chain: profiles lookup returns "no existing user".
  mockFrom.mockReturnValue({
    select: mockSelect.mockReturnThis(),
    eq: mockEq.mockReturnThis(),
    single: mockSingle,
  })
  mockSingle.mockResolvedValue({ data: null, error: null })
})

describe('POST /auth/register (unit)', () => {
  const payload = {
    email: 'test@example.com',
    password: 'password123',
    username: 'testuser',
    display_name: 'Test User',
  }

  it('creates a user and returns a verifiable JWT', async () => {
    const user = { id: 'user-1', email: payload.email }
    mockSignUp.mockResolvedValue({ data: { user }, error: null })

    const res = await request(app).post('/api/v1/auth/register').send(payload)

    expect(res.status).toBe(201)
    expect(res.body.success).toBe(true)
    expect(res.body.data.token).toBeDefined()

    const decoded = jwt.verify(res.body.data.token, process.env.JWT_SECRET!) as { id: string }
    expect(decoded.id).toBe('user-1')
    expect(mockSignUp).toHaveBeenCalledWith(
      expect.objectContaining({ email: payload.email, password: payload.password }),
    )
  })

  it('rejects a duplicate username with 400', async () => {
    mockSingle.mockResolvedValue({ data: { id: 'taken' }, error: null })

    const res = await request(app).post('/api/v1/auth/register').send(payload)

    expect(res.status).toBe(400)
    expect(res.body.success).toBe(false)
    expect(mockSignUp).not.toHaveBeenCalled()
  })

  it('returns 400 when Supabase rejects the signup', async () => {
    mockSignUp.mockResolvedValue({ data: { user: null }, error: { message: 'weak password' } })

    const res = await request(app).post('/api/v1/auth/register').send(payload)

    expect(res.status).toBe(400)
    expect(res.body.success).toBe(false)
    expect(res.body.error).toBe('weak password')
  })
})

describe('POST /auth/login (unit)', () => {
  it('authenticates valid credentials and issues a JWT', async () => {
    const user = { id: 'user-2', email: 'login@example.com' }
    mockSignInWithPassword.mockResolvedValue({ data: { user, session: {} }, error: null })

    const res = await request(app)
      .post('/api/v1/auth/login')
      .send({ email: user.email, password: 'password123' })

    expect(res.status).toBe(200)
    expect(res.body.success).toBe(true)

    const decoded = jwt.verify(res.body.data.token, process.env.JWT_SECRET!) as { id: string }
    expect(decoded.id).toBe('user-2')
  })

  it('rejects invalid credentials with 401', async () => {
    mockSignInWithPassword.mockResolvedValue({
      data: { user: null, session: null },
      error: { message: 'Invalid login credentials' },
    })

    const res = await request(app)
      .post('/api/v1/auth/login')
      .send({ email: 'login@example.com', password: 'wrong' })

    expect(res.status).toBe(401)
    expect(res.body.success).toBe(false)
  })
})

describe('GET /auth/me (unit)', () => {
  it('requires authentication', async () => {
    const res = await request(app).get('/api/v1/auth/me')

    expect(res.status).toBe(401)
    expect(res.body.success).toBe(false)
  })
})
