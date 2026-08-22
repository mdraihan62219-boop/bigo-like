/**
 * Origin allowlist shared by HTTP CORS and Socket.IO CORS.
 *
 * Comma-separated via CORS_ORIGIN in the environment, e.g.:
 *   CORS_ORIGIN=https://app.yourdomain.com,https://admin.yourdomain.com
 * Falls back to common local dev origins.
 */
export const getAllowedOrigins = (): string[] => {
  const raw = process.env.CORS_ORIGIN?.trim()
  if (raw) {
    return raw.split(',').map((o) => o.trim()).filter(Boolean)
  }
  return [
    'http://localhost:3000',
    'http://localhost:8080',
    'http://localhost:5173',
  ]
}
