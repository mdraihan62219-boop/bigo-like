import { Response } from 'express'
import { HostApplicationService } from '../services/hostApplication.service'
import { success, created, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

export class HostApplicationController {
  static async apply(req: AuthenticatedRequest, res: Response) {
    try {
      return created(res, await HostApplicationService.apply(req.user!.id, req.body), 'Application submitted')
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }

  static async mine(req: AuthenticatedRequest, res: Response) {
    try {
      return success(res, await HostApplicationService.myApplication(req.user!.id))
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
