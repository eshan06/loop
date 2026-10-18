import { useCallback, useEffect, useRef, useState } from 'react'
import type { Paged } from '../api/types'
import { isAbort } from '../api/client'

export function errMsg(e: unknown): string {
  return e instanceof Error ? e.message : 'Something went wrong. Try again.'
}

/** Load one value; re-runs when `deps` change. */
export function useAsync<T>(fn: (signal: AbortSignal) => Promise<T>, deps: unknown[]) {
  const [data, setData] = useState<T | null>(null)
  const [error, setError] = useState<Error | null>(null)
  const [loading, setLoading] = useState(true)
  const [tick, setTick] = useState(0)
  const fnRef = useRef(fn)
  fnRef.current = fn

  useEffect(() => {
    const ctl = new AbortController()
    setLoading(true)
    setError(null)
    fnRef.current(ctl.signal)
      .then((d) => {
        if (!ctl.signal.aborted) setData(d)
      })
      .catch((e) => {
        if (!isAbort(e) && !ctl.signal.aborted) setError(e instanceof Error ? e : new Error(String(e)))
      })
      .finally(() => {
        if (!ctl.signal.aborted) setLoading(false)
      })
    return () => ctl.abort()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, tick])

  const reload = useCallback(() => setTick((t) => t + 1), [])
  return { data, setData, error, loading, reload }
}

/** A paged list ({items,total,next_offset}) with load-more. Resets when `deps` change. */
export function usePaged<T>(fetchPage: (offset: number, signal: AbortSignal) => Promise<Paged<T>>, deps: unknown[]) {
  const [items, setItems] = useState<T[]>([])
  const [total, setTotal] = useState(0)
  const [next, setNext] = useState<number | null>(null)
  const [loading, setLoading] = useState(true)
  const [loadingMore, setLoadingMore] = useState(false)
  const [error, setError] = useState<Error | null>(null)
  const [moreError, setMoreError] = useState<Error | null>(null)
  const [tick, setTick] = useState(0)
  const fetchRef = useRef(fetchPage)
  fetchRef.current = fetchPage
  const nextRef = useRef<number | null>(null)
  const ctlRef = useRef<AbortController | null>(null)

  useEffect(() => {
    const ctl = new AbortController()
    ctlRef.current?.abort()
    ctlRef.current = ctl
    setLoading(true)
    setError(null)
    setMoreError(null)
    fetchRef.current(0, ctl.signal)
      .then((p) => {
        if (ctl.signal.aborted) return
        setItems(p.items)
        setTotal(p.total)
        setNext(p.next_offset)
        nextRef.current = p.next_offset
      })
      .catch((e) => {
        if (!isAbort(e) && !ctl.signal.aborted) setError(e instanceof Error ? e : new Error(String(e)))
      })
      .finally(() => {
        if (!ctl.signal.aborted) setLoading(false)
      })
    return () => ctl.abort()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, tick])

  const loadMore = useCallback(async () => {
    const offset = nextRef.current
    if (offset === null || loadingMore) return
    const ctl = ctlRef.current
    setLoadingMore(true)
    setMoreError(null)
    try {
      const p = await fetchRef.current(offset, ctl?.signal ?? new AbortController().signal)
      if (ctl?.signal.aborted) return
      setItems((prev) => {
        const seen = new Set(prev.map((x) => (x as { id?: number }).id))
        return [...prev, ...p.items.filter((x) => !seen.has((x as { id?: number }).id))]
      })
      setTotal(p.total)
      setNext(p.next_offset)
      nextRef.current = p.next_offset
    } catch (e) {
      if (!isAbort(e)) setMoreError(e instanceof Error ? e : new Error(String(e)))
    } finally {
      setLoadingMore(false)
    }
  }, [loadingMore])

  const reload = useCallback(() => setTick((t) => t + 1), [])
  return { items, setItems, total, hasMore: next !== null, loading, loadingMore, error, moreError, loadMore, reload }
}

/** Run `fn` every `ms` while the tab is visible (and once when it becomes visible again). */
export function useVisibleInterval(fn: () => void, ms: number, enabled = true) {
  const ref = useRef(fn)
  ref.current = fn
  useEffect(() => {
    if (!enabled) return
    let id: number | undefined
    const start = () => {
      if (id === undefined) id = window.setInterval(() => ref.current(), ms)
    }
    const stop = () => {
      if (id !== undefined) {
        window.clearInterval(id)
        id = undefined
      }
    }
    const onVis = () => {
      if (document.visibilityState === 'visible') {
        ref.current()
        start()
      } else stop()
    }
    if (document.visibilityState === 'visible') start()
    document.addEventListener('visibilitychange', onVis)
    return () => {
      stop()
      document.removeEventListener('visibilitychange', onVis)
    }
  }, [ms, enabled])
}

/** True when the viewport is under the mobile breakpoint. */
export function useIsMobile(breakpoint = 768) {
  const q = `(max-width: ${breakpoint - 1}px)`
  const [m, setM] = useState(() => (typeof window !== 'undefined' ? window.matchMedia(q).matches : false))
  useEffect(() => {
    const mq = window.matchMedia(q)
    const on = () => setM(mq.matches)
    mq.addEventListener('change', on)
    on()
    return () => mq.removeEventListener('change', on)
  }, [q])
  return m
}

export function useDocumentTitle(title: string | null) {
  useEffect(() => {
    document.title = title ? `${title} · Loop` : 'Loop'
  }, [title])
}
