import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import { ApiError, getToken, setToken, setUnauthorizedHandler } from '../api/client'
import { getMe, login } from '../api/endpoints'
import type { User } from '../api/types'

interface AuthValue {
  user: User | null
  /** 'loading' while we check a saved token; 'error' when the server couldn't be reached. */
  status: 'loading' | 'ready' | 'error'
  signIn: (email: string) => Promise<{ isNew: boolean; user: User }>
  /** Sign in with a token we already hold (after login elsewhere). */
  signOut: () => void
  setUser: (u: User) => void
  retry: () => void
}

const Ctx = createContext<AuthValue | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUserState] = useState<User | null>(null)
  const [status, setStatus] = useState<AuthValue['status']>(getToken() ? 'loading' : 'ready')
  const [attempt, setAttempt] = useState(0)

  useEffect(() => {
    setUnauthorizedHandler(() => setUserState(null))
  }, [])

  useEffect(() => {
    if (!getToken()) {
      setStatus('ready')
      return
    }
    let cancelled = false
    setStatus('loading')
    getMe()
      .then((u) => {
        if (cancelled) return
        setUserState(u)
        setStatus('ready')
      })
      .catch((e) => {
        if (cancelled) return
        // 401 already cleared the token and the user; anything else is a connectivity problem.
        if (e instanceof ApiError && e.status === 401) setStatus('ready')
        else setStatus('error')
      })
    return () => {
      cancelled = true
    }
  }, [attempt])

  const signIn = useCallback(async (email: string) => {
    const res = await login(email)
    setToken(res.token)
    setUserState(res.user)
    setStatus('ready')
    return { isNew: res.is_new, user: res.user }
  }, [])

  const signOut = useCallback(() => {
    setToken(null)
    setUserState(null)
  }, [])

  const retry = useCallback(() => setAttempt((a) => a + 1), [])

  const value = useMemo<AuthValue>(
    () => ({ user, status, signIn, signOut, setUser: setUserState, retry }),
    [user, status, signIn, signOut, retry],
  )
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useAuth(): AuthValue {
  const v = useContext(Ctx)
  if (!v) throw new Error('useAuth outside AuthProvider')
  return v
}

/** The signed-in user. Only call inside routes wrapped by RequireAuth. */
export function useUser(): User {
  const { user } = useAuth()
  if (!user) throw new Error('useUser without a signed-in user')
  return user
}
