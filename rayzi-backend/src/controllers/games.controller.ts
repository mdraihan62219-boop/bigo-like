import { Response } from 'express'
import { GamesService } from '../services/games.service'
import { success, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

export class GamesController {
  static async list(_req: AuthenticatedRequest, res: Response) {
    try {
      return success(res, await GamesService.listGames())
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async submitScore(req: AuthenticatedRequest, res: Response) {
    try {
      return success(res, await GamesService.submitScore(req.user!.id, req.body ?? {}))
    } catch (err: any) {
      return error(res, err.status ?? 500, err.message)
    }
  }
}
