import { Link } from 'react-router-dom'
import { Logo } from '../../components/Logo'
import { useDocumentTitle } from '../../lib/hooks'

const STEPS = [
  { n: '1', title: 'Snap it', body: 'Three quick photos: front, back, and the tag.' },
  { n: '2', title: 'AI writes the listing', body: 'Title, size, brand, condition and tags, filled in for you.' },
  { n: '3', title: 'A classmate picks it up', body: 'Swap it, give it away, or donate it. Meet on campus.' },
]

export default function Landing() {
  useDocumentTitle(null)
  return (
    <div className="landing">
      <header className="landing-bar">
        <Logo height={30} />
        <Link to="/signin" className="btn btn-ghost btn-small">Sign in</Link>
      </header>

      <section className="hero">
        <p className="eyebrow">Clothes, swapped on your campus</p>
        <h1 className="hero-title">
          Keep clothes out of landfills. <span className="hl">Make them cheaper</span> for students.
        </h1>
        <p className="hero-sub">
          Loop is where college students swap, give away and donate clothes with people down the hall.
          Everything stays on your own campus, so pickup is a walk to the library.
        </p>
        <div className="hero-actions">
          <Link to="/signin" className="btn btn-primary btn-large">Sign in with your .edu</Link>
          <span className="muted small">No password. Just your school email.</span>
        </div>
      </section>

      <section className="how" aria-labelledby="how-title">
        <h2 id="how-title" className="sr-only">How it works</h2>
        <ol className="how-grid">
          {STEPS.map((s) => (
            <li key={s.n} className="how-step">
              <span className="how-n">{s.n}</span>
              <h3>{s.title}</h3>
              <p className="muted">{s.body}</p>
            </li>
          ))}
        </ol>
      </section>

      <footer className="landing-foot muted small">Built by team Stacked. Loop is also on iPhone.</footer>
    </div>
  )
}
