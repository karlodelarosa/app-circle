import { useState } from 'react'
import { useCircles } from '../AppContext'
import type { PrayerCategory, PrayerScope } from '../types'

const categories: PrayerCategory[] = ['Family', 'Work or School', 'Health', 'Spiritual Growth', 'Other']

export function PrayerForm({ onDone }: { onDone: () => void }) {
  const { addPrayer, data } = useCircles()
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [category, setCategory] = useState<PrayerCategory>('Spiritual Growth')
  const [scope, setScope] = useState<PrayerScope>(data?.group ? 'circle' : 'organization')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const submit = async (event: React.FormEvent) => {
    event.preventDefault()
    setBusy(true); setError('')
    try { await addPrayer({ title, description, category, scope }); onDone() }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'Prayer could not be shared.') }
    finally { setBusy(false) }
  }
  return (
    <form onSubmit={submit} className="space-y-5">
      <label className="field-label">What can we pray for?<input className="field" value={title} onChange={(e) => setTitle(e.target.value)} required maxLength={100} placeholder="A short, clear title" /></label>
      <label className="field-label">Share a little more<textarea className="field min-h-28 resize-y" value={description} onChange={(e) => setDescription(e.target.value)} maxLength={800} placeholder="Details your circle can hold in prayer" /></label>
      <fieldset>
        <legend className="field-label">Who should see this prayer?</legend>
        <div className="mt-2 grid gap-2 sm:grid-cols-2">
          <label className={`rounded-2xl border p-4 ${data?.group ? 'cursor-pointer' : 'cursor-not-allowed opacity-60'} ${scope === 'circle' ? 'border-olive bg-parchment' : 'border-line'}`}>
            <span className="flex items-center gap-2 text-sm font-medium">
              <input
                type="radio"
                name="prayer-scope"
                value="circle"
                checked={scope === 'circle'}
                disabled={!data?.group}
                onChange={() => setScope('circle')}
              />
              My Circle — {data?.group?.name ?? 'select a Circle first'}
            </span>
            <span className="mt-2 block text-xs leading-5 text-muted">Only members of this Circle can see it.</span>
          </label>
          <label className={`cursor-pointer rounded-2xl border p-4 ${scope === 'organization' ? 'border-olive bg-parchment' : 'border-line'}`}>
            <span className="flex items-center gap-2 text-sm font-medium">
              <input
                type="radio"
                name="prayer-scope"
                value="organization"
                checked={scope === 'organization'}
                onChange={() => setScope('organization')}
              />
              Entire organization — {data?.organization.name}
            </span>
            <span className="mt-2 block text-xs leading-5 text-muted">Every active member in the organization can see it.</span>
          </label>
        </div>
      </fieldset>
      <fieldset><legend className="field-label mb-2">Category</legend><div className="flex flex-wrap gap-2">{categories.map((item) => <button type="button" key={item} onClick={() => setCategory(item)} className={`choice-chip ${category === item ? 'choice-chip-active' : ''}`}>{item}</button>)}</div></fieldset>
      {error && <p className="form-error">{error}</p>}
      <button disabled={busy} className="primary-button w-full">{busy ? 'Sharing…' : 'Share request'}</button>
      <p className="text-center text-xs text-muted">This prayer stays private inside Circles.</p>
    </form>
  )
}
