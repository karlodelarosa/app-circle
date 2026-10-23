import { X } from 'lucide-react'
import { useEffect, type ReactNode } from 'react'

export function Modal({ title, children, onClose }: { title: string; children: ReactNode; onClose: () => void }) {
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => event.key === 'Escape' && onClose()
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [onClose])

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-ink/35 p-0 backdrop-blur-[2px] sm:items-center sm:p-5" role="dialog" aria-modal="true" aria-labelledby="modal-title" onMouseDown={(event) => event.target === event.currentTarget && onClose()}>
      <div className="max-h-[92vh] w-full overflow-y-auto rounded-t-[1.75rem] border border-line bg-paper p-5 shadow-quiet sm:max-w-lg sm:rounded-[1.75rem] sm:p-7">
        <div className="sticky top-0 z-10 -mt-2 mb-4 flex items-center justify-between bg-paper py-2">
          <h2 id="modal-title" className="font-display text-3xl text-ink">{title}</h2>
          <button className="icon-button" onClick={onClose} aria-label="Close" autoFocus><X size={19} /></button>
        </div>
        {children}
      </div>
    </div>
  )
}
