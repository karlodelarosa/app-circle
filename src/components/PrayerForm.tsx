import { useState } from 'react'
import { useCircles } from '../AppContext'
import type { PrayerCategory } from '../types'

const categories: PrayerCategory[] = ['Family', 'Work or School', 'Health', 'Spiritual Growth', 'Other']

export function PrayerForm({ onDone }: { onDone: () => void }) {
  const { addPrayer, data } = useCircles()
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [category, setCategory] = useState<PrayerCategory>('Spiritual Growth')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const submit = async (event: React.FormEvent) => {
    event.preventDefault()
    setBusy(true); setError('')
    try { await addPrayer({ title, description, category }); onDone() }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'Prayer could not be shared.') }
    finally { setBusy(false) }
  }
  return (
    <form onSubmit={submit} className="space-y-5">
      <label className="field-label">What can we pray for?<input className="field" value={title} onChange={(e) => setTitle(e.target.value)} required maxLength={100} placeholder="A short, clear title" autoFocus /></label>
      <label className="field-label">Share a little more<textarea className="field min-h-28 resize-y" value={description} onChange={(e) => setDescription(e.target.value)} maxLength={800} placeholder="Details your circle can hold in prayer" /></label>
      <fieldset><legend className="field-label mb-2">Category</legend><div className="flex flex-wrap gap-2">{categories.map((item) => <button type="button" key={item} onClick={() => setCategory(item)} className={`choice-chip ${category === item ? 'choice-chip-active' : ''}`}>{item}</button>)}</div></fieldset>
      {error && <p className="form-error">{error}</p>}
      <button disabled={busy} className="primary-button w-full">{busy ? 'Sharing…' : 'Share with my circle'}</button>
      <p className="text-center text-xs text-muted">Only members of {data?.group?.name ?? 'your circle'} can see this.</p>
    </form>
  )
}
