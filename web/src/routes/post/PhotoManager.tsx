import { useRef, useState } from 'react'
import { media } from '../../api/client'
import { uploadPhoto } from '../../api/endpoints'
import type { Photo } from '../../api/types'
import { CameraIcon } from '../../components/Icons'
import { LIMITS } from '../../lib/constants'
import { errMsg } from '../../lib/hooks'
import { resizeToJpeg } from '../../lib/image'

interface Props {
  photos: Photo[]
  onChange: (p: Photo[]) => void
  max?: number
}

/** Uploaded photos for a listing: reorder, remove, add more (each goes through POST /photos). */
export function PhotoManager({ photos, onChange, max = LIMITS.photos }: Props) {
  const input = useRef<HTMLInputElement>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function add(files: FileList | File[]) {
    const room = max - photos.length
    const list = Array.from(files).slice(0, room)
    if (!list.length) return
    setBusy(true)
    setError(null)
    let next = photos
    try {
      for (const f of list) {
        const blob = await resizeToJpeg(f)
        const p = await uploadPhoto(blob, 'other')
        next = [...next, p]
        onChange(next)
      }
    } catch (e) {
      setError(errMsg(e))
    } finally {
      setBusy(false)
      if (input.current) input.current.value = ''
    }
  }

  const move = (i: number, d: number) => {
    const j = i + d
    if (j < 0 || j >= photos.length) return
    const n = [...photos]
    ;[n[i], n[j]] = [n[j], n[i]]
    onChange(n)
  }

  return (
    <div className="pm">
      <p className="field-label">Photos <span className="field-count">{photos.length}/{max}</span></p>
      <ul className="pm-grid">
        {photos.map((p, i) => (
          <li key={p.id} className="pm-item">
            <img src={media(p.url) ?? ''} alt={`Photo ${i + 1}${i === 0 ? ' (cover)' : ''}`} />
            {i === 0 && <span className="pm-cover">Cover</span>}
            <div className="pm-tools">
              <button type="button" onClick={() => move(i, -1)} disabled={i === 0} aria-label={`Move photo ${i + 1} earlier`}>←</button>
              <button type="button" onClick={() => move(i, 1)} disabled={i === photos.length - 1} aria-label={`Move photo ${i + 1} later`}>→</button>
              <button type="button" onClick={() => onChange(photos.filter((x) => x.id !== p.id))} disabled={photos.length <= 1} aria-label={`Remove photo ${i + 1}`}>×</button>
            </div>
          </li>
        ))}
        {photos.length < max && (
          <li>
            <button type="button" className="pm-add" onClick={() => input.current?.click()} disabled={busy}>
              <CameraIcon /> {busy ? 'Uploading…' : 'Add photo'}
            </button>
          </li>
        )}
      </ul>
      <input ref={input} type="file" accept="image/*" multiple hidden onChange={(e) => e.target.files && add(e.target.files)} />
      {error && <p className="field-error" role="alert">{error}</p>}
    </div>
  )
}
