import { useCallback, useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { ApiError } from '../../api/client'
import {
  createRequest, deleteListing, getListing, getSimilar, getStyle, reportListing, requestAction,
} from '../../api/endpoints'
import type { Listing, StyleIdea } from '../../api/types'
import { Avatar } from '../../components/Avatar'
import { ShareBadge, Tag } from '../../components/Badges'
import { Dialog } from '../../components/Dialog'
import { MoreIcon, SparkIcon } from '../../components/Icons'
import { ListingCard } from '../../components/ListingCard'
import { SaveButton } from '../../components/SaveButton'
import { ErrorState, FullLoading, NotFound, Spinner } from '../../components/States'
import { useToast } from '../../components/Toast'
import { categoryLabel, conditionLabel, LIMITS } from '../../lib/constants'
import { displayName, kg } from '../../lib/format'
import { errMsg, useAsync, useDocumentTitle } from '../../lib/hooks'
import { Gallery } from './Gallery'

export default function ItemDetail() {
  const { id } = useParams()
  const { data, setData, error, loading, reload } = useAsync(() => getListing(id!), [id])
  useDocumentTitle(data?.title ?? null)

  if (loading && !data) return <FullLoading />
  if (error instanceof ApiError && (error.status === 404 || error.status === 403)) return <NotFound />
  if (error) return <ErrorState error={error} onRetry={reload} />
  if (!data) return null
  return <Detail key={data.id} listing={data} onChange={setData} />
}

function Detail({ listing: l, onChange }: { listing: Listing; onChange: (l: Listing) => void }) {
  const nav = useNavigate()
  const toast = useToast()
  const [dialog, setDialog] = useState<null | 'request' | 'delete' | 'style' | 'report'>(null)
  const [menu, setMenu] = useState(false)
  const close = () => setDialog(null)
  const hasSpot = !!l.meetup_spot

  const similar = useAsync(() => getSimilar(l.id), [l.id])

  async function cancelRequest() {
    if (!l.my_request_id) return
    try {
      await requestAction(l.my_request_id, 'cancel')
      onChange({ ...l, my_request_status: 'cancelled', my_request_id: null })
      toast('Request cancelled.')
    } catch (e) {
      toast(errMsg(e), 'error')
    }
  }

  const editable = l.is_mine && l.status !== 'completed'

  return (
    <div className="item">
      <div className="item-media">
        <Gallery photos={l.photos} title={l.title} />
      </div>

      <div className="item-info">
        <div className="item-top">
          <div className="item-badges">
            <ShareBadge type={l.share_type} />
            {l.is_mine && <Tag lime>Yours</Tag>}
            {l.status === 'hidden' && <Tag>Hidden after reports</Tag>}
            {l.status === 'pending' && <Tag>Exchange in progress</Tag>}
            {l.status === 'completed' && <Tag>Exchanged</Tag>}
          </div>
          <div className="item-tools">
            {!l.is_mine && <SaveButton listingId={l.id} saved={l.saved_by_me} onChange={(s) => onChange({ ...l, saved_by_me: s })} className="heart-plain" />}
            {!l.is_mine && (
              <div className="popwrap">
                <button className="icon-btn" aria-label="More" aria-expanded={menu} onClick={() => setMenu((m) => !m)}><MoreIcon /></button>
                {menu && (
                  <div className="popover popover-menu" role="menu" onMouseLeave={() => setMenu(false)}>
                    <button role="menuitem" className="menu-item" onClick={() => { setMenu(false); setDialog('report') }}>Report this listing</button>
                  </div>
                )}
              </div>
            )}
          </div>
        </div>

        <h1>{l.title}</h1>

        <dl className="facts">
          <div><dt>Size</dt><dd>{l.size ?? '—'}</dd></div>
          <div><dt>Condition</dt><dd>{conditionLabel(l.condition)}</dd></div>
          <div><dt>Category</dt><dd>{categoryLabel(l.category)}</dd></div>
          {l.brand && <div><dt>Brand</dt><dd>{l.brand}</dd></div>}
          {l.color && <div><dt>Color</dt><dd>{l.color}</dd></div>}
          <div><dt>Meetup</dt><dd>{hasSpot ? l.meetup_spot!.name : 'Ask the owner'}</dd></div>
        </dl>
        {l.condition_note && <p className="cond-note">“{l.condition_note}”</p>}
        {l.description && <p className="item-desc">{l.description}</p>}
        {l.tags.length > 0 && (
          <ul className="tag-row" aria-label="Tags">
            {l.tags.map((t) => (
              <li key={t}><Link className="chip-link" to={`/feed?q=${encodeURIComponent(t)}`}>{t}</Link></li>
            ))}
          </ul>
        )}
        <p className="impact-line"><span className="leaf" aria-hidden>↻</span> Keeps {kg(l.impact.textile_kg)} kg of textile out of landfill.</p>

        <Actions
          l={l}
          onRequest={() => setDialog('request')}
          onDelete={() => setDialog('delete')}
          onCancel={cancelRequest}
          onChat={() => nav(`/inbox/${l.my_request_id}`)}
          onEdit={() => nav(`/item/${l.id}/edit`)}
          editable={editable}
        />

        <button className="btn btn-ghost style-btn" onClick={() => setDialog('style')}>
          <SparkIcon width={18} height={18} /> Style it
        </button>

        <div className="owner-card">
          <Avatar name={l.owner.name} url={l.owner.avatar_url} size={48} />
          <div>
            <strong>{displayName(l.owner.name)}</strong>
            <p className="muted small">{[l.owner.dorm, `${l.owner.items_shared} ${l.owner.items_shared === 1 ? 'item' : 'items'} shared`].filter(Boolean).join(' · ')}</p>
          </div>
        </div>
      </div>

      {similar.data && similar.data.items.length > 0 && (
        <section className="similar" aria-labelledby="similar-h">
          <h2 id="similar-h">Similar items</h2>
          <div className="similar-row">
            {similar.data.items.map((s) => <ListingCard key={s.id} listing={s} />)}
          </div>
        </section>
      )}

      <RequestDialog open={dialog === 'request'} listing={l} onClose={close} onSent={(rid) => {
        onChange({ ...l, my_request_status: 'pending', my_request_id: rid })
        toast('Request sent.')
        close()
      }} onAlready={() => { onChange({ ...l, my_request_status: 'pending' }); close() }} />
      <DeleteDialog open={dialog === 'delete'} listing={l} onClose={close} onDeleted={() => { toast('Listing deleted.'); nav('/profile', { replace: true }) }} />
      <StyleDialog open={dialog === 'style'} listing={l} onClose={close} />
      <ReportDialog open={dialog === 'report'} listing={l} onClose={close} />
    </div>
  )
}

function Actions({ l, onRequest, onDelete, onCancel, onChat, onEdit, editable }: {
  l: Listing
  onRequest: () => void
  onDelete: () => void
  onCancel: () => void
  onChat: () => void
  onEdit: () => void
  editable: boolean
}) {
  if (l.is_mine) {
    if (!editable) return <div className="actions"><button className="btn btn-ghost btn-large" disabled>Completed listings can't be changed</button></div>
    return (
      <div className="actions">
        <button className="btn btn-primary btn-large" onClick={onEdit}>Edit</button>
        <button className="btn btn-danger btn-large" onClick={onDelete}>Delete</button>
        {l.pending_request_count > 0 && <Link className="btn btn-ghost btn-large" to="/inbox?role=incoming">{l.pending_request_count} {l.pending_request_count === 1 ? 'request' : 'requests'}</Link>}
        {l.status === 'pending' && l.accepted_request_id && <Link className="btn btn-ghost btn-large" to={`/inbox/${l.accepted_request_id}`}>Open chat</Link>}
      </div>
    )
  }
  if (l.my_request_status === 'pending') {
    return (
      <div className="actions">
        <button className="btn btn-primary btn-large" disabled>Requested</button>
        <button className="btn btn-ghost btn-large" onClick={onCancel}>Cancel request</button>
      </div>
    )
  }
  if (l.my_request_status === 'accepted') {
    return <div className="actions"><button className="btn btn-lime btn-large" onClick={onChat}>Open chat</button></div>
  }
  if (l.status !== 'active') {
    return <div className="actions"><button className="btn btn-ghost btn-large" disabled>No longer available</button></div>
  }
  return <div className="actions"><button className="btn btn-primary btn-large" onClick={onRequest}>Request</button></div>
}

function RequestDialog({ open, listing, onClose, onSent, onAlready }: {
  open: boolean; listing: Listing; onClose: () => void; onSent: (requestId: number) => void; onAlready: () => void
}) {
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function send() {
    setBusy(true)
    setError(null)
    try {
      const r = await createRequest(listing.id, note.trim())
      onSent(r.id)
    } catch (e) {
      if (e instanceof ApiError && e.code === 'already_requested') return onAlready()
      setError(errMsg(e))
    } finally {
      setBusy(false)
    }
  }
  const verb = listing.share_type === 'swap' ? 'swap' : listing.share_type === 'free' ? 'take this' : 'pick this up'
  return (
    <Dialog open={open} onClose={onClose} title={`Request this item`}>
      <p className="muted">Tell {displayName(listing.owner.name).split(' ')[0]} why you'd like to {verb}. {listing.share_type === 'swap' ? 'Mention what you could offer.' : ''}</p>
      <div className="field">
        <label htmlFor="req-note">Note (optional) <span className="field-count">{note.length}/{LIMITS.note}</span></label>
        <textarea id="req-note" className="textarea" maxLength={LIMITS.note} value={note} onChange={(e) => setNote(e.target.value)} placeholder="Would you swap for a fleece in size M?" autoFocus />
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
      <div className="dialog-actions">
        <button className="btn btn-ghost" onClick={onClose}>Cancel</button>
        <button className="btn btn-primary" onClick={send} disabled={busy}>{busy ? 'Sending…' : 'Send request'}</button>
      </div>
    </Dialog>
  )
}

function DeleteDialog({ open, listing, onClose, onDeleted }: { open: boolean; listing: Listing; onClose: () => void; onDeleted: () => void }) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  async function go() {
    setBusy(true)
    setError(null)
    try {
      await deleteListing(listing.id)
      onDeleted()
    } catch (e) {
      setError(errMsg(e))
      setBusy(false)
    }
  }
  return (
    <Dialog open={open} onClose={onClose} title="Delete this listing?" small>
      <p className="muted">“{listing.title}” will be removed{listing.status === 'pending' || listing.pending_request_count ? ', along with its requests and chats' : ''}. This can't be undone.</p>
      {error && <p className="form-error" role="alert">{error}</p>}
      <div className="dialog-actions">
        <button className="btn btn-ghost" onClick={onClose}>Keep it</button>
        <button className="btn btn-primary" style={{ background: 'var(--danger)' }} onClick={go} disabled={busy}>{busy ? 'Deleting…' : 'Delete'}</button>
      </div>
    </Dialog>
  )
}

function StyleDialog({ open, listing, onClose }: { open: boolean; listing: Listing; onClose: () => void }) {
  const [ideas, setIdeas] = useState<StyleIdea[] | null>(null)
  const [error, setError] = useState<Error | null>(null)

  const load = useCallback(() => {
    setError(null)
    setIdeas(null)
    getStyle(listing.id).then((r) => setIdeas(r.ideas)).catch((e) => setError(e))
  }, [listing.id])
  // Fetch the first time the dialog opens; the server caches ideas per listing.
  useEffect(() => {
    if (open && !ideas && !error) load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open])
  return (
    <Dialog open={open} onClose={onClose} title="Ways to wear it">
      {error ? <ErrorState compact error={error} onRetry={load} /> : !ideas ? (
        <div className="state state-compact"><Spinner /><p className="muted">Pulling a few looks together…</p></div>
      ) : (
        <div className="style-ideas">
          {ideas.map((i) => (
            <div key={i.title} className="style-card"><strong>{i.title}</strong><p className="muted">{i.description}</p></div>
          ))}
        </div>
      )}
    </Dialog>
  )
}

function ReportDialog({ open, listing, onClose }: { open: boolean; listing: Listing; onClose: () => void }) {
  const [reason, setReason] = useState('')
  const [busy, setBusy] = useState(false)
  const [done, setDone] = useState(false)
  const [error, setError] = useState<string | null>(null)
  async function send() {
    setBusy(true)
    setError(null)
    try {
      await reportListing(listing.id, reason.trim())
      setDone(true)
    } catch (e) {
      setError(errMsg(e))
    } finally {
      setBusy(false)
    }
  }
  return (
    <Dialog open={open} onClose={onClose} title="Report this listing" small>
      {done ? (
        <>
          <p>Thanks, we'll take a look.</p>
          <div className="dialog-actions"><button className="btn btn-primary" onClick={onClose}>Done</button></div>
        </>
      ) : (
        <>
          <div className="field">
            <label htmlFor="report-reason">Reason (optional) <span className="field-count">{reason.length}/{LIMITS.report}</span></label>
            <textarea id="report-reason" className="textarea" maxLength={LIMITS.report} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Not clothing, wrong category, something else…" />
          </div>
          {error && <p className="form-error" role="alert">{error}</p>}
          <div className="dialog-actions">
            <button className="btn btn-ghost" onClick={onClose}>Cancel</button>
            <button className="btn btn-primary" onClick={send} disabled={busy}>{busy ? 'Sending…' : 'Report'}</button>
          </div>
        </>
      )}
    </Dialog>
  )
}
