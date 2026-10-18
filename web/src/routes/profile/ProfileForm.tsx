import { useEffect, useRef, useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { getDorms, patchMe, uploadPhoto, type ProfilePatch } from '../../api/endpoints'
import { useAuth, useUser } from '../../auth/AuthContext'
import { Avatar } from '../../components/Avatar'
import { Logo } from '../../components/Logo'
import { BOTTOM_SIZES, LIMITS, SHOE_SIZES, TOP_SIZES } from '../../lib/constants'
import { errMsg, useDocumentTitle } from '../../lib/hooks'
import { resizeToJpeg } from '../../lib/image'
import type { Sizes } from '../../api/types'

/** `/welcome` (first login) and `/profile/edit`: one form, two routes. */
export default function ProfileForm({ mode }: { mode: 'welcome' | 'edit' }) {
  useDocumentTitle(mode === 'welcome' ? 'Set up your profile' : 'Edit profile')
  const user = useUser()
  const { setUser } = useAuth()
  const nav = useNavigate()
  const fileRef = useRef<HTMLInputElement>(null)

  const [name, setName] = useState(user.name ?? '')
  const [year, setYear] = useState(user.class_year ? String(user.class_year) : '')
  const [dorm, setDorm] = useState(user.dorm ?? '')
  const [sizes, setSizes] = useState<Sizes>({ ...user.sizes })
  const [dorms, setDorms] = useState<string[] | null>(null)
  const [avatar, setAvatar] = useState<{ id: number; url: string } | null>(null)
  const [avatarBusy, setAvatarBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [fieldErr, setFieldErr] = useState<Record<string, string>>({})
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    getDorms().then((r) => setDorms(r.items)).catch(() => setDorms([]))
  }, [])

  async function pickAvatar(file: File | undefined) {
    if (!file) return
    setError(null)
    setAvatarBusy(true)
    try {
      const blob = await resizeToJpeg(file, 600)
      const p = await uploadPhoto(blob, 'avatar')
      setAvatar({ id: p.id, url: p.url })
    } catch (e) {
      setError(errMsg(e))
    } finally {
      setAvatarBusy(false)
      if (fileRef.current) fileRef.current.value = ''
    }
  }

  async function submit(e: FormEvent) {
    e.preventDefault()
    const errs: Record<string, string> = {}
    const trimmed = name.trim()
    if (!trimmed) errs.name = 'Enter your name.'
    else if (trimmed.length > LIMITS.name) errs.name = `Keep it under ${LIMITS.name} characters.`
    if (year && !/^\d{4}$/.test(year)) errs.year = 'Use a four-digit year, like 2028.'
    setFieldErr(errs)
    if (Object.keys(errs).length) return

    // Send only what changed; sizes always as the whole object.
    const patch: ProfilePatch = {}
    if (trimmed !== (user.name ?? '')) patch.name = trimmed
    const yr = year ? Number(year) : null
    if (yr !== user.class_year) patch.class_year = yr
    if ((dorm || null) !== user.dorm) patch.dorm = dorm || null
    if (sizes.top !== user.sizes.top || sizes.bottom !== user.sizes.bottom || sizes.shoe !== user.sizes.shoe) patch.sizes = sizes
    if (avatar) patch.avatar_photo_id = avatar.id

    setBusy(true)
    setError(null)
    try {
      const updated = Object.keys(patch).length ? await patchMe(patch) : user
      setUser(updated)
      nav(mode === 'welcome' ? '/feed' : '/profile', { replace: true })
    } catch (err) {
      setError(errMsg(err))
      setBusy(false)
    }
  }

  const sizeSelect = (key: keyof Sizes, label: string, options: string[]) => (
    <div className="field">
      <label htmlFor={`size-${key}`}>{label}</label>
      <select id={`size-${key}`} className="select" value={sizes[key] ?? ''} onChange={(e) => setSizes({ ...sizes, [key]: e.target.value || null })}>
        <option value="">Not set</option>
        {options.map((o) => <option key={o}>{o}</option>)}
      </select>
    </div>
  )

  const shownAvatarUrl = avatar?.url ?? user.avatar_url

  return (
    <div className={mode === 'welcome' ? 'welcome' : 'page-narrow'}>
      {mode === 'welcome' && <div className="welcome-logo"><Logo height={32} /></div>}
      <form className={mode === 'welcome' ? 'signin-card wide' : 'panel'} onSubmit={submit} noValidate>
        <div>
          <h1>{mode === 'welcome' ? 'Set up your profile' : 'Edit profile'}</h1>
          {mode === 'welcome' && <p className="muted">Classmates see this when you post or request something.</p>}
        </div>

        <div className="avatar-row">
          <Avatar name={name || user.name} url={shownAvatarUrl} size={72} />
          <div>
            <button type="button" className="btn btn-ghost btn-small" onClick={() => fileRef.current?.click()} disabled={avatarBusy}>
              {avatarBusy ? 'Uploading…' : shownAvatarUrl ? 'Change photo' : 'Add a photo'}
            </button>
            <input ref={fileRef} type="file" accept="image/*" hidden onChange={(e) => pickAvatar(e.target.files?.[0])} />
            {avatar && <span className="field-hint" style={{ marginLeft: 10 }}>Saved when you press Save.</span>}
          </div>
        </div>

        <div className="form-grid">
          <div className="field span-2">
            <label htmlFor="name">Name <span className="field-count">{name.length}/{LIMITS.name}</span></label>
            <input id="name" className="input" value={name} maxLength={LIMITS.name} onChange={(e) => setName(e.target.value)} autoComplete="name" autoFocus={mode === 'welcome'} aria-invalid={!!fieldErr.name} />
            {fieldErr.name && <p className="field-error" role="alert">{fieldErr.name}</p>}
          </div>
          <div className="field">
            <label htmlFor="year">Class year</label>
            <input id="year" className="input" inputMode="numeric" placeholder="2028" maxLength={4} value={year} onChange={(e) => setYear(e.target.value.replace(/\D/g, ''))} aria-invalid={!!fieldErr.year} />
            {fieldErr.year && <p className="field-error" role="alert">{fieldErr.year}</p>}
          </div>
          <div className="field">
            <label htmlFor="dorm">Dorm</label>
            {dorms && dorms.length === 0 ? (
              <input id="dorm" className="input" maxLength={80} value={dorm} onChange={(e) => setDorm(e.target.value)} placeholder="Your dorm" />
            ) : (
              <select id="dorm" className="select" value={dorm} onChange={(e) => setDorm(e.target.value)} disabled={!dorms}>
                <option value="">{dorms ? 'Not set' : 'Loading…'}</option>
                {/* keep a saved dorm selectable even if it's no longer in the list */}
                {dorm && dorms && !dorms.includes(dorm) && <option>{dorm}</option>}
                {dorms?.map((d) => <option key={d}>{d}</option>)}
              </select>
            )}
          </div>
        </div>

        <fieldset className="sizes">
          <legend className="field-label">Your usual sizes</legend>
          <div className="form-grid three">
            {sizeSelect('top', 'Top', TOP_SIZES)}
            {sizeSelect('bottom', 'Bottom', BOTTOM_SIZES)}
            {sizeSelect('shoe', 'Shoe (US)', SHOE_SIZES)}
          </div>
        </fieldset>

        {error && <p className="form-error" role="alert">{error}</p>}
        <div className="form-actions">
          {mode === 'edit' && <button type="button" className="btn btn-ghost" onClick={() => nav('/profile')}>Cancel</button>}
          <button className="btn btn-primary" disabled={busy || avatarBusy}>{busy ? 'Saving…' : mode === 'welcome' ? 'Continue' : 'Save'}</button>
        </div>
      </form>
    </div>
  )
}

