import { useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { getBadges, getImpactMe, getMe, getMyListings, requestAction } from '../../api/endpoints'
import type { Badge, Listing } from '../../api/types'
import { useAuth, useUser } from '../../auth/AuthContext'
import { Avatar } from '../../components/Avatar'
import { ListingCard } from '../../components/ListingCard'
import { CardSkeletons, EmptyState, ErrorState } from '../../components/States'
import { useToast } from '../../components/Toast'
import { displayName, formatDate, kg, n0 } from '../../lib/format'
import { errMsg, useAsync, useDocumentTitle, usePaged } from '../../lib/hooks'

export default function Profile() {
  useDocumentTitle('Profile')
  const user = useUser()
  const { setUser } = useAuth()
  const [params, setParams] = useSearchParams()
  const tab = params.get('tab') === 'completed' ? 'completed' : 'active'

  // Fresh counts (items shared) every time the profile opens.
  useEffect(() => {
    getMe().then(setUser).catch(() => {})
  }, [setUser])

  return (
    <div className="profile">
      <header className="profile-head">
        <Avatar name={user.name} url={user.avatar_url} size={96} />
        <div className="profile-who">
          <h1>{displayName(user.name)}</h1>
          <p className="muted">
            {[user.dorm, user.class_year ? `Class of ${user.class_year}` : null, user.campus.name].filter(Boolean).join(' · ')}
          </p>
          <p><strong>{user.items_shared}</strong> {user.items_shared === 1 ? 'item' : 'items'} shared</p>
        </div>
        <Link className="btn btn-ghost" to="/profile/edit">Edit profile</Link>
      </header>

      <ImpactSummary />
      <Badges />

      <section aria-labelledby="listings-h">
        <div className="page-head">
          <h2 id="listings-h">Your listings</h2>
          <div className="tabs tabs-inline" role="tablist">
            {(['active', 'completed'] as const).map((t) => (
              <button key={t} role="tab" aria-selected={tab === t} className="tab" onClick={() => setParams(t === 'active' ? {} : { tab: t })}>
                {t === 'active' ? 'Active' : 'Completed'}
              </button>
            ))}
          </div>
        </div>
        <MyListings key={tab} status={tab} />
      </section>
    </div>
  )
}

function ImpactSummary() {
  const { data } = useAsync(() => getImpactMe(), [])
  if (!data) return null
  return (
    <Link to="/impact" className="impact-strip" aria-label="Your impact">
      <div><strong>{kg(data.textile_kg)}</strong><span>kg textile</span></div>
      <div><strong>{n0(data.water_l)}</strong><span>L water</span></div>
      <div><strong>{kg(data.co2_kg)}</strong><span>kg CO₂</span></div>
      <span className="impact-more">Your impact →</span>
    </Link>
  )
}

function Badges() {
  const { data } = useAsync(() => getBadges(), [])
  if (!data) return null
  return (
    <section className="badges" aria-labelledby="badges-h">
      <h2 id="badges-h">Badges</h2>
      <ul className="badge-row">
        {data.items.map((b) => <BadgeCard key={b.id} b={b} />)}
      </ul>
    </section>
  )
}

function BadgeCard({ b }: { b: Badge }) {
  const earned = !!b.earned_at
  return (
    <li className={`badge ${earned ? 'badge-on' : 'badge-off'}`}>
      <span className="badge-medal" aria-hidden>{earned ? '✓' : ''}</span>
      <div>
        <strong>{b.name}</strong>
        <p className="muted small">{b.description}</p>
        <p className="small">{earned ? `Earned ${formatDate(b.earned_at!)}` : `${b.progress} of ${b.goal}`}</p>
      </div>
    </li>
  )
}

function MyListings({ status }: { status: 'active' | 'completed' }) {
  const list = usePaged((offset) => getMyListings(status, offset), [status])
  const toast = useToast()
  const [busy, setBusy] = useState<number | null>(null)

  async function complete(l: Listing) {
    if (!l.accepted_request_id) return
    setBusy(l.id)
    try {
      await requestAction(l.accepted_request_id, 'complete')
      toast('Marked as exchanged. Nice work.')
      list.reload()
    } catch (e) {
      toast(errMsg(e), 'error')
    } finally {
      setBusy(null)
    }
  }

  if (list.error) return <ErrorState error={list.error} onRetry={list.reload} />
  if (list.loading) return <div className="grid"><CardSkeletons count={5} /></div>
  if (!list.items.length)
    return status === 'active' ? (
      <EmptyState title="Nothing listed right now" body="Snap a few photos and we'll write the listing." action={<Link className="btn btn-lime" to="/post">Post an item</Link>} />
    ) : (
      <EmptyState title="No completed exchanges yet" body="Items you've swapped, given or donated end up here." />
    )

  return (
    <>
      <div className="grid">
        {list.items.map((l) => (
          <div key={l.id} className="own">
            <ListingCard listing={l} owner />
            {status === 'active' && (
              <div className="own-actions">
                {l.pending_request_count > 0 && <Link className="btn btn-primary btn-small" to="/inbox?role=incoming">See {l.pending_request_count === 1 ? 'request' : `${l.pending_request_count} requests`}</Link>}
                {l.status === 'pending' && l.accepted_request_id && (
                  <>
                    <button className="btn btn-lime btn-small" onClick={() => complete(l)} disabled={busy === l.id}>{busy === l.id ? 'Saving…' : 'Mark exchanged'}</button>
                    <Link className="btn btn-ghost btn-small" to={`/inbox/${l.accepted_request_id}?role=incoming`}>Open chat</Link>
                  </>
                )}
                {l.status === 'hidden' && <Link className="btn btn-ghost btn-small" to={`/item/${l.id}/edit`}>Edit</Link>}
              </div>
            )}
          </div>
        ))}
      </div>
      {list.hasMore && <div className="load-more"><button className="btn btn-ghost" onClick={list.loadMore} disabled={list.loadingMore}>{list.loadingMore ? 'Loading…' : 'Load more'}</button></div>}
    </>
  )
}
