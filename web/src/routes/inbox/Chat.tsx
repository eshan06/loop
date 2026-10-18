import { useCallback, useEffect, useLayoutEffect, useRef, useState, type KeyboardEvent } from 'react'
import { getMessages, sendMessage } from '../../api/endpoints'
import type { Message } from '../../api/types'
import { useUnread } from '../../auth/UnreadContext'
import { SendIcon } from '../../components/Icons'
import { ErrorState, Spinner } from '../../components/States'
import { LIMITS } from '../../lib/constants'
import { formatTime } from '../../lib/format'
import { errMsg } from '../../lib/hooks'

interface Props {
  requestId: number
  meId: number
  /** Polling and the composer only while the request is accepted. */
  live: boolean
  /** Called with each poll so the pane can notice the other person completing or cancelling. */
  onPoll: () => void
}

const POLL_MS = 3000

export function Chat({ requestId, meId, live, onPoll }: Props) {
  const [messages, setMessages] = useState<Message[] | null>(null)
  const [error, setError] = useState<Error | null>(null)
  const [text, setText] = useState('')
  const [sending, setSending] = useState(false)
  const [sendError, setSendError] = useState<string | null>(null)
  const scroller = useRef<HTMLDivElement>(null)
  const stick = useRef(true)
  const lastId = useRef<number | undefined>(undefined)
  const { refresh: refreshUnread } = useUnread()
  const onPollRef = useRef(onPoll)
  onPollRef.current = onPoll

  const merge = useCallback((incoming: Message[]) => {
    if (!incoming.length) return
    setMessages((cur) => {
      const have = new Set((cur ?? []).map((m) => m.id))
      const add = incoming.filter((m) => !have.has(m.id))
      if (!add.length) return cur
      const next = [...(cur ?? []), ...add].sort((a, b) => a.id - b.id)
      lastId.current = next[next.length - 1].id
      return next
    })
  }, [])

  // Open: load the whole history (this marks it read).
  const load = useCallback(() => {
    setError(null)
    setMessages(null)
    lastId.current = undefined
    stick.current = true
    getMessages(requestId)
      .then((r) => {
        setMessages(r.items)
        lastId.current = r.items.length ? r.items[r.items.length - 1].id : undefined
        refreshUnread()
      })
      .catch((e) => setError(e))
  }, [requestId, refreshUnread])
  useEffect(load, [load])

  // Poll every 3 s while the chat is open and the tab is visible. Stops when the chat closes (unmount) or is hidden.
  useEffect(() => {
    if (!live || messages === null) return
    let timer: number | undefined
    let stopped = false
    const tick = async () => {
      if (document.visibilityState !== 'visible') return
      try {
        const r = await getMessages(requestId, lastId.current)
        if (stopped) return
        if (r.items.length) {
          merge(r.items)
          refreshUnread()
        }
        onPollRef.current()
      } catch {
        /* transient; next tick retries */
      }
    }
    const start = () => { if (timer === undefined) timer = window.setInterval(tick, POLL_MS) }
    const stop = () => { if (timer !== undefined) { window.clearInterval(timer); timer = undefined } }
    const vis = () => (document.visibilityState === 'visible' ? (tick(), start()) : stop())
    start()
    document.addEventListener('visibilitychange', vis)
    return () => {
      stopped = true
      stop()
      document.removeEventListener('visibilitychange', vis)
    }
  }, [live, messages === null, requestId, merge, refreshUnread])

  // Keep the newest message in view unless the reader scrolled up.
  useLayoutEffect(() => {
    const el = scroller.current
    if (el && stick.current) el.scrollTop = el.scrollHeight
  }, [messages])

  async function send() {
    const body = text.trim()
    if (!body || sending) return
    setSending(true)
    setSendError(null)
    try {
      const m = await sendMessage(requestId, body)
      stick.current = true
      merge([m])
      setText('')
    } catch (e) {
      setSendError(errMsg(e))
    } finally {
      setSending(false)
    }
  }

  function onKey(e: KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) {
      e.preventDefault()
      send()
    }
  }

  if (error) return <ErrorState error={error} onRetry={load} />
  if (!messages) return <div className="state"><Spinner /></div>

  return (
    <div className="chat">
      <div
        className="chat-scroll"
        ref={scroller}
        onScroll={(e) => {
          const el = e.currentTarget
          stick.current = el.scrollHeight - el.scrollTop - el.clientHeight < 80
        }}
        role="log"
        aria-live="polite"
        aria-label="Messages"
      >
        {messages.length === 0 && <p className="muted chat-empty">{live ? 'Say hi and pick a time to meet.' : 'No messages.'}</p>}
        {messages.map((m) => (
          <div key={m.id} className={`msg ${m.sender_id === meId ? 'msg-me' : 'msg-them'}`}>
            <p>{m.body}</p>
            <span className="msg-time">{formatTime(m.created_at)}</span>
          </div>
        ))}
      </div>
      {live && (
        <div className="composer">
          {sendError && <p className="field-error" role="alert">{sendError}</p>}
          <div className="composer-row">
            <textarea
              className="input composer-input"
              rows={1}
              value={text}
              maxLength={LIMITS.message}
              placeholder="Write a message"
              aria-label="Message"
              onChange={(e) => setText(e.target.value)}
              onKeyDown={onKey}
            />
            <button className="btn btn-primary btn-send" onClick={send} disabled={!text.trim() || sending} aria-label="Send">
              <SendIcon width={18} height={18} />
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
