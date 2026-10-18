import { createContext, useCallback, useContext, useMemo, useRef, useState, type ReactNode } from 'react'

interface ToastItem {
  id: number
  text: string
  tone: 'info' | 'error'
}
const Ctx = createContext<(text: string, tone?: 'info' | 'error') => void>(() => {})

export function ToastProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<ToastItem[]>([])
  const nextId = useRef(1)
  const push = useCallback((text: string, tone: 'info' | 'error' = 'info') => {
    const id = nextId.current++
    setItems((l) => [...l, { id, text, tone }])
    window.setTimeout(() => setItems((l) => l.filter((t) => t.id !== id)), 3500)
  }, [])
  const value = useMemo(() => push, [push])
  return (
    <Ctx.Provider value={value}>
      {children}
      <div className="toasts" role="status" aria-live="polite">
        {items.map((t) => (
          <div key={t.id} className={`toast toast-${t.tone}`}>
            {t.text}
          </div>
        ))}
      </div>
    </Ctx.Provider>
  )
}

export const useToast = () => useContext(Ctx)
