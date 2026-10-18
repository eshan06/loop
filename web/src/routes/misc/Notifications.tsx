import { useNavigate } from 'react-router-dom'
import { getNotifications, markNotificationsRead } from '../../api/endpoints'
import type { LoopNotification } from '../../api/types'
import { useUnread } from '../../auth/UnreadContext'
import { NotificationRow, notificationTarget } from '../../components/NotificationItem'
import { EmptyState, ErrorState, Spinner } from '../../components/States'
import { useDocumentTitle, usePaged } from '../../lib/hooks'

export default function Notifications() {
  useDocumentTitle('Notifications')
  const list = usePaged((offset) => getNotifications(offset), [])
  const { refresh, unread } = useUnread()
  const nav = useNavigate()

  function open(n: LoopNotification) {
    if (!n.read) markNotificationsRead({ ids: [n.id] }).then(refresh).catch(() => {})
    nav(notificationTarget(n))
  }
  async function markAll() {
    await markNotificationsRead({ all: true }).catch(() => {})
    list.setItems((cur) => cur.map((n) => ({ ...n, read: true })))
    refresh()
  }

  return (
    <div className="page-narrow">
      <div className="page-head">
        <h1>Notifications</h1>
        <button className="btn btn-ghost btn-small" onClick={markAll} disabled={!unread.notifications}>Mark all read</button>
      </div>
      {list.error ? (
        <ErrorState error={list.error} onRetry={list.reload} />
      ) : list.loading ? (
        <div className="state"><Spinner /></div>
      ) : list.items.length === 0 ? (
        <EmptyState title="You're all caught up" body="Requests, messages and badges will show up here." />
      ) : (
        <div className="notif-list">
          {list.items.map((n) => <NotificationRow key={n.id} n={n} onClick={() => open(n)} />)}
          {list.hasMore && <div className="load-more"><button className="btn btn-ghost" onClick={list.loadMore} disabled={list.loadingMore}>{list.loadingMore ? 'Loading…' : 'Load more'}</button></div>}
        </div>
      )}
    </div>
  )
}
