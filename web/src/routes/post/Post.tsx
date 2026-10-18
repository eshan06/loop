import { useCallback, useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { createListing, getMeetupSpots, scan } from '../../api/endpoints'
import type { ListingInput, MeetupSpot, Photo, PhotoKind, ScanResult } from '../../api/types'
import { CameraIcon } from '../../components/Icons'
import { LIMITS } from '../../lib/constants'
import { errMsg, useAsync, useDocumentTitle } from '../../lib/hooks'
import { resizeToJpeg } from '../../lib/image'
import { ListingForm, type FormValues } from './ListingForm'
import { PhotoManager } from './PhotoManager'

type ScanKind = Extract<PhotoKind, 'front' | 'back' | 'label' | 'other'>
const KIND_LABEL: Record<ScanKind, string> = { front: 'Front', back: 'Back', label: 'Label', other: 'Other' }
const DEFAULT_KINDS: ScanKind[] = ['front', 'back', 'label']
const READING = ['Reading the label…', 'Checking the fabric…', 'Spotting the brand…', 'Writing it up…']

interface Shot {
  id: number
  blob: Blob
  preview: string
  kind: ScanKind
  kindTouched: boolean
}

let shotId = 1

export default function Post() {
  useDocumentTitle('Post an item')
  const nav = useNavigate()
  const [step, setStep] = useState<'photos' | 'scanning' | 'review'>('photos')
  const [shots, setShots] = useState<Shot[]>([])
  const [result, setResult] = useState<ScanResult | null>(null)
  const [photos, setPhotos] = useState<Photo[]>([])
  const [error, setError] = useState<string | null>(null)

  // Revoke object URLs we created for the previews.
  const shotsRef = useRef<Shot[]>([])
  shotsRef.current = shots
  useEffect(() => () => shotsRef.current.forEach((s) => URL.revokeObjectURL(s.preview)), [])

  const spots = useAsync(() => getMeetupSpots(), [])

  async function runScan() {
    setError(null)
    setStep('scanning')
    try {
      const res = await scan(shots.map((s) => s.blob), shots.map((s) => s.kind))
      setResult(res)
      setPhotos(res.photos)
      setStep('review')
    } catch (e) {
      setError(errMsg(e))
      setStep('photos')
    }
  }

  return (
    <div className="page-narrow-wide">
      <div className="page-head">
        <div>
          <h1>Post an item</h1>
          <p className="muted">{step === 'review' ? 'Check what the AI wrote, pick how to share it, and post.' : 'Add up to three photos. We\'ll write the listing for you.'}</p>
        </div>
        <ol className="steps" aria-label="Steps">
          {['Photos', 'Reading', 'Review'].map((s, i) => {
            const cur = ['photos', 'scanning', 'review'].indexOf(step)
            return <li key={s} className={i === cur ? 'on' : i < cur ? 'done' : ''} aria-current={i === cur ? 'step' : undefined}>{s}</li>
          })}
        </ol>
      </div>

      {step === 'photos' && <PhotoStep shots={shots} setShots={setShots} error={error} onContinue={runScan} />}
      {step === 'scanning' && <Scanning shots={shots} />}
      {step === 'review' && result && (
        <Review
          result={result}
          photos={photos}
          setPhotos={setPhotos}
          spots={spots.data?.items ?? null}
          spotsError={spots.error}
          reloadSpots={spots.reload}
          onBack={() => setStep('photos')}
          onPosted={(id) => nav('/feed', { state: { justPosted: id } })}
        />
      )}
    </div>
  )
}

// ---------------------------------------------------------------- step 1

function PhotoStep({ shots, setShots, error, onContinue }: {
  shots: Shot[]; setShots: React.Dispatch<React.SetStateAction<Shot[]>>; error: string | null; onContinue: () => void
}) {
  const input = useRef<HTMLInputElement>(null)
  const cam = useRef<HTMLInputElement>(null)
  const [drag, setDrag] = useState(false)
  const [busy, setBusy] = useState(false)
  const [localError, setLocalError] = useState<string | null>(null)
  const room = LIMITS.scanPhotos - shots.length

  const addFiles = useCallback(async (files: File[]) => {
    const imgs = files.filter((f) => f.type.startsWith('image/') || /\.(heic|heif|jpe?g|png|webp)$/i.test(f.name))
    if (!imgs.length) return
    setBusy(true)
    setLocalError(null)
    const added: Shot[] = []
    let failed = false
    for (const f of imgs) {
      try {
        const blob = await resizeToJpeg(f)
        added.push({ id: shotId++, blob, preview: URL.createObjectURL(blob), kind: 'other', kindTouched: false })
      } catch (e) {
        failed = true
        setLocalError(errMsg(e))
      }
    }
    setShots((cur) => {
      const space = LIMITS.scanPhotos - cur.length
      const take = added.slice(0, Math.max(0, space))
      added.slice(Math.max(0, space)).forEach((s) => URL.revokeObjectURL(s.preview))
      if (added.length > space && !failed) setLocalError(`You can add up to ${LIMITS.scanPhotos} photos for the scan. Add more after it reads your item.`)
      return relabel([...cur, ...take])
    })
    setBusy(false)
  }, [setShots])

  // Paste an image from the clipboard anywhere on the page.
  useEffect(() => {
    const onPaste = (e: ClipboardEvent) => {
      const files = Array.from(e.clipboardData?.files ?? [])
      if (files.length) {
        e.preventDefault()
        addFiles(files)
      }
    }
    document.addEventListener('paste', onPaste)
    return () => document.removeEventListener('paste', onPaste)
  }, [addFiles])

  function relabel(list: Shot[]): Shot[] {
    return list.map((s, i) => (s.kindTouched ? s : { ...s, kind: DEFAULT_KINDS[i] ?? 'other' }))
  }
  const remove = (id: number) => setShots((cur) => {
    const gone = cur.find((s) => s.id === id)
    if (gone) URL.revokeObjectURL(gone.preview)
    return relabel(cur.filter((s) => s.id !== id))
  })
  const move = (i: number, d: number) => setShots((cur) => {
    const j = i + d
    if (j < 0 || j >= cur.length) return cur
    const n = [...cur]
    ;[n[i], n[j]] = [n[j], n[i]]
    return relabel(n)
  })
  const setKind = (id: number, kind: ScanKind) => setShots((cur) => cur.map((s) => (s.id === id ? { ...s, kind, kindTouched: true } : s)))

  return (
    <div className="post-step">
      {room > 0 && (
        <div
          className={`dropzone${drag ? ' dropzone-over' : ''}`}
          onDragOver={(e) => { e.preventDefault(); setDrag(true) }}
          onDragLeave={() => setDrag(false)}
          onDrop={(e) => { e.preventDefault(); setDrag(false); addFiles(Array.from(e.dataTransfer.files)) }}
        >
          <CameraIcon width={34} height={34} />
          <p className="dropzone-title">{shots.length ? 'Add more photos' : 'Drag photos here'}</p>
          <p className="muted small">or paste one, or</p>
          <div className="dropzone-actions">
            <button type="button" className="btn btn-primary btn-small" onClick={() => input.current?.click()} disabled={busy}>Choose photos</button>
            <button type="button" className="btn btn-ghost btn-small only-mobile-inline" onClick={() => cam.current?.click()} disabled={busy}>Take a photo</button>
          </div>
          <p className="muted small">Front, back and the tag work best. Up to {LIMITS.scanPhotos}.</p>
          <input ref={input} type="file" accept="image/*" multiple hidden onChange={(e) => { addFiles(Array.from(e.target.files ?? [])); e.target.value = '' }} />
          <input ref={cam} type="file" accept="image/*" capture="environment" hidden onChange={(e) => { addFiles(Array.from(e.target.files ?? [])); e.target.value = '' }} />
        </div>
      )}

      {busy && <p className="muted small" role="status">Getting your photos ready…</p>}
      {(localError || error) && <p className="form-error" role="alert">{localError ?? error}</p>}

      {shots.length > 0 && (
        <ul className="shots">
          {shots.map((s, i) => (
            <li key={s.id} className="shot">
              <div className="shot-photo"><img src={s.preview} alt={`${KIND_LABEL[s.kind]} photo`} /></div>
              <div className="shot-controls">
                <select className="select" value={s.kind} onChange={(e) => setKind(s.id, e.target.value as ScanKind)} aria-label={`Label for photo ${i + 1}`}>
                  {(Object.keys(KIND_LABEL) as ScanKind[]).map((k) => <option key={k} value={k}>{KIND_LABEL[k]}</option>)}
                </select>
                <div className="shot-btns">
                  <button type="button" className="icon-btn" onClick={() => move(i, -1)} disabled={i === 0} aria-label={`Move photo ${i + 1} earlier`}>←</button>
                  <button type="button" className="icon-btn" onClick={() => move(i, 1)} disabled={i === shots.length - 1} aria-label={`Move photo ${i + 1} later`}>→</button>
                  <button type="button" className="icon-btn" onClick={() => remove(s.id)} aria-label={`Remove photo ${i + 1}`}>×</button>
                </div>
              </div>
            </li>
          ))}
        </ul>
      )}

      <div className="form-actions">
        <button className="btn btn-lime btn-large" disabled={!shots.length || busy} onClick={onContinue}>Continue</button>
      </div>
    </div>
  )
}

// ---------------------------------------------------------------- step 2

function Scanning({ shots }: { shots: Shot[] }) {
  const [i, setI] = useState(0)
  useEffect(() => {
    const t = window.setInterval(() => setI((n) => (n + 1) % READING.length), 1600)
    return () => window.clearInterval(t)
  }, [])
  return (
    <div className="scanning" role="status" aria-live="polite">
      <div className="scan-photos">
        {shots.map((s) => (
          <div key={s.id} className="scan-photo"><img src={s.preview} alt="" /><span className="scan-shimmer" /></div>
        ))}
      </div>
      <p className="scan-text">{READING[i]}</p>
      <p className="muted small">This usually takes a few seconds.</p>
    </div>
  )
}

// ---------------------------------------------------------------- step 3

function toValues(r: ScanResult): { values: FormValues; ai: (keyof FormValues)[] } {
  const d = r.draft
  const values: FormValues = {
    title: d.title ?? '', category: d.category ?? '', size: d.size ?? '', color: d.color ?? '', brand: d.brand ?? '',
    condition: d.condition ?? '', condition_note: d.condition_note ?? '', description: d.description ?? '', tags: d.tags ?? [],
    share_type: '', meetup_spot_id: '',
  }
  const ai: (keyof FormValues)[] = []
  if (r.source !== 'none') {
    for (const k of ['title', 'category', 'size', 'color', 'brand', 'condition', 'condition_note', 'description'] as const) if (values[k]) ai.push(k)
    if (values.tags.length) ai.push('tags')
  }
  return { values, ai }
}

function Review({ result, photos, setPhotos, spots, spotsError, reloadSpots, onBack, onPosted }: {
  result: ScanResult
  photos: Photo[]
  setPhotos: (p: Photo[]) => void
  spots: MeetupSpot[] | null
  spotsError: Error | null
  reloadSpots: () => void
  onBack: () => void
  onPosted: (id: number) => void
}) {
  const [{ values, ai }] = useState(() => toValues(result))
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function submit(input: ListingInput) {
    setBusy(true)
    setError(null)
    try {
      const l = await createListing(input)
      onPosted(l.id)
    } catch (e) {
      setError(errMsg(e))
      setBusy(false)
    }
  }

  return (
    <>
      {result.source === 'none' ? (
        <p className="notice">We couldn't read this one. Fill it in below.</p>
      ) : (
        <p className="notice notice-ai">Filled in by AI, check it over. <span className="muted">The marked fields are its guesses.</span></p>
      )}
      {spotsError ? (
        <div className="form-error">Couldn't load meetup spots. <button className="link-btn" onClick={reloadSpots}>Try again</button></div>
      ) : !spots ? (
        <div className="state state-compact"><span className="spinner" /></div>
      ) : (
        <ListingForm
          initial={values}
          aiFields={ai}
          spots={spots}
          photos={photos}
          submitLabel="Post"
          busy={busy}
          error={error}
          aside={<PhotoManager photos={photos} onChange={setPhotos} />}
          onSubmit={submit}
          onCancel={onBack}
        />
      )}
    </>
  )
}
