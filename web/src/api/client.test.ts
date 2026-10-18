import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError, buildQuery, media, request, setToken, setUnauthorizedHandler } from './client'

describe('media', () => {
  it('rewrites server photo URLs to the same-origin proxy', () => {
    expect(media('http://163.192.218.131:8000/media/71.jpg')).toBe('/api/media/71.jpg')
    expect(media('http://163.192.218.131:8000/media/avatars/3.jpg')).toBe('/api/media/avatars/3.jpg')
  })
  it('passes null through', () => {
    expect(media(null)).toBeNull()
    expect(media(undefined)).toBeNull()
  })
})

describe('buildQuery', () => {
  it('drops empty values and encodes the rest', () => {
    expect(buildQuery({ q: 'denim jacket', size: '', category: undefined, offset: 0 })).toBe('?q=denim+jacket&offset=0')
    expect(buildQuery({})).toBe('')
  })
})

describe('request', () => {
  const store = new Map<string, string>()
  beforeEach(() => {
    store.clear()
    vi.stubGlobal('localStorage', {
      getItem: (k: string) => store.get(k) ?? null,
      setItem: (k: string, v: string) => void store.set(k, v),
      removeItem: (k: string) => void store.delete(k),
    })
  })
  afterEach(() => vi.unstubAllGlobals())

  const respond = (status: number, body?: unknown) =>
    vi.stubGlobal('fetch', vi.fn(async () => new Response(body === undefined ? null : JSON.stringify(body), { status })))

  it('sends the bearer token', async () => {
    setToken('abc')
    respond(200, { ok: true })
    await request('/me')
    const [url, init] = (fetch as unknown as ReturnType<typeof vi.fn>).mock.calls[0]
    expect(url).toBe('/api/me')
    expect(init.headers.Authorization).toBe('Bearer abc')
  })

  it('turns the contract error shape into an ApiError', async () => {
    respond(400, { error: { code: 'not_edu_email', message: 'Use your college .edu email address.' } })
    await expect(request('/auth/login', { method: 'POST', json: {}, auth: false })).rejects.toMatchObject({
      status: 400,
      code: 'not_edu_email',
      message: 'Use your college .edu email address.',
    })
  })

  it('drops the token and calls the handler on a 401', async () => {
    setToken('abc')
    const handler = vi.fn()
    setUnauthorizedHandler(handler)
    respond(401, { error: { code: 'unauthorized', message: 'Sign in again.' } })
    await expect(request('/me')).rejects.toBeInstanceOf(ApiError)
    expect(store.has('loop.token')).toBe(false)
    expect(handler).toHaveBeenCalledOnce()
  })

  it('returns undefined for 204', async () => {
    respond(204)
    await expect(request('/listings/1/save', { method: 'PUT' })).resolves.toBeUndefined()
  })

  it('reports an unreachable server as a network error', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => { throw new TypeError('Failed to fetch') }))
    await expect(request('/me')).rejects.toMatchObject({ code: 'network' })
  })
})
