import { Response } from 'express'
import { ShopService } from '../services/shop.service'
import { success, error } from '../utils/response'
import { AuthenticatedRequest } from '../types'

export class ShopController {
  static async listItems(req: AuthenticatedRequest, res: Response) {
    try {
      const category = typeof req.query.category === 'string' ? req.query.category : undefined
      return success(res, await ShopService.listItems(category))
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async purchase(req: AuthenticatedRequest, res: Response) {
    try {
      const result = await ShopService.purchase(req.user!.id, req.body.item_id)
      if (!result.ok) return error(res, 400, result.message)
      return success(res, result.data, 'Purchased')
    } catch (err: any) {
      return error(res, 400, err.message)
    }
  }

  static async inventory(req: AuthenticatedRequest, res: Response) {
    try {
      return success(res, await ShopService.inventory(req.user!.id))
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }

  static async equip(req: AuthenticatedRequest, res: Response) {
    try {
      const equip = req.method === 'POST'
      const r = await ShopService.equip(req.user!.id, req.params.itemId, equip)
      if (!r.ok) return error(res, r.status, r.message)
      return success(res, r.data, equip ? 'Equipped' : 'Unequipped')
    } catch (err: any) {
      return error(res, 500, err.message)
    }
  }
}
