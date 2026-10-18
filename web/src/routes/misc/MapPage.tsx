import { useEffect, useRef } from 'react'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { getDonationBins, getMeetupSpots } from '../../api/endpoints'
import { ErrorState, FullLoading } from '../../components/States'
import { useAsync, useDocumentTitle } from '../../lib/hooks'

interface Pin {
  key: string
  lat: number
  lng: number
  kind: 'spot' | 'bin'
  name: string
  detail: string[]
}

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!)

/** Meetup spots and donation bins as two kinds of pins. Leaflet + OpenStreetMap tiles, no API key. */
export default function MapPage() {
  useDocumentTitle('Map')
  const data = useAsync(async () => {
    const [spots, bins] = await Promise.all([getMeetupSpots(), getDonationBins()])
    const pins: Pin[] = []
    for (const s of spots.items) if (s.lat !== null && s.lng !== null) pins.push({ key: `s${s.id}`, lat: s.lat, lng: s.lng, kind: 'spot', name: s.name, detail: ['Meetup spot'] })
    for (const b of bins.items) pins.push({
      key: `b${b.id}`, lat: b.lat, lng: b.lng, kind: 'bin', name: b.name,
      detail: ['Donation bin', b.description, b.accepts && `Accepts: ${b.accepts}`, b.hours && `Hours: ${b.hours}`].filter(Boolean) as string[],
    })
    return pins
  }, [])
  const el = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!el.current || !data.data?.length) return
    const map = L.map(el.current, { scrollWheelZoom: true })
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    }).addTo(map)
    const pts: L.LatLngExpression[] = []
    const css = getComputedStyle(document.documentElement)
    const ink = css.getPropertyValue('--ink').trim()
    const lime = css.getPropertyValue('--lime').trim()
    for (const p of data.data) {
      const color = p.kind === 'bin' ? lime : ink
      L.circleMarker([p.lat, p.lng], { radius: 10, weight: 3, color: ink, fillColor: color, fillOpacity: 1 })
        .bindPopup(`<strong>${esc(p.name)}</strong>${p.detail.map((d) => `<br>${esc(d)}`).join('')}`)
        .addTo(map)
      pts.push([p.lat, p.lng])
    }
    map.fitBounds(L.latLngBounds(pts).pad(0.25), { maxZoom: 17 })
    return () => { map.remove() }
  }, [data.data])

  if (data.error) return <ErrorState error={data.error} onRetry={data.reload} />
  if (!data.data) return <FullLoading />

  return (
    <div>
      <div className="page-head">
        <h1>Campus map</h1>
        <p className="map-legend small"><span className="dot dot-spot" /> Meetup spots <span className="dot dot-bin" /> Donation bins</p>
      </div>
      {data.data.length === 0 ? (
        <p className="muted">No places with coordinates on your campus yet.</p>
      ) : (
        <div ref={el} className="map" role="region" aria-label="Map of meetup spots and donation bins" />
      )}
    </div>
  )
}
