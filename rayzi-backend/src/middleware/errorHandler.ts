import { Request, Response, NextFunction } from 'express'
import { logger } from '../utils/logger'

export const errorHandler = (err: any, req: Request, res: Response, _next: NextFunction) => {
  logger.error(err.message, { stack: err.stack, path: req.path })
  res.status(err.status || 500).json({
    success: false,
    error: process.env.NODE_ENV === 'production' ? 'Internal server error' : err.message
  })
}