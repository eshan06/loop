import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'

export function Spinner({ label = 'Loading' }: { label?: string }) {
  return <span className="spinner" role="status" aria-label={label} />
}

export function FullLoading() {
  return (
    <div className="center-fill">
      <Spinner />
    </div>
  )
}

export function ErrorState({ error, onRetry, compact }: { error: Error | string; onRetry?: () => void; compact?: boolean }) {
  const message = typeof error === 'string' ? error : error.message
  return (
    <div className={`state${compact ? ' state-compact' : ''}`} role="alert">
      <p className="state-title">Something went wrong</p>
      <p className="muted">{message}</p>
      {onRetry && (
        <button className="btn btn-ghost" onClick={onRetry}>
          Try again
        </button>
      )}
    </div>
  )
}

export function EmptyState({ title, body, action }: { title: string; body?: string; action?: ReactNode }) {
  return (
    <div className="state">
      <p className="state-title">{title}</p>
      {body && <p className="muted">{body}</p>}
      {action}
    </div>
  )
}

export function NotFound({ title = "This one's not here.", body = 'It may have been swapped already.' }: { title?: string; body?: string }) {
  return (
    <div className="state state-big">
      <p className="state-title">{title}</p>
      <p className="muted">{body}</p>
      <Link className="btn btn-primary" to="/feed">
        Back to the feed
      </Link>
    </div>
  )
}

export function CardSkeletons({ count = 10 }: { count?: number }) {
  return (
    <>
      {Array.from({ length: count }, (_, i) => (
        <div key={i} className="card card-skeleton" aria-hidden>
          <div className="card-photo skeleton" />
          <div className="skeleton skeleton-line" />
          <div className="skeleton skeleton-line short" />
        </div>
      ))}
    </>
  )
}
