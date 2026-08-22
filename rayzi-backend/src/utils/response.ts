import { Response } from 'express'
import { ApiResponse } from '../types'

export const success = <T>(res: Response, data: T, message?: string, meta?: any) => {
  const response: ApiResponse<T> = { success: true, data, message, meta }
  return res.status(200).json(response)
}

export const created = <T>(res: Response, data: T, message?: string) => {
  return res.status(201).json({ success: true, data, message })
}

export const error = (res: Response, status: number, message: string) => {
  return res.status(status).json({ success: false, error: message })
}