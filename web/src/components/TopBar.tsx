import { useEffect, useRef, useState, type FormEvent } from 'react'
import { Link, NavLink, useLocation, useNavigate, useSearchParams } from 'react-router-dom'
import { useAuth, useUser } from '../auth/AuthContext'
import { useUnread } from '../auth/UnreadContext'
import { Avatar } from './Avatar'
import { InboxIcon, MenuIcon, PlusIcon, SearchIcon } from './Icons'
import { Logo } from './Logo'
import { NotificationBell } from './NotificationBell'
import { displayName } from '../lib/format'

const MENU_LINKS = [
  { to: '/profile', label: 'Profile' },
  { to: '/saved', label: 'Saved' },
  { to: '/impact', label: 'Impact' },
  { to: '/leaderboard', label: 'Leaderboard' },
  { to: '/events', label: 'Events' },
  { to: '/map', label: 'Map' },
]

export function TopBar() {
  const user = useUser()
  const { signOut } = useAuth()
  const { unread } = useUnread()
  const nav = useNavigate()
  const loc = useLocation()
  const [params] = useSearchParams()
  const urlQ = loc.pathname === '/feed' ? params.get('q') ?? '' : ''
  const [q, setQ] = useState(urlQ)
  const [menu, setMenu] = useState(false)
  const [mobileSearch, setMobileSearch] = useState(false)
  const menuWrap = useRef<HTMLDivElement>(null)
  const searchRef = useRef<HTMLInputElement>(null)
  const inboxCount = unread.messages + unread.incoming_requests

  useEffect(() => setQ(urlQ), [urlQ])
  useEffect(() => {
    setMenu(false)
    setMobileSearch(false)
  }, [loc.pathname])
  useEffect(() => {
    if (mobileSearch) searchRef.current?.focus()
  }, [mobileSearch])

  useEffect(() => {
    if (!menu) return
    const onDoc = (e: MouseEvent) => {
      if (!menuWrap.current?.contains(e.target as Node)) setMenu(false)
    }
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setMenu(false)
    document.addEventListener('mousedown', onDoc)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('mousedown', onDoc)
      document.removeEventListener('keydown', onKey)
    }
  }, [menu])

  function submit(e: FormEvent) {
    e.preventDefault()
    const term = q.trim()
    nav(term ? `/feed?q=${encodeURIComponent(term)}` : '/feed')
    setMobileSearch(false)
  }

  return (
    <header className="topbar">
      <div className="topbar-inner">
        <Link to="/feed" className="brand" aria-label="Loop, campus feed">
          <Logo height={26} />
          <span className="brand-campus">{user.campus.name}</span>
        </Link>

        <form className={`search${mobileSearch ? ' search-open' : ''}`} onSubmit={submit} role="search">
          <SearchIcon width={18} height={18} />
          <input
            ref={searchRef}
            type="search"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Search jackets, brands, tags"
            aria-label="Search listings"
          />
        </form>

        <nav className="topbar-actions" aria-label="Main">
          <button className="icon-btn search-toggle" onClick={() => setMobileSearch((s) => !s)} aria-label="Search">
            <SearchIcon />
          </button>
          <Link to="/post" className="btn btn-lime btn-post">
            <PlusIcon width={18} height={18} />
            <span>Post</span>
          </Link>
          <NavLink to="/inbox" className="icon-btn nav-icon" aria-label={`Inbox${inboxCount ? `, ${inboxCount} new` : ''}`}>
            <InboxIcon />
            {inboxCount > 0 && <span className="badge-count">{inboxCount > 99 ? '99+' : inboxCount}</span>}
          </NavLink>
          <NotificationBell />
          <div className="popwrap" ref={menuWrap}>
            <button className="avatar-btn" onClick={() => setMenu((m) => !m)} aria-expanded={menu} aria-label="Account menu">
              <span className="only-desktop"><Avatar name={user.name} url={user.avatar_url} size={34} /></span>
              <span className="only-mobile"><MenuIcon /></span>
            </button>
            {menu && (
              <div className="popover popover-menu" role="menu">
                <div className="menu-user">
                  <Avatar name={user.name} url={user.avatar_url} size={36} />
                  <div>
                    <strong>{displayName(user.name)}</strong>
                    <span className="muted small">{user.email}</span>
                  </div>
                </div>
                <div className="only-mobile">
                  <Link role="menuitem" className="menu-item" to="/post">Post an item</Link>
                  <Link role="menuitem" className="menu-item" to="/inbox">Inbox{inboxCount ? ` (${inboxCount})` : ''}</Link>
                  <Link role="menuitem" className="menu-item" to="/notifications">Notifications{unread.notifications ? ` (${unread.notifications})` : ''}</Link>
                </div>
                {MENU_LINKS.map((l) => (
                  <Link key={l.to} role="menuitem" className="menu-item" to={l.to}>
                    {l.label}
                  </Link>
                ))}
                <button
                  role="menuitem"
                  className="menu-item menu-signout"
                  onClick={() => {
                    signOut()
                    nav('/')
                  }}
                >
                  Sign out
                </button>
              </div>
            )}
          </div>
        </nav>
      </div>
    </header>
  )
}
