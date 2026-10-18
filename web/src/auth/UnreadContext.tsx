import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import { useLocation } from 'react-router-dom'
import { getUnread } from '../api/endpoints'
import type { Unread } from '../api/types'
import { useVisibleInterval } from '../lib/hooks'

interface UnreadValue {
  unread: Unread
  refresh: () => void
}

const ZERO: Unread = { notifications: 0, messages: 0, incoming_requests: 0 }
const Ctx = createContext<UnreadValue>({ unread: ZERO, refresh: () => {} })

/** Badge counts from GET /me/unread: on every route change and every 15 s while the tab is visible. */
export function UnreadProvider({ children }: { children: ReactNode }) {
  const [unread, setUnread] = useState<Unread>(ZERO)
  const { pathname } = useLocation()

  const refresh = useCallback(() => {
    getUnread()
      .then(setUnread)
      .catch(() => {
        /* badges are best-effort; a failed poll keeps the old counts */
      })
  }, [])

  useEffect(refresh, [pathname, refresh])
  useVisibleInterval(refresh, 15000)

  const value = useMemo(() => ({ unread, refresh }), [unread, refresh])
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export const useUnread = () => useContext(Ctx)
