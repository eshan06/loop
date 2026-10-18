import { useCallback, useEffect, useRef, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { getNotifications, markNotificationsRead } from '../api/endpoints'
import type { LoopNotification } from '../api/types'
import { useUnread } from '../auth/UnreadContext'
import { BellIcon } from './Icons'
import { NotificationRow, notificationTarget } from './NotificationItem'
import { ErrorState, Spinner } from './States'

export function NotificationBell() {
  const { unread, refresh } = useUnread()
  const [open, setOpen] = useState(false)
  const [items, setItems] = useState<LoopNotification[] | null>(null)
  const [error, setError] = useState<Error | null>(null)
  const wrap = useRef<HTMLDivElement>(null)
  const nav = useNavigate()

  const load = useCallback(() => {
    setError(null)
    getNotifications(0, 8)
      .then((p) => setItems(p.items))
      .catch((e) => setError(e))
  }, [])

  useEffect(() => {
    if (open) load()
  }, [open, load])

  useEffect(() => {
    if (!open) return
    const onDoc = (e: MouseEvent) => {
      if (!wrap.current?.contains(e.target as Node)) setOpen(false)
    }
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false)
    document.addEventListener('mousedown', onDoc)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('mousedown', onDoc)
      document.removeEventListener('keydown', onKey)
    }
  }, [open])

  async function markAll() {
    try {
      await markNotificationsRead({ all: true })
      setItems((l) => l?.map((n) => ({ ...n, read: true })) ?? l)
      refresh()
    } catch {
      /* leave as is; the user can retry */
    }
  }

  function openOne(n: LoopNotification) {
    setOpen(false)
    if (!n.read) markNotificationsRead({ ids: [n.id] }).then(refresh).catch(() => {})
    nav(notificationTarget(n))
  }

  return (
    <div className="popwrap" ref={wrap}>
      <button
        className="icon-btn nav-icon"
        onClick={() => setOpen((o) => !o)}
        aria-label={`Notifications${unread.notifications ? `, ${unread.notifications} unread` : ''}`}
        aria-expanded={open}
      >
        <BellIcon />
        {unread.notifications > 0 && <span className="badge-count">{unread.notifications > 99 ? '99+' : unread.notifications}</span>}
      </button>
      {open && (
        <div className="popover popover-notifs" role="dialog" aria-label="Notifications">
          <div className="popover-head">
            <strong>Notifications</strong>
            <button className="link-btn" onClick={markAll} disabled={!unread.notifications}>
              Mark all read
            </button>
          </div>
          <div className="popover-scroll">
            {error ? (
              <ErrorState compact error={error} onRetry={load} />
            ) : !items ? (
              <div className="state state-compact"><Spinner /></div>
            ) : items.length === 0 ? (
              <p className="muted pad">Nothing yet. We'll tell you when someone requests or messages you.</p>
            ) : (
              items.map((n) => <NotificationRow key={n.id} n={n} onClick={() => openOne(n)} />)
            )}
          </div>
          <Link className="popover-foot" to="/notifications" onClick={() => setOpen(false)}>
            See all
          </Link>
        </div>
      )}
    </div>
  )
}
