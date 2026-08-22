import admin from 'firebase-admin'
import { logger } from '../utils/logger'

let _messaging: admin.messaging.Messaging | null = null

try {
  if (!admin.apps.length && process.env.FIREBASE_PROJECT_ID && process.env.FIREBASE_PRIVATE_KEY && process.env.FIREBASE_CLIENT_EMAIL) {
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: process.env.FIREBASE_PROJECT_ID,
        privateKey: process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
        clientEmail: process.env.FIREBASE_CLIENT_EMAIL
      })
    })
    _messaging = admin.messaging()
  } else {
    logger.warn('Firebase not configured - push notifications disabled')
  }
} catch (err) {
  logger.warn('Firebase initialization failed - push notifications disabled', err)
}

export const messaging = _messaging