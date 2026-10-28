import { X } from 'lucide-react'
import { useEffect, useId, useRef, type ReactNode } from 'react'

export function Modal({ title, children, onClose }: { title: string; children: ReactNode; onClose: () => void }) {
  const panelRef = useRef<HTMLDivElement>(null)
  const returnFocusRef = useRef<HTMLElement | null>(document.activeElement as HTMLElement | null)
  const titleId = useId()
  useEffect(() => {
    const returnFocus = returnFocusRef.current
    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose()
      if (event.key !== 'Tab') return
      const focusable = Array.from(panelRef.current?.querySelectorAll<HTMLElement>(
        'button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), a[href], [tabindex]:not([tabindex="-1"])',
      ) ?? [])
      if (!focusable.length) return
      const first = focusable[0]
      const last = focusable[focusable.length - 1]
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault()
        last.focus()
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault()
        first.focus()
      }
    }
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('keydown', onKey)
      document.body.style.overflow = previousOverflow
      returnFocus?.focus()
    }
  }, [onClose])

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-ink/35 p-0 backdrop-blur-[2px] sm:items-center sm:p-5" role="dialog" aria-modal="true" aria-labelledby={titleId} onMouseDown={(event) => event.target === event.currentTarget && onClose()}>
      <div ref={panelRef} className="max-h-[92vh] w-full overflow-y-auto rounded-t-[1.75rem] border border-line bg-paper p-5 shadow-quiet sm:max-w-lg sm:rounded-[1.75rem] sm:p-7">
        <div className="sticky top-0 z-10 -mt-2 mb-4 flex items-center justify-between bg-paper py-2">
          <h2 id={titleId} className="font-display text-3xl text-ink">{title}</h2>
          <button className="icon-button" onClick={onClose} aria-label="Close" autoFocus><X size={19} /></button>
        </div>
        {children}
      </div>
    </div>
  )
}
