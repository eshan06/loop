import { request } from './client'
import type {
  Badge, Category, CampusEvent, DonationBin, ImpactCampus, ImpactMe, LeaderboardRow, Listing, ListingInput,
  LoopRequest, MeetupSpot, Message, NotificationPage, Paged, PhotoKind, Photo, ScanResult, ShareType, Sizes,
  StyleIdea, Unread, User,
} from './types'

export interface FeedFilters {
  q?: string
  share_type?: ShareType | ''
  category?: Category | ''
  size?: string
}

// ---- auth + me
export const login = (email: string) =>
  request<{ token: string; is_new: boolean; user: User }>('/auth/login', { method: 'POST', json: { email }, auth: false })
export const getMe = () => request<User>('/me')
export interface ProfilePatch {
  name?: string
  dorm?: string | null
  class_year?: number | null
  sizes?: Sizes
  avatar_photo_id?: number | null
}
export const patchMe = (patch: ProfilePatch) => request<User>('/me', { method: 'PATCH', json: patch })
export const getUnread = (signal?: AbortSignal) => request<Unread>('/me/unread', { signal })
export const getDorms = () => request<{ items: string[] }>('/dorms')

// ---- photos + scan
export function uploadPhoto(blob: Blob, kind: PhotoKind) {
  const form = new FormData()
  form.append('file', blob, 'photo.jpg')
  form.append('kind', kind)
  return request<Photo>('/photos', { method: 'POST', form })
}
export function scan(blobs: Blob[], kinds: PhotoKind[]) {
  const form = new FormData()
  blobs.forEach((b, i) => form.append('photos', b, `photo${i + 1}.jpg`))
  form.append('kinds', kinds.join(','))
  return request<ScanResult>('/scan', { method: 'POST', form })
}
export const getMeetupSpots = () => request<{ items: MeetupSpot[] }>('/meetup-spots')

// ---- listings
export const getListings = (f: FeedFilters, offset = 0, limit = 20, signal?: AbortSignal) =>
  request<Paged<Listing>>('/listings', { query: { ...f, offset, limit }, signal })
export const getListing = (id: number | string) => request<Listing>(`/listings/${id}`)
export const createListing = (input: ListingInput) => request<Listing>('/listings', { method: 'POST', json: input })
export const patchListing = (id: number, patch: Partial<ListingInput>) =>
  request<Listing>(`/listings/${id}`, { method: 'PATCH', json: patch })
export const deleteListing = (id: number) => request<void>(`/listings/${id}`, { method: 'DELETE' })
export const getMyListings = (status: 'active' | 'completed', offset = 0, limit = 20) =>
  request<Paged<Listing>>('/me/listings', { query: { status, offset, limit } })

// ---- requests + chat
export const createRequest = (listingId: number, note: string) =>
  request<LoopRequest>(`/listings/${listingId}/requests`, { method: 'POST', json: note ? { note } : {} })
export const getMyRequests = (role: 'incoming' | 'outgoing', offset = 0, limit = 50, signal?: AbortSignal) =>
  request<Paged<LoopRequest>>('/me/requests', { query: { role, offset, limit }, signal })
export const getRequest = (id: number | string, signal?: AbortSignal) => request<LoopRequest>(`/requests/${id}`, { signal })
export const requestAction = (id: number, action: 'accept' | 'decline' | 'complete' | 'cancel') =>
  request<LoopRequest>(`/requests/${id}/${action}`, { method: 'POST' })
export const getMessages = (id: number, afterId?: number, signal?: AbortSignal) =>
  request<{ items: Message[] }>(`/requests/${id}/messages`, { query: { after_id: afterId }, signal })
export const sendMessage = (id: number, body: string) =>
  request<Message>(`/requests/${id}/messages`, { method: 'POST', json: { body } })

// ---- tier 2
export const getImpactMe = () => request<ImpactMe>('/impact/me')
export const getImpactCampus = () => request<ImpactCampus>('/impact/campus')
export const saveListing = (id: number) => request<void>(`/listings/${id}/save`, { method: 'PUT' })
export const unsaveListing = (id: number) => request<void>(`/listings/${id}/save`, { method: 'DELETE' })
export const getSaved = (offset = 0, limit = 20) => request<Paged<Listing>>('/me/saved', { query: { offset, limit } })
export const getSimilar = (id: number, limit = 6) => request<{ items: Listing[] }>(`/listings/${id}/similar`, { query: { limit } })
export const getStyle = (id: number) => request<{ ideas: StyleIdea[] }>(`/listings/${id}/style`, { method: 'POST' })
export const getLeaderboard = () => request<{ items: LeaderboardRow[] }>('/leaderboard/dorms')
export const getBadges = () => request<{ items: Badge[] }>('/me/badges')
export const getNotifications = (offset = 0, limit = 20) =>
  request<NotificationPage>('/notifications', { query: { offset, limit } })
export const markNotificationsRead = (body: { ids: number[] } | { all: true }) =>
  request<void>('/notifications/read', { method: 'POST', json: body })
export const reportListing = (id: number, reason: string) =>
  request<void>(`/listings/${id}/report`, { method: 'POST', json: reason ? { reason } : {} })

// ---- tier 3
export const getEvents = () => request<{ items: CampusEvent[] }>('/events')
export const getDonationBins = () => request<{ items: DonationBin[] }>('/donation-bins')
