import type { Category, Condition, ListingStatus, RequestStatus, ShareType } from '../api/types'

export const SHARE_TYPES: { value: ShareType; label: string; hint: string }[] = [
  { value: 'swap', label: 'Swap', hint: 'Trade it for something of theirs' },
  { value: 'free', label: 'Free', hint: 'Give it to a classmate' },
  { value: 'donate', label: 'Donate', hint: 'We route it to a campus bin' },
]
export const shareLabel = (s: ShareType) => SHARE_TYPES.find((x) => x.value === s)?.label ?? s

export const CATEGORIES: { value: Category; label: string }[] = [
  { value: 'tops', label: 'Tops' },
  { value: 'bottoms', label: 'Bottoms' },
  { value: 'outerwear', label: 'Outerwear' },
  { value: 'dresses', label: 'Dresses' },
  { value: 'shoes', label: 'Shoes' },
  { value: 'accessories', label: 'Accessories' },
  { value: 'bags', label: 'Bags' },
]
export const categoryLabel = (c: Category) => CATEGORIES.find((x) => x.value === c)?.label ?? c

export const CONDITIONS: { value: Condition; label: string }[] = [
  { value: 'new', label: 'New' },
  { value: 'like_new', label: 'Like new' },
  { value: 'good', label: 'Good' },
  { value: 'worn', label: 'Worn' },
]
export const conditionLabel = (c: Condition) => CONDITIONS.find((x) => x.value === c)?.label ?? c

const LETTERS = ['XS', 'S', 'M', 'L', 'XL', 'XXL']
const range = (from: number, to: number, step = 1) => {
  const out: string[] = []
  for (let n = from; n <= to + 1e-9; n += step) out.push(String(n))
  return out
}

/** The size vocabulary from docs/API.md, per category. */
export function sizesFor(category: Category | '' | null): string[] {
  switch (category) {
    case 'tops':
    case 'outerwear':
    case 'dresses':
      return LETTERS
    case 'bottoms':
      return [...range(24, 40), ...LETTERS]
    case 'shoes':
      return range(5, 14, 0.5)
    case 'accessories':
    case 'bags':
      return ['One size']
    default:
      return [...LETTERS, 'One size']
  }
}

export const TOP_SIZES = LETTERS
export const BOTTOM_SIZES = [...range(24, 40), ...LETTERS]
export const SHOE_SIZES = range(5, 14, 0.5)

export const REQUEST_STATUS_LABEL: Record<RequestStatus, string> = {
  pending: 'Pending',
  accepted: 'Accepted',
  declined: 'Declined',
  cancelled: 'Cancelled',
  completed: 'Completed',
}

export const LISTING_STATUS_LABEL: Record<ListingStatus, string> = {
  active: 'Active',
  pending: 'Pending exchange',
  completed: 'Completed',
  hidden: 'Hidden after reports',
}

/** Field limits from docs/API.md; the server checks them too. */
export const LIMITS = {
  title: 120,
  size: 20,
  color: 60,
  brand: 80,
  conditionNote: 140,
  description: 2000,
  tags: 10,
  tagLength: 30,
  note: 280,
  message: 1000,
  report: 200,
  name: 80,
  photos: 5,
  scanPhotos: 3,
}
