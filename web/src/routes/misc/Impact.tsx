import { getImpactCampus, getImpactMe } from '../../api/endpoints'
import { ErrorState, FullLoading } from '../../components/States'
import { kg, n0 } from '../../lib/format'
import { useAsync, useDocumentTitle } from '../../lib/hooks'

function Big({ value, unit, label }: { value: string; unit: string; label: string }) {
  return (
    <div className="big-num">
      <strong>{value}</strong>
      <span className="big-unit">{unit}</span>
      <span className="muted">{label}</span>
    </div>
  )
}

export default function Impact() {
  useDocumentTitle('Impact')
  const me = useAsync(() => getImpactMe(), [])
  const campus = useAsync(() => getImpactCampus(), [])

  if (me.error) return <ErrorState error={me.error} onRetry={me.reload} />
  if (!me.data) return <FullLoading />
  const m = me.data

  return (
    <div className="page-narrow-wide impact">
      <div className="page-head"><h1>Your impact</h1></div>
      <section className="impact-panel" aria-label="My impact">
        <div className="big-row">
          <Big value={kg(m.textile_kg)} unit="kg" label="of textile kept out of landfill" />
          <Big value={n0(m.water_l)} unit="L" label="of water saved" />
          <Big value={kg(m.co2_kg)} unit="kg" label="of CO₂e avoided" />
        </div>
        <p className="muted">
          You've shared <strong>{m.items_shared}</strong> {m.items_shared === 1 ? 'item' : 'items'} and received <strong>{m.items_received}</strong>.
        </p>
      </section>

      <section className="impact-panel" aria-label="Campus impact this week">
        <h2>On your campus this week</h2>
        {campus.error ? (
          <ErrorState compact error={campus.error} onRetry={campus.reload} />
        ) : !campus.data ? null : campus.data.items_rehomed === 0 ? (
          <p className="muted">No exchanges completed yet this week. Be the first.</p>
        ) : (
          <>
            <div className="big-row">
              <Big value={n0(campus.data.items_rehomed)} unit="" label="items rehomed" />
              <Big value={kg(campus.data.textile_kg)} unit="kg" label="of textile" />
              <Big value={n0(campus.data.water_l)} unit="L" label="of water" />
            </div>
            {campus.data.top_dorm && <p>Top dorm: <strong>{campus.data.top_dorm}</strong></p>}
          </>
        )}
      </section>

      <section className="sources" aria-label="Where these numbers come from">
        <h2>Where these numbers come from</h2>
        <p className="muted">
          Each item's impact is a typical garment weight for its category times a lifecycle footprint per kilogram of clothing. They're estimates, not measurements.
        </p>
        <ul>
          <li>
            <strong>Footprint per kg</strong>: WRAP (2017), <a href="https://www.wrap.ngo/sites/default/files/2020-10/WRAP-valuing-our-clothes-the-cost-of-uk-fashion_WRAP.pdf" target="_blank" rel="noreferrer">Valuing Our Clothes: the cost of UK fashion</a>, Table 3 (2016): 23.2 kg CO₂e and 7,060 L of water per kg of clothing.
          </li>
          <li>
            <strong>Garment weights</strong>: Sandin, Roos, Spak, Zamani &amp; Peters (2019), <a href="https://research.chalmers.se/publication/514322" target="_blank" rel="noreferrer">Environmental assessment of Swedish clothing consumption</a>, Mistra Future Fashion report 2019:05, Table 3.1 (T-shirt 110 g, jeans 477 g, dress 478 g, jacket 444 g, socks 43 g). Shoes and bags are assumptions, since neither source covers them.
          </li>
        </ul>
      </section>
    </div>
  )
}
