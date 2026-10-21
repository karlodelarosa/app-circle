import { Check, Heart, MessageCircleHeart, Plus, Sparkles } from 'lucide-react'
import { useState } from 'react'
import { useCircles } from '../AppContext'
import { Modal } from '../components/Modal'
import { PrayerForm } from '../components/PrayerForm'
import { relativeDate } from '../lib/format'
import type { PrayerRequest } from '../types'

function AnswerForm({ prayer, onDone }: { prayer: PrayerRequest; onDone: () => void }) {
  const { markAnswered } = useCircles()
  const [notes, setNotes] = useState('')
  const [busy, setBusy] = useState(false)
  return <form onSubmit={(event) => { event.preventDefault(); setBusy(true); void markAnswered(prayer.id, notes).then(onDone).finally(() => setBusy(false)) }} className="space-y-5"><p className="leading-6 text-muted">Share the good news your circle can celebrate with you.</p><label className="field-label">Praise note<textarea className="field min-h-28" required value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="How did God answer?" autoFocus /></label><button className="primary-button w-full" disabled={busy}>{busy ? 'Saving…' : 'Share praise report'}</button></form>
}

export function PrayerPage() {
  const { data, togglePrayer } = useCircles()
  const [composer, setComposer] = useState(false)
  const [answering, setAnswering] = useState<PrayerRequest | null>(null)
  const [showAnswered, setShowAnswered] = useState(false)
  if (!data) return null
  const canParticipate = Boolean(data.currentUser.personId)
  const prayers = data.prayers.filter((item) => item.isAnswered === showAnswered)
  return <div>
    <div className="page-heading"><div><p className="page-kicker">Held among friends</p><h1>Prayer</h1><p>A private wall for the things we’re carrying together.</p></div>{canParticipate && <button className="primary-button" onClick={() => setComposer(true)}><Plus size={17} /> Share a request</button>}</div>
    <div className="mt-8 flex border-b border-line"><button onClick={() => setShowAnswered(false)} className={`tab-button ${!showAnswered ? 'tab-button-active' : ''}`}>In prayer</button><button onClick={() => setShowAnswered(true)} className={`tab-button ${showAnswered ? 'tab-button-active' : ''}`}>Answered</button></div>
    {prayers.length ? <div className="mt-6 columns-1 gap-5 md:columns-2">{prayers.map((prayer) => {
      const mayAnswer = data.currentUser.role === 'admin' || data.group?.role === 'leader' || data.currentUser.personId === prayer.userId
      return <article key={prayer.id} className="prayer-card mb-5 break-inside-avoid"><div className="flex items-center justify-between gap-3"><span className="category-label">{prayer.category}</span><span className="text-xs text-muted">{relativeDate(prayer.createdAt)}</span></div><h2>{prayer.title}</h2><p>{prayer.description}</p>{prayer.isAnswered && prayer.answeredNotes && <div className="praise-note"><Sparkles size={17} /><div><strong>Praise report</strong><p>{prayer.answeredNotes}</p></div></div>}<div className="mt-6 flex items-center justify-between border-t border-line pt-4"><div><div className="text-sm font-medium">{prayer.authorName}</div><div className="text-xs text-muted">{prayer.prayerCount} {prayer.prayerCount === 1 ? 'person has' : 'people have'} prayed</div></div>{canParticipate && <button onClick={() => void togglePrayer(prayer.id)} className={`prayed-button ${prayer.prayedByMe ? 'prayed-button-active' : ''}`} aria-pressed={prayer.prayedByMe}>{prayer.prayedByMe ? <Check size={16} /> : <Heart size={16} />}{prayer.prayedByMe ? 'Prayed' : 'I prayed'}</button>}</div>{!prayer.isAnswered && mayAnswer && <button onClick={() => setAnswering(prayer)} className="mt-4 text-xs font-medium text-olive hover:underline">Mark as answered</button>}</article>
    })}</div> : <div className="empty-state mt-8"><MessageCircleHeart /><h2>{showAnswered ? 'Praise reports will live here' : 'Nothing shared yet'}</h2><p>{showAnswered ? 'When a prayer is answered, your circle can celebrate it together.' : 'Share what you would like your circle to hold in prayer.'}</p>{!showAnswered && canParticipate && <button className="secondary-button" onClick={() => setComposer(true)}>Share the first request</button>}</div>}
    {composer && <Modal title="Please pray with me" onClose={() => setComposer(false)}><PrayerForm onDone={() => setComposer(false)} /></Modal>}
    {answering && <Modal title="Mark as answered" onClose={() => setAnswering(null)}><AnswerForm prayer={answering} onDone={() => setAnswering(null)} /></Modal>}
  </div>
}
