import { useCallback, useEffect, useRef, useState } from 'react'
import { Link, useLocation, useNavigate, useSearchParams } from 'react-router-dom'
import { getImpactCampus, getListings } from '../../api/endpoints'
import type { Category, ShareType } from '../../api/types'
import { Dialog } from '../../components/Dialog'
import { FilterIcon } from '../../components/Icons'
import { ListingCard } from '../../components/ListingCard'
import { CardSkeletons, EmptyState, ErrorState } from '../../components/States'
import { CATEGORIES, SHARE_TYPES, sizesFor } from '../../lib/constants'
import { n0, n1 } from '../../lib/format'
import { useAsync, useDocumentTitle, useIsMobile, usePaged } from '../../lib/hooks'

const SHARE_VALUES = SHARE_TYPES.map((s) => s.value)
const CATEGORY_VALUES = CATEGORIES.map((c) => c.value)

function useFilters() {
  const [params, setParams] = useSearchParams()
  const rawShare = params.get('share_type') ?? ''
  const rawCategory = params.get('category') ?? ''
  const filters = {
    q: params.get('q') ?? '',
    share_type: (SHARE_VALUES.includes(rawShare as ShareType) ? rawShare : '') as ShareType | '',
    category: (CATEGORY_VALUES.includes(rawCategory as Category) ? rawCategory : '') as Category | '',
    size: params.get('size') ?? '',
  }
  const set = useCallback(
    (patch: Partial<typeof filters>) => {
      const next = new URLSearchParams(params)
      for (const [k, v] of Object.entries(patch)) {
        if (v) next.set(k, v)
        else next.delete(k)
      }
      // a size from another category's vocabulary no longer applies
      if ('category' in patch) next.delete('size')
      setParams(next)
    },
    [params, setParams],
  )
  const clear = useCallback(() => setParams(new URLSearchParams()), [setParams])
  return { filters, set, clear }
}

type Filters = ReturnType<typeof useFilters>['filters']

function FilterPanel({ filters, set, clear }: { filters: Filters; set: (p: Partial<Filters>) => void; clear: () => void }) {
  const active = !!(filters.q || filters.share_type || filters.category || filters.size)
  return (
    <div className="filters">
      <fieldset className="filter-group">
        <legend>Type</legend>
        <div className="seg">
          <button className="seg-btn" aria-pressed={!filters.share_type} onClick={() => set({ share_type: '' })}>All</button>
          {SHARE_TYPES.map((s) => (
            <button key={s.value} className="seg-btn" aria-pressed={filters.share_type === s.value} onClick={() => set({ share_type: s.value })}>
              {s.label}
            </button>
          ))}
        </div>
      </fieldset>
      <fieldset className="filter-group">
        <legend>Category</legend>
        <div className="seg">
          <button className="seg-btn" aria-pressed={!filters.category} onClick={() => set({ category: '' })}>All</button>
          {CATEGORIES.map((c) => (
            <button key={c.value} className="seg-btn" aria-pressed={filters.category === c.value} onClick={() => set({ category: c.value })}>
              {c.label}
            </button>
          ))}
        </div>
      </fieldset>
      <div className="filter-group">
        <label className="field-label" htmlFor="filter-size">Size</label>
        <select id="filter-size" className="select" value={filters.size} onChange={(e) => set({ size: e.target.value })}>
          <option value="">Any size</option>
          {sizesFor(filters.category).map((s) => <option key={s}>{s}</option>)}
        </select>
      </div>
      {active && <button className="btn btn-ghost btn-small" onClick={clear}>Clear filters</button>}
    </div>
  )
}

function ImpactBanner() {
  const { data } = useAsync(() => getImpactCampus(), [])
  if (!data || data.items_rehomed === 0) return null
  return (
    <Link to="/impact" className="impact-banner">
      <strong>{n0(data.items_rehomed)} items rehomed this week</strong>
      <span>{n1(data.textile_kg)} kg of textile</span>
      <span>{n0(data.water_l)} L of water</span>
      <span className="impact-more">See your impact →</span>
    </Link>
  )
}

export default function Feed() {
  useDocumentTitle('Feed')
  const { filters, set, clear } = useFilters()
  const isMobile = useIsMobile()
  const [drawer, setDrawer] = useState(false)
  const loc = useLocation()
  const nav = useNavigate()
  const [fresh, setFresh] = useState<number | null>((loc.state as { justPosted?: number } | null)?.justPosted ?? null)

  // The "Just posted" tag lasts a few seconds, and a refresh shouldn't bring it back.
  useEffect(() => {
    if (fresh === null) return
    nav(loc.pathname + loc.search, { replace: true, state: null })
    const t = window.setTimeout(() => setFresh(null), 6000)
    return () => window.clearTimeout(t)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const list = usePaged(
    (offset, signal) => getListings({ q: filters.q || undefined, share_type: filters.share_type, category: filters.category, size: filters.size || undefined }, offset, 20, signal),
    [filters.q, filters.share_type, filters.category, filters.size],
  )

  // Load more as the sentinel scrolls into view; the button remains as the fallback.
  const sentinel = useRef<HTMLDivElement>(null)
  const { hasMore, loadMore, loading, loadingMore, moreError } = list
  useEffect(() => {
    const el = sentinel.current
    if (!el || !hasMore || loading || moreError) return
    const io = new IntersectionObserver((e) => e[0].isIntersecting && loadMore(), { rootMargin: '600px' })
    io.observe(el)
    return () => io.disconnect()
  }, [hasMore, loading, loadMore, moreError, list.items.length])

  const filtered = !!(filters.q || filters.share_type || filters.category || filters.size)
  const activeCount = [filters.share_type, filters.category, filters.size].filter(Boolean).length

  return (
    <div className="feed-layout">
      {!isMobile && (
        <aside className="feed-side" aria-label="Filters">
          <FilterPanel filters={filters} set={set} clear={clear} />
        </aside>
      )}
      <section className="feed-main">
        <ImpactBanner />
        <div className="page-head">
          <div>
            <h1>{filters.q ? `Results for “${filters.q}”` : 'Campus feed'}</h1>
            {!list.loading && !list.error && <p className="muted small">{list.total} {list.total === 1 ? 'item' : 'items'}</p>}
          </div>
          {isMobile && (
            <button className="btn btn-ghost btn-small" onClick={() => setDrawer(true)}>
              <FilterIcon width={16} height={16} /> Filters{activeCount ? ` (${activeCount})` : ''}
            </button>
          )}
        </div>

        {list.error ? (
          <ErrorState error={list.error} onRetry={list.reload} />
        ) : list.loading ? (
          <div className="grid"><CardSkeletons /></div>
        ) : list.items.length === 0 ? (
          <EmptyState
            title="Nothing matches yet"
            body={filtered ? 'Try fewer filters or a different search.' : 'Be the first to post something on your campus.'}
            action={filtered ? <button className="btn btn-primary" onClick={clear}>Clear filters</button> : <Link className="btn btn-lime" to="/post">Post an item</Link>}
          />
        ) : (
          <>
            <div className="grid">
              {list.items.map((l) => (
                <ListingCard key={l.id} listing={l} justPosted={l.id === fresh} />
              ))}
              {loadingMore && <CardSkeletons count={5} />}
            </div>
            <div ref={sentinel} className="load-more">
              {moreError ? (
                <ErrorState compact error={moreError} onRetry={loadMore} />
              ) : (
                hasMore && !loadingMore && <button className="btn btn-ghost" onClick={loadMore}>Load more</button>
              )}
            </div>
          </>
        )}
      </section>

      {isMobile && (
        <Dialog open={drawer} onClose={() => setDrawer(false)} title="Filters">
          <FilterPanel filters={filters} set={set} clear={clear} />
          <div className="dialog-actions">
            <button className="btn btn-primary btn-block" onClick={() => setDrawer(false)}>Show {list.total} {list.total === 1 ? 'item' : 'items'}</button>
          </div>
        </Dialog>
      )}
    </div>
  )
}
