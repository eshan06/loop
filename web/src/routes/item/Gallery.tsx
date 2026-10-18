import { useState } from 'react'
import { media } from '../../api/client'
import type { Photo } from '../../api/types'
import { BackIcon, ChevronRight } from '../../components/Icons'

export function Gallery({ photos, title }: { photos: Photo[]; title: string }) {
  const [i, setI] = useState(0)
  const count = photos.length
  const go = (n: number) => setI(((n % count) + count) % count)
  const cur = photos[Math.min(i, count - 1)]

  return (
    <div
      className="gallery"
      tabIndex={0}
      role="group"
      aria-roledescription="carousel"
      aria-label={`${title} photos`}
      onKeyDown={(e) => {
        if (count < 2) return
        if (e.key === 'ArrowRight') { e.preventDefault(); go(i + 1) }
        if (e.key === 'ArrowLeft') { e.preventDefault(); go(i - 1) }
      }}
    >
      <div className="gallery-main">
        {cur && <img src={media(cur.url) ?? ''} alt={`${title}, photo ${i + 1} of ${count}${cur.kind !== 'other' ? ` (${cur.kind})` : ''}`} />}
        {count > 1 && (
          <>
            <button className="gallery-nav prev" onClick={() => go(i - 1)} aria-label="Previous photo"><BackIcon /></button>
            <button className="gallery-nav next" onClick={() => go(i + 1)} aria-label="Next photo"><ChevronRight /></button>
            <span className="gallery-count">{i + 1} / {count}</span>
          </>
        )}
      </div>
      {count > 1 && (
        <div className="gallery-thumbs">
          {photos.map((p, n) => (
            <button key={p.id} className={`thumb${n === i ? ' on' : ''}`} onClick={() => setI(n)} aria-label={`Show photo ${n + 1}`} aria-current={n === i}>
              <img src={media(p.url) ?? ''} alt="" loading="lazy" />
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
