import { lazy, Suspense } from 'react'
import { Navigate, Route, Routes } from 'react-router-dom'
import { AppLayout, BareLayout, PublicOnly, RequireAuth } from './components/Layout'
import { FullLoading } from './components/States'
import EditListing from './routes/post/EditListing'
import Post from './routes/post/Post'
import Feed from './routes/feed/Feed'
import Inbox from './routes/inbox/Inbox'
import ItemDetail from './routes/item/ItemDetail'
import Landing from './routes/landing/Landing'
import Events from './routes/misc/Events'
import Impact from './routes/misc/Impact'
import Leaderboard from './routes/misc/Leaderboard'
import NotFoundPage from './routes/misc/NotFoundPage'
import Notifications from './routes/misc/Notifications'
import Saved from './routes/misc/Saved'
import Profile from './routes/profile/Profile'
import ProfileForm from './routes/profile/ProfileForm'
import SignIn from './routes/signin/SignIn'

// Leaflet is only needed on /map.
const MapPage = lazy(() => import('./routes/misc/MapPage'))

export default function App() {
  return (
    <Routes>
      <Route element={<PublicOnly />}>
        <Route path="/" element={<Landing />} />
      </Route>
      <Route path="/signin" element={<SignIn />} />

      <Route element={<RequireAuth />}>
        <Route element={<BareLayout />}>
          <Route path="/welcome" element={<ProfileForm mode="welcome" />} />
        </Route>
        <Route element={<AppLayout />}>
          <Route path="/feed" element={<Feed />} />
          <Route path="/item/:id" element={<ItemDetail />} />
          <Route path="/item/:id/edit" element={<EditListing />} />
          <Route path="/post" element={<Post />} />
          <Route path="/inbox" element={<Inbox />} />
          <Route path="/inbox/:requestId" element={<Inbox />} />
          <Route path="/profile" element={<Profile />} />
          <Route path="/profile/edit" element={<ProfileForm mode="edit" />} />
          <Route path="/saved" element={<Saved />} />
          <Route path="/notifications" element={<Notifications />} />
          <Route path="/impact" element={<Impact />} />
          <Route path="/leaderboard" element={<Leaderboard />} />
          <Route path="/events" element={<Events />} />
          <Route path="/map" element={<Suspense fallback={<FullLoading />}><MapPage /></Suspense>} />
        </Route>
      </Route>

      <Route path="/home" element={<Navigate to="/" replace />} />
      <Route path="*" element={<NotFoundPage />} />
    </Routes>
  )
}
