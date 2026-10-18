import { media } from '../api/client'
import { displayName, initials } from '../lib/format'

interface Props {
  name: string | null | undefined
  url: string | null | undefined
  size?: number
}

export function Avatar({ name, url, size = 36 }: Props) {
  const src = media(url)
  return (
    <span className="avatar" style={{ width: size, height: size, fontSize: Math.max(11, size * 0.38) }}>
      {src ? <img src={src} alt={`${displayName(name)}'s avatar`} width={size} height={size} /> : <span aria-hidden>{initials(name) || '·'}</span>}
    </span>
  )
}
