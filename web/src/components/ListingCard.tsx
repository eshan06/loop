import { Link } from 'react-router-dom'
import { media } from '../api/client'
import type { Listing } from '../api/types'
import { ListingStatusPill, ShareBadge, Tag } from './Badges'
import { SaveButton } from './SaveButton'

interface Props {
  listing: Listing
  justPosted?: boolean
  /** Owner view (My listings): show request counts and hidden state. */
  owner?: boolean
  onSavedChange?: (saved: boolean) => void
  /** Items from another list (similar row) don't need the full overlay. */
  compact?: boolean
}

export function ListingCard({ listing: l, justPosted, owner, onSavedChange, compact }: Props) {
  const photo = media(l.photos[0]?.url)
  return (
    <article className={`card${justPosted ? ' card-fresh' : ''}`}>
      <Link to={`/item/${l.id}`} className="card-link" aria-label={`${l.title}, ${l.size ?? 'no size'}`}>
        <div className="card-photo">
          {photo ? <img src={photo} alt={l.title} loading="lazy" decoding="async" /> : <div className="skeleton" />}
          <div className="card-tags">
            {justPosted && <Tag lime>Just posted</Tag>}
            {l.is_mine && !owner && <Tag lime>Yours</Tag>}
            {owner && l.status === 'hidden' && <ListingStatusPill status="hidden" />}
            {owner && l.pending_request_count > 0 && <Tag ink>{l.pending_request_count} {l.pending_request_count === 1 ? 'request' : 'requests'}</Tag>}
          </div>
        </div>
        <div className="card-meta">
          <p className="card-title">{l.title}</p>
          <p className="card-sub">
            <span>{l.size ? l.size : l.category}</span>
            <ShareBadge type={l.share_type} />
          </p>
        </div>
      </Link>
      {!compact && !owner && <SaveButton listingId={l.id} saved={l.saved_by_me} onChange={onSavedChange} className="card-heart" />}
    </article>
  )
}
