import { getEvents } from '../../api/endpoints'
import type { CampusEvent } from '../../api/types'
import { Tag } from '../../components/Badges'
import { EmptyState, ErrorState, FullLoading } from '../../components/States'
import { formatDateTime } from '../../lib/format'
import { useAsync, useDocumentTitle } from '../../lib/hooks'

const KIND: Record<string, string> = { swap_day: 'Swap Day', donation_drive: 'Donation drive', repair_workshop: 'Repair workshop' }
const kindLabel = (k: string) => KIND[k] ?? KIND.swap_day

function EventCard({ e }: { e: CampusEvent }) {
  return (
    <article className="event">
      <div className="event-top">
        <Tag>{kindLabel(e.kind)}</Tag>
        {e.is_live && <Tag lime>Happening now</Tag>}
      </div>
      <h3>{e.title}</h3>
      {e.description && <p className="muted">{e.description}</p>}
      <p className="small"><strong>{formatDateTime(e.starts_at)}</strong> to {formatDateTime(e.ends_at)}</p>
      <p className="small muted">{e.location_name}</p>
    </article>
  )
}

export default function Events() {
  useDocumentTitle('Events')
  const { data, error, reload } = useAsync(() => getEvents(), [])
  if (error) return <ErrorState error={error} onRetry={reload} />
  if (!data) return <FullLoading />
  const groups: [string, CampusEvent[]][] = [
    ['Happening now', data.items.filter((e) => e.status === 'live')],
    ['Upcoming', data.items.filter((e) => e.status === 'upcoming')],
    ['Recently ended', data.items.filter((e) => e.status === 'ended')],
  ]
  const any = groups.some(([, l]) => l.length)
  return (
    <div className="page-narrow">
      <div className="page-head"><h1>Events</h1></div>
      {!any ? <EmptyState title="No events yet" body="Swap Days and donation drives on your campus will show up here." /> : groups.map(([title, list]) =>
        list.length ? (
          <section key={title} className="event-group">
            <h2>{title}</h2>
            <div className="event-list">{list.map((e) => <EventCard key={e.id} e={e} />)}</div>
          </section>
        ) : null,
      )}
    </div>
  )
}
