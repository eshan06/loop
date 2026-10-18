// One place that talks to the backend. The browser only ever calls /api/...;
// Vite (dev) or Vercel (prod) forwards it to the server. See docs/WEB.md "Talking to the API".

const TOKEN_KEY = 'loop.token'
const BASE = '/api'

export class ApiError extends Error {
  status: number
  code: string
  constructor(status: number, code: string, message: string) {
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.code = code
  }
}

// ---- token -------------------------------------------------------------

export function getToken(): string | null {
  try {
    return localStorage.getItem(TOKEN_KEY)
  } catch {
    return null
  }
}

export function setToken(token: string | null) {
  try {
    if (token) localStorage.setItem(TOKEN_KEY, token)
    else localStorage.removeItem(TOKEN_KEY)
  } catch {
    /* storage unavailable: session lasts until reload */
  }
}

let onUnauthorized: () => void = () => {}
/** AuthProvider registers what happens on any 401: forget the user and go to /signin. */
export function setUnauthorizedHandler(fn: () => void) {
  onUnauthorized = fn
}

// ---- media -------------------------------------------------------------

/** Photo URLs come back as absolute http://host:8000/media/... which an HTTPS page can't load. */
export const media = (u: string | null | undefined): string | null =>
  u ? u.replace(/^https?:\/\/[^/]+\/media\//, '/api/media/') : null

// ---- request -----------------------------------------------------------

type Query = Record<string, string | number | boolean | null | undefined>

export function buildQuery(query?: Query): string {
  if (!query) return ''
  const p = new URLSearchParams()
  for (const [k, v] of Object.entries(query)) {
    if (v === undefined || v === null || v === '') continue
    p.set(k, String(v))
  }
  const s = p.toString()
  return s ? `?${s}` : ''
}

interface Options {
  method?: string
  query?: Query
  json?: unknown
  form?: FormData
  auth?: boolean
  signal?: AbortSignal
}

/** Parse the contract's error shape; anything else becomes a generic error for that status. */
export async function toApiError(res: Response): Promise<ApiError> {
  let code = 'server_error'
  let message = 'Something went wrong. Try again.'
  try {
    const body = await res.json()
    if (body?.error?.code) {
      code = body.error.code
      message = body.error.message ?? message
    }
  } catch {
    if (res.status === 502 || res.status === 504) message = "Couldn't reach Loop. Check your connection and try again."
  }
  return new ApiError(res.status, code, message)
}

export async function request<T>(path: string, opts: Options = {}): Promise<T> {
  const { method = 'GET', query, json, form, auth = true, signal } = opts
  const headers: Record<string, string> = {}
  const token = getToken()
  if (auth && token) headers.Authorization = `Bearer ${token}`
  let body: BodyInit | undefined
  if (form) body = form
  else if (json !== undefined) {
    headers['Content-Type'] = 'application/json'
    body = JSON.stringify(json)
  }

  let res: Response
  try {
    res = await fetch(`${BASE}${path}${buildQuery(query)}`, { method, headers, body, signal })
  } catch (e) {
    if (e instanceof DOMException && e.name === 'AbortError') throw e
    throw new ApiError(0, 'network', "Couldn't reach Loop. Check your connection and try again.")
  }

  if (!res.ok) {
    const err = await toApiError(res)
    if (res.status === 401 && auth) {
      setToken(null)
      onUnauthorized()
    }
    throw err
  }
  if (res.status === 204) return undefined as T
  return (await res.json()) as T
}

export const isAbort = (e: unknown) => e instanceof DOMException && e.name === 'AbortError'
