/** Coerces an Express query param to a bounded positive integer. */
export const pageParam = (v: unknown, fallback = 1): number => {
  const n = Number(Array.isArray(v) ? v[0] : v)
  return Number.isInteger(n) && n > 0 ? n : fallback
}

/** Coerces an Express query param to a bounded page size. */
export const limitParam = (v: unknown, fallback = 20, max = 100): number => {
  const n = Number(Array.isArray(v) ? v[0] : v)
  return Number.isInteger(n) && n > 0 ? Math.min(max, n) : fallback
}
