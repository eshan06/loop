import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { useAuth } from '../auth/AuthContext'
import { UnreadProvider } from '../auth/UnreadContext'
import { ErrorState, FullLoading } from './States'
import { TopBar } from './TopBar'

/** Signed-out users go to /signin and come back; a user with no name yet goes to profile setup first. */
export function RequireAuth() {
  const { user, status, retry } = useAuth()
  const loc = useLocation()
  if (status === 'loading') return <FullLoading />
  if (status === 'error')
    return (
      <div className="center-fill">
        <ErrorState error="Couldn't reach Loop. Check your connection." onRetry={retry} />
      </div>
    )
  if (!user) return <Navigate to="/signin" replace state={{ from: loc.pathname + loc.search }} />
  if (!user.name && loc.pathname !== '/welcome') return <Navigate to="/welcome" replace />
  return <Outlet />
}

/** Top bar plus page content for every signed-in screen. */
export function AppLayout() {
  return (
    <UnreadProvider>
      <TopBar />
      <main className="page">
        <Outlet />
      </main>
    </UnreadProvider>
  )
}

/** Welcome page sits outside the app shell: no top bar until the profile exists. */
export function BareLayout() {
  return (
    <UnreadProvider>
      <Outlet />
    </UnreadProvider>
  )
}

export function PublicOnly() {
  const { user, status } = useAuth()
  if (status === 'loading') return <FullLoading />
  if (user) return <Navigate to="/feed" replace />
  return <Outlet />
}
