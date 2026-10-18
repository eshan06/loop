import { useEffect, useState } from 'react'
import { getBadges, getListing } from '../../api/endpoints'
import type { Badge } from '../../api/types'
import { CheckIcon } from '../../components/Icons'
import { kg, n0 } from '../../lib/format'

/** Counts from 0 to `to` over ~1.2 s (instantly when the user prefers reduced motion). */
function useCountUp(to: number, run: boolean) {
  const [v, setV] = useState(0)
  useEffect(() => {
    if (!run) return
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return setV(to)
    const start = performance.now()
    let raf = 0
    const tick = (now: number) => {
      const p = Math.min(1, (now - start) / 1200)
      setV(to * (1 - Math.pow(1 - p, 3)))
      if (p < 1) raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [to, run])
  return v
}

export function Celebration({ listingId }: { listingId: number }) {
  const [impact, setImpact] = useState<{ textile_kg: number; water_l: number; co2_kg: number } | null>(null)
  const [badges, setBadges] = useState<Badge[]>([])

  useEffect(() => {
    getListing(listingId).then((l) => setImpact(l.impact)).catch(() => {})
    getBadges()
      .then((r) => setBadges(r.items.filter((b) => b.earned_at && Date.now() - new Date(b.earned_at).getTime() < 60_000)))
      .catch(() => {})
  }, [listingId])

  const t = useCountUp(impact?.textile_kg ?? 0, !!impact)
  const w = useCountUp(impact?.water_l ?? 0, !!impact)
  const c = useCountUp(impact?.co2_kg ?? 0, !!impact)

  return (
    <div className="celebrate">
      <span className="celebrate-check"><CheckIcon width={34} height={34} /></span>
      <h2>Exchange complete</h2>
      <p className="muted">Another piece of clothing kept out of the landfill.</p>
      {impact && (
        <div className="celebrate-nums">
          <div><strong>{kg(t)}</strong><span>kg textile</span></div>
          <div><strong>{n0(w)}</strong><span>L water</span></div>
          <div><strong>{kg(c)}</strong><span>kg CO₂</span></div>
        </div>
      )}
      {badges.map((b) => (
        <div key={b.id} className="celebrate-badge">
          <span className="tag tag-lime">New badge</span> <strong>{b.name}</strong> <span className="muted">{b.description}</span>
        </div>
      ))}
    </div>
  )
}
