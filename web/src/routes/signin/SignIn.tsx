import { useState, type FormEvent } from 'react'
import { Link, Navigate, useLocation, useNavigate } from 'react-router-dom'
import { ApiError } from '../../api/client'
import { useAuth } from '../../auth/AuthContext'
import { Logo } from '../../components/Logo'
import { useDocumentTitle } from '../../lib/hooks'

const DEMO = [
  { email: 'jordan.park@vanderbilt.edu', label: 'Jordan Park', sub: 'Kissam' },
  { email: 'sam.lee@vanderbilt.edu', label: 'Sam Lee', sub: 'Zeppos' },
  { email: 'riley.chen@vanderbilt.edu', label: 'Riley Chen', sub: 'E. Bronson Ingram' },
]

export default function SignIn() {
  useDocumentTitle('Sign in')
  const { user, signIn } = useAuth()
  const nav = useNavigate()
  const loc = useLocation()
  const from = (loc.state as { from?: string } | null)?.from
  const [email, setEmail] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [handled, setHandled] = useState(false)

  // Already signed in (and not in the middle of signing in here): skip the form.
  if (user && !handled) return <Navigate to={from ?? '/feed'} replace />

  async function go(address: string) {
    setError(null)
    setBusy(true)
    setHandled(true)
    try {
      const { isNew, user: u } = await signIn(address.trim())
      nav(isNew || !u.name ? '/welcome' : from ?? '/feed', { replace: true })
    } catch (e) {
      setHandled(false)
      setError(e instanceof ApiError ? e.message : 'Something went wrong. Try again.')
      setBusy(false)
    }
  }

  function submit(e: FormEvent) {
    e.preventDefault()
    if (!email.trim()) return setError('Enter your school email.')
    go(email)
  }

  return (
    <div className="signin">
      <Link to="/" aria-label="Loop home" className="signin-logo"><Logo height={34} /></Link>
      <form className="signin-card" onSubmit={submit} noValidate>
        <h1>Sign in</h1>
        <p className="muted">Use your college .edu email. We'll put you on your campus's feed.</p>
        <div className="field">
          <label htmlFor="email">School email</label>
          <input
            id="email"
            className="input"
            type="email"
            inputMode="email"
            autoComplete="email"
            autoCapitalize="none"
            autoFocus
            placeholder="you@school.edu"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            aria-invalid={!!error}
            aria-describedby={error ? 'email-error' : undefined}
          />
          {error && <p id="email-error" className="field-error" role="alert">{error}</p>}
        </div>
        <button className="btn btn-primary btn-block btn-large" disabled={busy}>
          {busy ? 'Signing in…' : 'Continue'}
        </button>
      </form>

      {import.meta.env.DEV && (
        <div className="demo-box">
          <p className="small muted">Development only: demo accounts</p>
          <div className="demo-list">
            {DEMO.map((d) => (
              <button key={d.email} className="btn btn-ghost btn-small" disabled={busy} onClick={() => go(d.email)}>
                {d.label} <span className="muted">· {d.sub}</span>
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
