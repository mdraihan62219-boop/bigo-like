import request from 'supertest'
import express from 'express'

// --- Supabase client mocks -------------------------------------------------
const mockRpc = jest.fn()
const mockSelect = jest.fn()
const mockEq = jest.fn()
const mockOrder = jest.fn()
const mockSingle = jest.fn()
const mockFrom = jest.fn()

jest.mock('../config/database', () => ({
  supabase: {
    from: (...args: unknown[]) => mockFrom(...args),
    rpc: (...args: unknown[]) => mockRpc(...args),
  },
}))

import routes from '../routes'

const app = express()
app.use(express.json())
app.use('/api/v1', routes)

// Bypass JWT auth the same way auth.test.ts does: sign a real token.
process.env.JWT_SECRET = 'test-secret-key-for-jest-min-32-chars!!'
import jwt from 'jsonwebtoken'
const USER_ID = '11111111-2222-3333-4444-555555555555'
const authHeader = () =>
  `Bearer ${jwt.sign({ id: USER_ID, email: 'gamer@example.com' }, process.env.JWT_SECRET!)}`

beforeEach(() => {
  jest.clearAllMocks()
  mockFrom.mockReturnValue({
    select: mockSelect.mockReturnThis(),
    eq: mockEq.mockReturnThis(),
    order: mockOrder.mockReturnThis(),
    single: mockSingle,
  })
  // authenticate() reads profiles live — default to an ordinary active user.
  mockSingle.mockResolvedValue({ data: { role: 'user', is_banned: false }, error: null })
})

describe('POST /games/score (unit)', () => {
  it('rejects missing game_key with 400 before touching the RPC', async () => {
    const res = await request(app)
      .post('/api/v1/games/score')
      .set('Authorization', authHeader())
      .send({ score: 100, moves: 10 })

    expect(res.status).toBe(400)
    expect(mockRpc).not.toHaveBeenCalled()
  })

  it.each([
    ['float score', { game_key: '2048', score: 10.5, moves: 3 }],
    ['negative score', { game_key: '2048', score: -5, moves: 3 }],
    ['absurd score', { game_key: '2048', score: 999_999_999_999, moves: 1 }],
    ['string moves', { game_key: '2048', score: 100, moves: 'many' }],
    ['missing moves', { game_key: '2048', score: 100 }],
  ])('rejects %s with 400 without calling award_game_coins', async (_name, body) => {
    const res = await request(app)
      .post('/api/v1/games/score')
      .set('Authorization', authHeader())
      .send(body)

    expect(res.status).toBe(400)
    expect(mockRpc).not.toHaveBeenCalled()
  })

  it('forwards valid submissions to award_game_coins and returns the verdict', async () => {
    const verdict = {
      session_id: 'sess-1',
      coins_awarded: 12,
      balance_after: 112,
      capped: false,
      sessions_used_today: 3,
      max_sessions_per_day: 15,
    }
    mockRpc.mockResolvedValue({ data: verdict, error: null })

    const res = await request(app)
      .post('/api/v1/games/score')
      .set('Authorization', authHeader())
      .send({ game_key: '2048', score: 600, moves: 40 })

    expect(res.status).toBe(200)
    expect(res.body.data.coins_awarded).toBe(12)
    expect(mockRpc).toHaveBeenCalledWith('award_game_coins', {
      p_user_id: USER_ID,
      p_game_key: '2048',
      p_score: 600,
      p_moves: 40,
    })
  })

  it('maps RPC implausibility rejections to HTTP 422', async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: { message: 'Implausible score: 99999 points exceeds achievable maximum for 2 moves' },
    })

    const res = await request(app)
      .post('/api/v1/games/score')
      .set('Authorization', authHeader())
      .send({ game_key: '2048', score: 99999, moves: 2 })

    expect(res.status).toBe(422)
    expect(res.body.error).toMatch(/Implausible/)
  })
})

describe('GET /games (unit)', () => {
  it('lists active games from game_config', async () => {
    // listGames chains select().eq().order() and awaits the result.
    mockOrder.mockResolvedValue({
      data: [
        { game_key: '2048', display_name: '2048 Puzzle', is_active: true },
        { game_key: 'tic_tac_toe', display_name: 'Tic Tac Toe', is_active: true },
      ],
      error: null,
    })

    const res = await request(app).get('/api/v1/games').set('Authorization', authHeader())

    expect(res.status).toBe(200)
    expect(res.body.data).toHaveLength(2)
  })
})
