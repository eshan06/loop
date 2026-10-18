import { useState, type KeyboardEvent } from 'react'
import { LIMITS } from '../../lib/constants'

interface Props {
  id: string
  tags: string[]
  onChange: (tags: string[]) => void
}

/** Editable chips, up to 10 tags of up to 30 characters. Enter or comma adds one. */
export function TagsInput({ id, tags, onChange }: Props) {
  const [text, setText] = useState('')
  const full = tags.length >= LIMITS.tags

  function commit(raw = text) {
    const t = raw.trim().replace(/\s+/g, ' ').slice(0, LIMITS.tagLength)
    setText('')
    if (!t || full || tags.some((x) => x.toLowerCase() === t.toLowerCase())) return
    onChange([...tags, t])
  }

  function onKey(e: KeyboardEvent<HTMLInputElement>) {
    if (e.key === 'Enter' || e.key === ',') {
      e.preventDefault()
      commit()
    } else if (e.key === 'Backspace' && !text && tags.length) {
      onChange(tags.slice(0, -1))
    }
  }

  return (
    <div className="chips" onClick={(e) => (e.currentTarget.querySelector('input') as HTMLInputElement | null)?.focus()}>
      {tags.map((t) => (
        <span key={t} className="chip">
          {t}
          <button type="button" aria-label={`Remove tag ${t}`} onClick={() => onChange(tags.filter((x) => x !== t))}>×</button>
        </span>
      ))}
      <input
        id={id}
        value={text}
        maxLength={LIMITS.tagLength}
        disabled={full}
        placeholder={full ? 'Tag limit reached' : tags.length ? 'Add another' : 'denim, vintage, oversized'}
        onChange={(e) => setText(e.target.value)}
        onKeyDown={onKey}
        onBlur={() => commit()}
        aria-label="Add a tag"
      />
    </div>
  )
}
