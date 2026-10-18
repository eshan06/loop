import { useAuth } from '../../auth/AuthContext'
import { UnreadProvider } from '../../auth/UnreadContext'
import { Logo } from '../../components/Logo'
import { NotFound } from '../../components/States'
import { TopBar } from '../../components/TopBar'
import { Link } from 'react-router-dom'
import { useDocumentTitle } from '../../lib/hooks'

/** Any unknown URL. Inside the app shell when signed in, bare when not. */
export default function NotFoundPage() {
  useDocumentTitle('Not found')
  const { user } = useAuth()
  if (user?.name)
    return (
      <UnreadProvider>
        <TopBar />
        <main className="page"><NotFound /></main>
      </UnreadProvider>
    )
  return (
    <div className="signin">
      <Link to="/" aria-label="Loop home" className="signin-logo"><Logo height={34} /></Link>
      <NotFound />
    </div>
  )
}
