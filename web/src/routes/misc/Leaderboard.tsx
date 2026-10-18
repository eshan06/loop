import { getLeaderboard } from '../../api/endpoints'
import { useUser } from '../../auth/AuthContext'
import { Tag } from '../../components/Badges'
import { EmptyState, ErrorState, FullLoading } from '../../components/States'
import { useAsync, useDocumentTitle, useVisibleInterval } from '../../lib/hooks'

export default function Leaderboard() {
  useDocumentTitle('Leaderboard')
  const me = useUser()
  const { data, error, reload } = useAsync(() => getLeaderboard(), [])
  // The projector view stays fresh while it's up.
  useVisibleInterval(reload, 30000)

  if (error && !data) return <ErrorState error={error} onRetry={reload} />
  if (!data) return <FullLoading />

  return (
    <div className="board">
      <div className="board-head">
        <h1>Dorm leaderboard</h1>
        <p className="muted">Items shared this week at {me.campus.name}</p>
      </div>
      {data.items.length === 0 ? (
        <EmptyState title="No exchanges this week yet" body="The first completed swap puts a dorm on the board." />
      ) : (
        <ol className="board-list">
          {data.items.map((r) => {
            const mine = !!me.dorm && r.dorm.toLowerCase() === me.dorm.toLowerCase()
            return (
              <li key={r.dorm} className={`board-row rank-${Math.min(r.rank, 4)}${mine ? ' board-mine' : ''}`}>
                <span className="board-rank">{r.rank}</span>
                <span className="board-dorm">{r.dorm} {mine && <Tag lime>You</Tag>}</span>
                <span className="board-count"><strong>{r.items_shared}</strong> <span className="muted">{r.items_shared === 1 ? 'item' : 'items'}</span></span>
              </li>
            )
          })}
        </ol>
      )}
    </div>
  )
}
