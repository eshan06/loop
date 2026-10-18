import type { LoopNotification } from '../api/types'
import { timeAgo } from '../lib/format'

/** Where a notification leads: the request chat, or the profile for badges. */
export function notificationTarget(n: LoopNotification): string {
  if (n.type === 'badge_earned') return '/profile'
  if (n.request_id) return `/inbox/${n.request_id}`
  if (n.listing_id) return `/item/${n.listing_id}`
  return '/inbox'
}

export function NotificationRow({ n, onClick }: { n: LoopNotification; onClick: () => void }) {
  return (
    <button className={`notif${n.read ? '' : ' notif-unread'}`} onClick={onClick}>
      <span className="notif-dot" aria-hidden />
      <span className="notif-text">
        <span className="notif-title">{n.title}</span>
        {n.body && <span className="notif-body">{n.body}</span>}
      </span>
      <span className="notif-time">{timeAgo(n.created_at)}</span>
    </button>
  )
}
