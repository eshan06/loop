import { LOGO_PATH, LOGO_VIEWBOX } from '../assets/logo-path'

/** The Loop logo: flat near-black outline, sharp at any size. `height` is in px. */
export function Logo({ height = 28, className }: { height?: number; className?: string }) {
  const [, , w, h] = LOGO_VIEWBOX.split(' ').map(Number)
  return (
    <svg
      className={className}
      viewBox={LOGO_VIEWBOX}
      height={height}
      width={(height * w) / h}
      role="img"
      aria-label="Loop"
    >
      <path d={LOGO_PATH} fill="currentColor" fillRule="evenodd" />
    </svg>
  )
}
