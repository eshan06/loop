import { useEffect, useState } from 'react'
import { saveListing, unsaveListing } from '../api/endpoints'
import { HeartIcon } from './Icons'
import { useToast } from './Toast'

interface Props {
  listingId: number
  saved: boolean
  onChange?: (saved: boolean) => void
  className?: string
}

/** Heart toggle. Optimistic; rolls back and says so when the server refuses. */
export function SaveButton({ listingId, saved, onChange, className = '' }: Props) {
  const [on, setOn] = useState(saved)
  const [busy, setBusy] = useState(false)
  const toast = useToast()
  useEffect(() => setOn(saved), [saved])

  async function toggle(e: React.MouseEvent) {
    e.preventDefault()
    e.stopPropagation()
    if (busy) return
    const next = !on
    setOn(next)
    setBusy(true)
    try {
      await (next ? saveListing(listingId) : unsaveListing(listingId))
      onChange?.(next)
    } catch (err) {
      setOn(!next)
      toast(err instanceof Error ? err.message : "Couldn't update your saved items.", 'error')
    } finally {
      setBusy(false)
    }
  }

  return (
    <button
      type="button"
      className={`heart ${on ? 'heart-on' : ''} ${className}`}
      onClick={toggle}
      aria-pressed={on}
      aria-label={on ? 'Remove from saved' : 'Save'}
    >
      <HeartIcon filled={on} width={20} height={20} />
    </button>
  )
}
