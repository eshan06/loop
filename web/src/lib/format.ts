/** "2h ago" for recent timestamps, a short date for older ones. Input is UTC ISO 8601. */
export function timeAgo(iso: string, now = Date.now()): string {
  const t = new Date(iso).getTime()
  if (Number.isNaN(t)) return ''
  const s = Math.max(0, Math.round((now - t) / 1000))
  if (s < 45) return 'just now'
  const m = Math.round(s / 60)
  if (m < 60) return `${m}m ago`
  const h = Math.round(m / 60)
  if (h < 24) return `${h}h ago`
  const d = Math.round(h / 24)
  if (d < 7) return `${d}d ago`
  return new Date(t).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })
}

export function formatDateTime(iso: string): string {
  return new Date(iso).toLocaleString(undefined, { weekday: 'short', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })
}

export function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })
}

export function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })
}

export const n0 = (n: number) => Math.round(n).toLocaleString()
export const n1 = (n: number) => (Math.round(n * 10) / 10).toLocaleString(undefined, { maximumFractionDigits: 1 })

/** kg with sensible precision: 0.44, 3.1, 61.5 */
export function kg(n: number): string {
  if (n < 1) return (Math.round(n * 100) / 100).toLocaleString(undefined, { maximumFractionDigits: 2 })
  return n1(n)
}

export const displayName = (name: string | null | undefined) => name?.trim() || 'Loop member'
export const firstName = (name: string | null | undefined) => displayName(name).split(' ')[0]
export const initials = (name: string | null | undefined) =>
  displayName(name).split(/\s+/).slice(0, 2).map((p) => p[0]?.toUpperCase() ?? '').join('')
