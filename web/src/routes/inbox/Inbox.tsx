import { useCallback, useEffect, useRef, useState } from 'react'
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { getMyRequests } from '../../api/endpoints'
import type { LoopRequest } from '../../api/types'
import { useUser } from '../../auth/AuthContext'
import { useUnread } from '../../auth/UnreadContext'
import { Avatar } from '../../components/Avatar'
import { StatusPill, Tag } from '../../components/Badges'
import { EmptyState, ErrorState, Spinner } from '../../components/States'
import { media } from '../../api/client'
import { displayName, timeAgo } from '../../lib/format'
import { useDocumentTitle, useIsMobile, useVisibleInterval } from '../../lib/hooks'
import { RequestPane } from './RequestPane'

type Role = 'incoming' | 'outgoing'

export default function Inbox() {
  useDocumentTitle('Inbox')
  const me = useUser()
  const { requestId } = useParams()
  const [params] = useSearchParams()
  const nav = useNavigate()
  const isMobile = useIsMobile()
  const openId = requestId ? Number(requestId) : null
  const explicit = params.get('role')
  // Without ?role, follow the open request: incoming if I own the listing, else outgoing.
  const [derived, setDerived] = useState<Role | null>(null)
  const role: Role = explicit === 'incoming' || explicit === 'outgoing' ? explicit : derived ?? 'incoming'

  const [items, setItems] = useState<LoopRequest[] | null>(null)
  const [next, setNext] = useState<number | null>(null)
  const [error, setError] = useState<Error | null>(null)
  const [loadingMore, setLoadingMore] = useState(false)
  const roleRef = useRef(role)
  roleRef.current = role
  const { unread } = useUnread()

  // `silent` refreshes keep the current rows on screen (no spinner flash).
  const load = useCallback((silent = false) => {
    const r = roleRef.current
    if (!silent) { setItems(null); setError(null) }
    getMyRequests(r, 0, 50)
      .then((p) => {
        if (roleRef.current !== r) return
        setItems(p.items)
        setNext(p.next_offset)
        setError(null)
      })
      .catch((e) => { if (!silent && roleRef.current === r) setError(e) })
  }, [])
  useEffect(() => load(false), [role, load])
  useVisibleInterval(() => load(true), 10000)
  // New incoming requests or messages show up in the badge first; pull the list when they change.
  useEffect(() => load(true), [unread.messages, unread.incoming_requests, load])

  async function more() {
    if (next === null) return
    setLoadingMore(true)
    try {
      const p = await getMyRequests(role, next, 50)
      setItems((cur) => [...(cur ?? []), ...p.items.filter((x) => !(cur ?? []).some((c) => c.id === x.id))])
      setNext(p.next_offset)
    } finally {
      setLoadingMore(false)
    }
  }

  const onChanged = useCallback((r: LoopRequest) => {
    setDerived(r.owner.id === me.id ? 'incoming' : 'outgoing')
    load(true)
  }, [load, me.id])

  const backTo = `/inbox?role=${role}`
  const sorted = items
    ? [...items].sort((a, b) => {
        // Incoming pending rows sit at the top with a "New request" tag.
        const ap = role === 'incoming' && a.status === 'pending' ? 1 : 0
        const bp = role === 'incoming' && b.status === 'pending' ? 1 : 0
        return bp - ap || +new Date(b.updated_at) - +new Date(a.updated_at)
      })
    : null

  const showList = !isMobile || openId === null
  const showPane = !isMobile || openId !== null

  return (
    <div className={`inbox${openId ? ' inbox-open' : ''}`}>
      {showList && (
        <aside className="inbox-list" aria-label="Requests">
          <h1 className="inbox-title">Inbox</h1>
          <div className="tabs" role="tablist">
            {(['incoming', 'outgoing'] as Role[]).map((r) => (
              <button key={r} role="tab" aria-selected={role === r} className="tab" onClick={() => nav(`/inbox?role=${r}`)}>
                {r === 'incoming' ? 'Incoming' : 'Outgoing'}
                {r === 'incoming' && unread.incoming_requests > 0 && <span className="tab-count">{unread.incoming_requests}</span>}
              </button>
            ))}
          </div>
          <div className="inbox-rows">
            {error ? (
              <ErrorState compact error={error} onRetry={() => load(false)} />
            ) : !sorted ? (
              <div className="state state-compact"><Spinner /></div>
            ) : sorted.length === 0 ? (
              role === 'incoming' ? (
                <EmptyState title="No requests yet" body="When a classmate asks for one of your items, it shows up here." action={<Link className="btn btn-lime btn-small" to="/post">Post an item</Link>} />
              ) : (
                <EmptyState title="You haven't requested anything" body="Find something you like and send a request." action={<Link className="btn btn-primary btn-small" to="/feed">Browse the feed</Link>} />
              )
            ) : (
              <>
                {sorted.map((r) => {
                  const other = role === 'incoming' ? r.requester : r.owner
                  const photo = media(r.listing.photo_url)
                  return (
                    <Link key={r.id} to={`/inbox/${r.id}?role=${role}`} className={`row${r.id === openId ? ' row-on' : ''}`} aria-current={r.id === openId}>
                      {photo ? <img className="row-photo" src={photo} alt="" /> : <span className="row-photo skeleton" />}
                      <span className="row-main">
                        <span className="row-top">
                          <strong className="row-title">{r.listing.title}</strong>
                          <span className="row-time">{timeAgo(r.updated_at)}</span>
                        </span>
                        <span className="row-who"><Avatar name={other.name} url={other.avatar_url} size={18} /> {displayName(other.name)}</span>
                        <span className="row-bottom">
                          {role === 'incoming' && r.status === 'pending' && <Tag lime>New request</Tag>}
                          <StatusPill status={r.status} />
                          <span className="row-note">{r.note ? r.note.split('\n')[0] : ''}</span>
                        </span>
                      </span>
                      {r.unread_messages > 0 && <span className="unread-dot" aria-label={`${r.unread_messages} unread`}>{r.unread_messages}</span>}
                    </Link>
                  )
                })}
                {next !== null && <button className="btn btn-ghost btn-small row-more" onClick={more} disabled={loadingMore}>{loadingMore ? 'Loading…' : 'Load more'}</button>}
              </>
            )}
          </div>
        </aside>
      )}

      {showPane && (
        <section className="inbox-pane" aria-label="Conversation">
          {openId ? (
            <RequestPane key={openId} requestId={openId} meId={me.id} backTo={backTo} onChanged={onChanged} />
          ) : (
            <div className="pane-empty">
              <p className="state-title">Select a request</p>
              <p className="muted">Pick one on the left to see it and chat.</p>
            </div>
          )}
        </section>
      )}
    </div>
  )
}
