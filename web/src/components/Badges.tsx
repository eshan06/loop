import type { ListingStatus, RequestStatus, ShareType } from '../api/types'
import { LISTING_STATUS_LABEL, REQUEST_STATUS_LABEL, shareLabel } from '../lib/constants'

/** Swap / Free / Donate: the neutral capsule, same as the iOS app. */
export function ShareBadge({ type }: { type: ShareType }) {
  return <span className="tag">{shareLabel(type)}</span>
}

export function Tag({ children, lime, ink }: { children: React.ReactNode; lime?: boolean; ink?: boolean }) {
  return <span className={`tag${lime ? ' tag-lime' : ''}${ink ? ' tag-ink' : ''}`}>{children}</span>
}

export function StatusPill({ status }: { status: RequestStatus }) {
  return <span className={`pill pill-${status}`}>{REQUEST_STATUS_LABEL[status]}</span>
}

export function ListingStatusPill({ status }: { status: ListingStatus }) {
  return <span className={`pill pill-l-${status}`}>{LISTING_STATUS_LABEL[status]}</span>
}
