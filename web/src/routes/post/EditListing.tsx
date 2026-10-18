import { useState } from 'react'
import { Navigate, useNavigate, useParams } from 'react-router-dom'
import { ApiError } from '../../api/client'
import { getListing, getMeetupSpots, patchListing } from '../../api/endpoints'
import type { Listing, ListingInput, Photo } from '../../api/types'
import { ErrorState, FullLoading, NotFound } from '../../components/States'
import { useToast } from '../../components/Toast'
import { errMsg, useAsync, useDocumentTitle } from '../../lib/hooks'
import { ListingForm, type FormValues } from './ListingForm'
import { PhotoManager } from './PhotoManager'

export default function EditListing() {
  useDocumentTitle('Edit listing')
  const { id } = useParams()
  const listing = useAsync(() => getListing(id!), [id])
  const spots = useAsync(() => getMeetupSpots(), [])

  if (listing.error instanceof ApiError && (listing.error.status === 404 || listing.error.status === 403)) return <NotFound />
  if (listing.error) return <ErrorState error={listing.error} onRetry={listing.reload} />
  if (spots.error) return <ErrorState error={spots.error} onRetry={spots.reload} />
  if (!listing.data || !spots.data) return <FullLoading />
  const l = listing.data
  // Owner only; completed listings can't be edited.
  if (!l.is_mine || l.status === 'completed') return <Navigate to={`/item/${l.id}`} replace />
  return <Editor listing={l} spots={spots.data.items} />
}

function Editor({ listing: l, spots }: { listing: Listing; spots: { id: number; name: string; lat: number | null; lng: number | null }[] }) {
  const nav = useNavigate()
  const toast = useToast()
  const [photos, setPhotos] = useState<Photo[]>(l.photos)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const initial: FormValues = {
    title: l.title, category: l.category, size: l.size ?? '', color: l.color ?? '', brand: l.brand ?? '', condition: l.condition,
    condition_note: l.condition_note ?? '', description: l.description ?? '', tags: l.tags, share_type: l.share_type,
    meetup_spot_id: l.meetup_spot?.id ?? '',
  }

  async function save(input: ListingInput) {
    // Only the changed fields; photo_ids replaces the whole list, so send it only when it changed.
    const patch: Record<string, unknown> = {}
    const before: Record<string, unknown> = {
      title: l.title, category: l.category, size: l.size, color: l.color, brand: l.brand, condition: l.condition,
      condition_note: l.condition_note, description: l.description, tags: l.tags, share_type: l.share_type,
      meetup_spot_id: l.meetup_spot?.id ?? null, photo_ids: l.photos.map((p) => p.id),
    }
    for (const [k, v] of Object.entries(input)) {
      if (JSON.stringify(v) !== JSON.stringify(before[k])) patch[k] = v
    }
    if (!Object.keys(patch).length) return nav(`/item/${l.id}`)
    setBusy(true)
    setError(null)
    try {
      await patchListing(l.id, patch as Partial<ListingInput>)
      toast('Saved.')
      nav(`/item/${l.id}`)
    } catch (e) {
      setError(errMsg(e))
      setBusy(false)
    }
  }

  return (
    <div className="page-narrow-wide">
      <div className="page-head"><h1>Edit listing</h1></div>
      <ListingForm
        initial={initial}
        spots={spots}
        photos={photos}
        submitLabel="Save changes"
        busy={busy}
        error={error}
        aside={<PhotoManager photos={photos} onChange={setPhotos} />}
        onSubmit={save}
        onCancel={() => nav(`/item/${l.id}`)}
      />
    </div>
  )
}
