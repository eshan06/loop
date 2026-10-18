// Types match docs/API.md (contract v1). Nullable fields are always present as null.

export type ShareType = 'swap' | 'free' | 'donate'
export type Condition = 'new' | 'like_new' | 'good' | 'worn'
export type Category = 'tops' | 'bottoms' | 'outerwear' | 'dresses' | 'shoes' | 'accessories' | 'bags'
export type ListingStatus = 'active' | 'pending' | 'completed' | 'hidden'
export type PhotoKind = 'front' | 'back' | 'label' | 'other' | 'avatar'
export type RequestStatus = 'pending' | 'accepted' | 'declined' | 'completed' | 'cancelled'
export type NotificationType =
  | 'request_received'
  | 'request_accepted'
  | 'request_declined'
  | 'new_message'
  | 'badge_earned'
export type ScanSource = 'vision' | 'labels' | 'none'
export type EventKind = 'swap_day' | 'donation_drive' | 'repair_workshop'

export interface Sizes {
  top: string | null
  bottom: string | null
  shoe: string | null
}

export interface User {
  id: number
  name: string | null
  email: string
  campus: { id: number; name: string }
  dorm: string | null
  class_year: number | null
  sizes: Sizes
  avatar_url: string | null
  items_shared: number
  created_at: string
}

export interface Owner {
  id: number
  name: string | null
  dorm: string | null
  avatar_url: string | null
  items_shared: number
}

export interface Photo {
  id: number
  url: string
  kind: PhotoKind
}

export interface MeetupSpot {
  id: number
  name: string
  lat: number | null
  lng: number | null
}

export interface Impact {
  textile_kg: number
  water_l: number
  co2_kg: number
}

export interface Listing {
  id: number
  title: string
  category: Category
  size: string | null
  color: string | null
  brand: string | null
  condition: Condition
  condition_note: string | null
  description: string | null
  tags: string[]
  share_type: ShareType
  status: ListingStatus
  photos: Photo[]
  meetup_spot: MeetupSpot | null
  owner: Owner
  impact: Impact
  is_mine: boolean
  saved_by_me: boolean
  my_request_status: RequestStatus | null
  my_request_id: number | null
  pending_request_count: number
  accepted_request_id: number | null
  created_at: string
}

export interface ScanDraft {
  title: string | null
  category: Category | null
  size: string | null
  color: string | null
  brand: string | null
  condition: Condition | null
  condition_note: string | null
  description: string | null
  tags: string[]
}

export interface ScanResult {
  photos: Photo[]
  draft: ScanDraft
  source: ScanSource
}

export interface RequestListing {
  id: number
  title: string
  photo_url: string
  share_type: ShareType
  status: ListingStatus
}

export interface LoopRequest {
  id: number
  listing: RequestListing
  requester: Owner
  owner: Owner
  note: string | null
  status: RequestStatus
  unread_messages: number
  created_at: string
  updated_at: string
}

export interface Message {
  id: number
  request_id: number
  sender_id: number
  body: string
  created_at: string
}

export interface LoopNotification {
  id: number
  type: NotificationType
  title: string
  body: string | null
  request_id: number | null
  listing_id: number | null
  read: boolean
  created_at: string
}

export interface Unread {
  notifications: number
  messages: number
  incoming_requests: number
}

export interface Paged<T> {
  items: T[]
  total: number
  next_offset: number | null
}

export interface NotificationPage extends Paged<LoopNotification> {
  unread: number
}

export interface ImpactMe {
  items_shared: number
  items_received: number
  textile_kg: number
  water_l: number
  co2_kg: number
}

export interface ImpactCampus {
  items_rehomed: number
  textile_kg: number
  water_l: number
  co2_kg: number
  top_dorm: string | null
}

export interface Badge {
  id: string
  name: string
  description: string
  earned_at: string | null
  progress: number
  goal: number
}

export interface LeaderboardRow {
  rank: number
  dorm: string
  items_shared: number
}

export interface StyleIdea {
  title: string
  description: string
}

export interface CampusEvent {
  id: number
  title: string
  description: string | null
  kind: EventKind
  status: 'upcoming' | 'live' | 'ended'
  is_live: boolean
  starts_at: string
  ends_at: string
  location_name: string
  lat: number | null
  lng: number | null
}

export interface DonationBin {
  id: number
  name: string
  description: string | null
  accepts: string | null
  hours: string | null
  lat: number
  lng: number
}

export interface ListingInput {
  title: string
  category: Category
  size: string | null
  color: string | null
  brand: string | null
  condition: Condition
  condition_note: string | null
  description: string | null
  tags: string[]
  share_type: ShareType
  meetup_spot_id: number
  photo_ids: number[]
}
