import { useMemo, useState, type FormEvent, type ReactNode } from 'react'
import type { Category, Condition, ListingInput, MeetupSpot, Photo, ShareType } from '../../api/types'
import { CATEGORIES, CONDITIONS, LIMITS, SHARE_TYPES, sizesFor } from '../../lib/constants'
import { TagsInput } from './TagsInput'

export interface FormValues {
  title: string
  category: Category | ''
  size: string
  color: string
  brand: string
  condition: Condition | ''
  condition_note: string
  description: string
  tags: string[]
  share_type: ShareType | ''
  meetup_spot_id: number | ''
}

export const EMPTY_VALUES: FormValues = {
  title: '', category: '', size: '', color: '', brand: '', condition: '', condition_note: '', description: '', tags: [], share_type: '', meetup_spot_id: '',
}

type Key = keyof FormValues

interface Props {
  initial: FormValues
  /** Fields the AI filled in: subtly marked until the user edits them. */
  aiFields?: Key[]
  spots: MeetupSpot[]
  photos: Photo[]
  submitLabel: string
  busy: boolean
  error: string | null
  /** The photo manager and anything else that belongs beside the form. */
  aside?: ReactNode
  onSubmit: (input: ListingInput) => void
  onCancel?: () => void
}

/** The review form for /post and /item/:id/edit. */
export function ListingForm({ initial, aiFields = [], spots, photos, submitLabel, busy, error, aside, onSubmit, onCancel }: Props) {
  const [v, setV] = useState<FormValues>(initial)
  const [ai, setAi] = useState<Set<Key>>(new Set(aiFields))
  const [errs, setErrs] = useState<Partial<Record<Key | 'photos', string>>>({})

  const set = <K extends Key>(k: K, value: FormValues[K]) => {
    setV((p) => ({ ...p, [k]: value }))
    if (ai.has(k)) setAi((s) => { const n = new Set(s); n.delete(k); return n })
    if (errs[k]) setErrs((e) => ({ ...e, [k]: undefined }))
  }
  const mark = (k: Key) => (ai.has(k) ? ' ai-mark' : '')

  const sizeOptions = useMemo(() => {
    const base = sizesFor(v.category)
    return v.size && !base.includes(v.size) ? [...base, v.size] : base
  }, [v.category, v.size])

  function submit(e: FormEvent) {
    e.preventDefault()
    const next: typeof errs = {}
    if (!v.title.trim()) next.title = 'Add a title.'
    if (!v.category) next.category = 'Pick a category.'
    if (!v.condition) next.condition = 'Pick a condition.'
    if (!v.share_type) next.share_type = 'Choose swap, free or donate.'
    if (v.meetup_spot_id === '') next.meetup_spot_id = 'Pick a meetup spot.'
    if (photos.length < 1) next.photos = 'Add at least one photo.'
    setErrs(next)
    if (Object.keys(next).length) {
      document.querySelector<HTMLElement>('[aria-invalid="true"]')?.focus()
      return
    }
    const opt = (s: string) => (s.trim() ? s.trim() : null)
    onSubmit({
      title: v.title.trim(),
      category: v.category as Category,
      size: opt(v.size),
      color: opt(v.color),
      brand: opt(v.brand),
      condition: v.condition as Condition,
      condition_note: opt(v.condition_note),
      description: opt(v.description),
      tags: v.tags,
      share_type: v.share_type as ShareType,
      meetup_spot_id: v.meetup_spot_id as number,
      photo_ids: photos.map((p) => p.id),
    })
  }

  const counter = (s: string, max: number) => <span className="field-count">{s.length}/{max}</span>

  return (
    <div className="review">
      <div className="review-aside">{aside}{errs.photos && <p className="field-error" role="alert">{errs.photos}</p>}</div>
      <form className="review-form" onSubmit={submit} noValidate>
        <div className="form-grid">
          <div className={`field span-2`}>
            <label htmlFor="f-title">Title {counter(v.title, LIMITS.title)}</label>
            <input id="f-title" className={`input${mark('title')}`} value={v.title} maxLength={LIMITS.title} onChange={(e) => set('title', e.target.value)} aria-invalid={!!errs.title} placeholder="Levi's denim trucker jacket" />
            {errs.title && <p className="field-error" role="alert">{errs.title}</p>}
          </div>

          <div className="field">
            <label htmlFor="f-category">Category</label>
            <select id="f-category" className={`select${mark('category')}`} value={v.category} onChange={(e) => set('category', e.target.value as Category | '')} aria-invalid={!!errs.category}>
              <option value="">Choose…</option>
              {CATEGORIES.map((c) => <option key={c.value} value={c.value}>{c.label}</option>)}
            </select>
            {errs.category && <p className="field-error" role="alert">{errs.category}</p>}
          </div>
          <div className="field">
            <label htmlFor="f-size">Size</label>
            <select id="f-size" className={`select${mark('size')}`} value={v.size} onChange={(e) => set('size', e.target.value)}>
              <option value="">Not sure</option>
              {sizeOptions.map((s) => <option key={s} value={s}>{sizesFor(v.category).includes(s) ? s : `Other: ${s}`}</option>)}
            </select>
          </div>

          <div className="field">
            <label htmlFor="f-color">Color {counter(v.color, LIMITS.color)}</label>
            <input id="f-color" className={`input${mark('color')}`} value={v.color} maxLength={LIMITS.color} onChange={(e) => set('color', e.target.value)} />
          </div>
          <div className="field">
            <label htmlFor="f-brand">Brand {counter(v.brand, LIMITS.brand)}</label>
            <input id="f-brand" className={`input${mark('brand')}`} value={v.brand} maxLength={LIMITS.brand} onChange={(e) => set('brand', e.target.value)} />
          </div>

          <div className={`field span-2`}>
            <span className="field-label" id="f-cond-l">Condition</span>
            <div className={`seg${mark('condition')}`} role="radiogroup" aria-labelledby="f-cond-l" aria-invalid={!!errs.condition}>
              {CONDITIONS.map((c) => (
                <button key={c.value} type="button" role="radio" aria-checked={v.condition === c.value} className="seg-btn" onClick={() => set('condition', c.value)}>{c.label}</button>
              ))}
            </div>
            {errs.condition && <p className="field-error" role="alert">{errs.condition}</p>}
          </div>
          <div className="field span-2">
            <label htmlFor="f-note">Condition note {counter(v.condition_note, LIMITS.conditionNote)}</label>
            <input id="f-note" className={`input${mark('condition_note')}`} value={v.condition_note} maxLength={LIMITS.conditionNote} onChange={(e) => set('condition_note', e.target.value)} placeholder="light fading at the cuffs" />
          </div>
          <div className="field span-2">
            <label htmlFor="f-desc">Description {counter(v.description, LIMITS.description)}</label>
            <textarea id="f-desc" className={`textarea${mark('description')}`} value={v.description} maxLength={LIMITS.description} onChange={(e) => set('description', e.target.value)} />
          </div>
          <div className="field span-2">
            <label htmlFor="f-tags">Tags <span className="field-count">{v.tags.length}/{LIMITS.tags}</span></label>
            <div className={mark('tags')}><TagsInput id="f-tags" tags={v.tags} onChange={(t) => set('tags', t)} /></div>
          </div>

          <div className="field span-2">
            <span className="field-label" id="f-share-l">How do you want to share it?</span>
            <div className="seg" role="radiogroup" aria-labelledby="f-share-l" aria-invalid={!!errs.share_type}>
              {SHARE_TYPES.map((s) => (
                <button key={s.value} type="button" role="radio" aria-checked={v.share_type === s.value} className="seg-card" onClick={() => set('share_type', s.value)}>
                  <strong>{s.label}</strong><span>{s.hint}</span>
                </button>
              ))}
            </div>
            {errs.share_type && <p className="field-error" role="alert">{errs.share_type}</p>}
          </div>
          <div className="field span-2">
            <label htmlFor="f-spot">Meetup spot</label>
            <select id="f-spot" className="select" value={v.meetup_spot_id} onChange={(e) => set('meetup_spot_id', e.target.value ? Number(e.target.value) : '')} aria-invalid={!!errs.meetup_spot_id}>
              <option value="">Choose a spot…</option>
              {spots.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
            {errs.meetup_spot_id && <p className="field-error" role="alert">{errs.meetup_spot_id}</p>}
          </div>
        </div>

        {error && <p className="form-error" role="alert">{error}</p>}
        <div className="form-actions">
          {onCancel && <button type="button" className="btn btn-ghost" onClick={onCancel}>Cancel</button>}
          <button className="btn btn-lime btn-large" disabled={busy}>{busy ? 'Saving…' : submitLabel}</button>
        </div>
      </form>
    </div>
  )
}
