import { Link } from 'react-router-dom'
import { getSaved } from '../../api/endpoints'
import { ListingCard } from '../../components/ListingCard'
import { CardSkeletons, EmptyState, ErrorState } from '../../components/States'
import { useDocumentTitle, usePaged } from '../../lib/hooks'

export default function Saved() {
  useDocumentTitle('Saved')
  const list = usePaged((offset) => getSaved(offset), [])
  return (
    <div>
      <div className="page-head"><h1>Saved</h1></div>
      {list.error ? (
        <ErrorState error={list.error} onRetry={list.reload} />
      ) : list.loading ? (
        <div className="grid"><CardSkeletons count={5} /></div>
      ) : list.items.length === 0 ? (
        <EmptyState title="Tap the heart on anything you like." body="Saved items show up here." action={<Link className="btn btn-primary" to="/feed">Browse the feed</Link>} />
      ) : (
        <>
          <div className="grid">
            {list.items.map((l) => (
              // Unsaving removes the card.
              <ListingCard key={l.id} listing={{ ...l, saved_by_me: true }} onSavedChange={(s) => !s && list.setItems((cur) => cur.filter((x) => x.id !== l.id))} />
            ))}
          </div>
          {list.hasMore && <div className="load-more"><button className="btn btn-ghost" onClick={list.loadMore} disabled={list.loadingMore}>{list.loadingMore ? 'Loading…' : 'Load more'}</button></div>}
        </>
      )}
    </div>
  )
}
