import { useCallback, useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { ApiError } from '../../api/client'
import { getRequest, requestAction } from '../../api/endpoints'
import type { LoopRequest } from '../../api/types'
import { useUnread } from '../../auth/UnreadContext'
import { Avatar } from '../../components/Avatar'
import { ShareBadge, StatusPill } from '../../components/Badges'
import { BackIcon } from '../../components/Icons'
import { ErrorState, Spinner } from '../../components/States'
import { useToast } from '../../components/Toast'
import { media } from '../../api/client'
import { displayName, firstName, timeAgo } from '../../lib/format'
import { errMsg } from '../../lib/hooks'
import { Celebration } from './Celebration'
import { Chat } from './Chat'

interface Props {
  requestId: number
  meId: number
  backTo: string
  /** Tell the list that this request changed so it can refetch. */
  onChanged: (r: LoopRequest) => void
}

export function RequestPane({ requestId, meId, backTo, onChanged }: Props) {
  const [req, setReq] = useState<LoopRequest | null>(null)
  const [error, setError] = useState<Error | null>(null)
  const [busy, setBusy] = useState<string | null>(null)
  const [justCompleted, setJustCompleted] = useState(false)
  const toast = useToast()
  const { refresh: refreshUnread } = useUnread()
  const statusRef = useRef<string | null>(null)

  const apply = useCallback((r: LoopRequest) => {
    const prev = statusRef.current
    statusRef.current = r.status
    setReq(r)
    if (prev && prev !== r.status) {
      onChanged(r)
      if (r.status === 'completed') setJustCompleted(true)
    }
  }, [onChanged])

  const load = useCallback(() => {
    setError(null)
    setReq(null)
    statusRef.current = null
    setJustCompleted(false)
    getRequest(requestId)
      .then((r) => {
        statusRef.current = r.status
        setReq(r)
        onChanged(r)
      })
      .catch((e) => setError(e))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [requestId])
  useEffect(load, [load])

  // Each chat poll also re-reads the request, so we notice the other person completing or cancelling.
  const poll = useCallback(() => {
    getRequest(requestId).then(apply).catch(() => {})
  }, [requestId, apply])

  async function act(action: 'accept' | 'decline' | 'complete' | 'cancel') {
    setBusy(action)
    try {
      const r = await requestAction(requestId, action)
      apply(r)
      onChanged(r)
      refreshUnread()
      if (action === 'complete') setJustCompleted(true)
    } catch (e) {
      toast(errMsg(e), 'error')
      // state may have moved under us (the other side acted first); re-read
      getRequest(requestId).then(apply).catch(() => {})
    } finally {
      setBusy(null)
    }
  }

  if (error instanceof ApiError && (error.status === 404 || error.status === 403))
    return (
      <div className="pane-empty">
        <p className="state-title">We couldn't find that request.</p>
        <Link className="btn btn-ghost" to={backTo}>Back to the inbox</Link>
      </div>
    )
  if (error) return <ErrorState error={error} onRetry={load} />
  if (!req) return <div className="pane-empty"><Spinner /></div>

  const iAmOwner = req.owner.id === meId
  const other = iAmOwner ? req.requester : req.owner
  const photo = media(req.listing.photo_url)

  return (
    <div className="pane">
      <header className="pane-head">
        <Link to={backTo} className="icon-btn pane-back" aria-label="Back to requests"><BackIcon /></Link>
        <Link to={`/item/${req.listing.id}`} className="pane-listing">
          {photo && <img src={photo} alt="" />}
          <span>
            <strong>{req.listing.title}</strong>
            <span className="pane-sub"><ShareBadge type={req.listing.share_type} /> <StatusPill status={req.status} /></span>
          </span>
        </Link>
        <div className="pane-other">
          <Avatar name={other.name} url={other.avatar_url} size={32} />
          <span className="small"><strong>{displayName(other.name)}</strong><br /><span className="muted">{other.dorm ?? (iAmOwner ? 'Requester' : 'Owner')}</span></span>
        </div>
      </header>

      {req.status === 'pending' && (
        <div className="pane-body">
          <div className="req-note">
            <p className="muted small">{iAmOwner ? `${firstName(other.name)} asked ${timeAgo(req.created_at)}` : `You asked ${timeAgo(req.created_at)}`}</p>
            <p>{req.note ? `“${req.note}”` : <span className="muted">No note.</span>}</p>
          </div>
          {iAmOwner ? (
            <div className="actions">
              <button className="btn btn-primary" onClick={() => act('accept')} disabled={!!busy}>{busy === 'accept' ? 'Accepting…' : 'Accept'}</button>
              <button className="btn btn-ghost" onClick={() => act('decline')} disabled={!!busy}>{busy === 'decline' ? 'Declining…' : 'Decline'}</button>
            </div>
          ) : (
            <div className="actions">
              <p className="muted">Waiting for {firstName(other.name)}…</p>
              <button className="btn btn-ghost" onClick={() => act('cancel')} disabled={!!busy}>{busy === 'cancel' ? 'Cancelling…' : 'Cancel request'}</button>
            </div>
          )}
        </div>
      )}

      {req.status === 'accepted' && (
        <>
          <div className="pane-toolbar">
            <span className="muted small">Agree a time and place in the chat. Mark it exchanged when it's done.</span>
            <span className="pane-toolbar-btns">
              <button className="btn btn-lime btn-small" onClick={() => act('complete')} disabled={!!busy}>{busy === 'complete' ? 'Saving…' : 'Mark exchanged'}</button>
              {!iAmOwner && <button className="btn btn-ghost btn-small" onClick={() => act('cancel')} disabled={!!busy}>Cancel</button>}
            </span>
          </div>
          <Chat requestId={req.id} meId={meId} live onPoll={poll} />
        </>
      )}

      {req.status === 'completed' && (
        <div className="pane-scroll">
          <Celebration key={justCompleted ? 'fresh' : 'old'} listingId={req.listing.id} />
          <p className="pane-history-title muted small">Chat history</p>
          <Chat requestId={req.id} meId={meId} live={false} onPoll={() => {}} />
        </div>
      )}

      {(req.status === 'declined' || req.status === 'cancelled') && (
        <div className="pane-body">
          <p className="req-note">
            {req.status === 'declined' ? (iAmOwner ? 'You declined this request.' : `${firstName(other.name)} declined this request.`) : 'This request was cancelled.'}
          </p>
          <Chat requestId={req.id} meId={meId} live={false} onPoll={() => {}} />
        </div>
      )}
    </div>
  )
}
