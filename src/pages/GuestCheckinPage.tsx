import { ArrowLeft, Check, Search } from 'lucide-react'
import { useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { Brand } from '../components/AppShell'
import { supabase } from '../lib/supabase'
import { formatDate, formatTime } from '../lib/format'
import { getCheckinContext, guestCheckin } from '../services/circles'

type Context = Awaited<ReturnType<typeof getCheckinContext>>

export function GuestCheckinPage() {
  const [params] = useSearchParams()
  const [code, setCode] = useState((params.get('code') ?? '').toUpperCase())
  const [context, setContext] = useState<Context | null>(null)
  const [form, setForm] = useState({ firstName: '', lastName: '', phone: '', socialContact: '' })
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [complete, setComplete] = useState(false)

  const resolve = async () => {
    if (!supabase) throw new Error('Guest check-in is not configured yet.')
    setContext(await getCheckinContext(supabase, code))
  }

  const submit = async () => {
    if (!supabase) throw new Error('Guest check-in is not configured yet.')
    await guestCheckin(supabase, { code, ...form })
    setComplete(true)
  }

  return <main className="min-h-screen bg-parchment px-5 py-8 text-ink sm:py-14">
    <div className="mx-auto max-w-lg">
      <div className="flex items-center justify-between"><Brand /><Link to="/" className="text-link"><ArrowLeft size={15} /> Member sign in</Link></div>
      <section className="paper-panel mt-10 overflow-hidden">
        <div className="border-b border-line bg-[#F0EBDD] p-6 sm:p-8">
          <p className="page-kicker">Welcome to the table</p>
          <h1 className="mt-2 font-display text-4xl">Guest check-in</h1>
          <p className="mt-2 leading-6 text-muted">Enter the short code your cell leader shared. Checking in records today’s attendance—it does not create an account.</p>
        </div>
        <div className="p-6 sm:p-8">
          {!context ? <form onSubmit={(event) => { event.preventDefault(); setBusy(true); setError(''); void resolve().catch((cause) => setError(cause instanceof Error ? cause.message : 'Code not found.')).finally(() => setBusy(false)) }} className="space-y-5">
            <label className="field-label">Gathering code<input className="field text-center font-mono text-xl uppercase tracking-[.3em]" value={code} onChange={(event) => setCode(event.target.value.replace(/[^a-z0-9]/gi, '').slice(0, 6).toUpperCase())} required minLength={6} autoFocus placeholder="ABC123" /></label>
            {error && <p className="form-error">{error}</p>}
            <button className="primary-button w-full" disabled={busy}><Search size={17} /> {busy ? 'Checking…' : 'Find gathering'}</button>
          </form> : complete ? <div className="py-8 text-center"><span className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-sage/30 text-olive"><Check size={28} /></span><h2 className="mt-5 font-display text-3xl">You’re checked in.</h2><p className="mt-2 text-muted">Welcome to {context.groupName}. We’re glad you’re here.</p></div> : <div>
            <div className="border-b border-line pb-5"><div className="text-xs uppercase tracking-[.14em] text-muted">{context.organizationName}</div><h2 className="mt-2 font-display text-3xl">{context.gatheringTitle}</h2><p className="mt-2 text-sm text-muted">{context.groupName} · {formatDate(context.startsAt)} at {formatTime(context.startsAt)}</p></div>
            <form onSubmit={(event) => { event.preventDefault(); setBusy(true); setError(''); void submit().catch((cause) => setError(cause instanceof Error ? cause.message : 'Check-in failed.')).finally(() => setBusy(false)) }} className="mt-6 space-y-4">
              <div className="grid grid-cols-2 gap-3"><label className="field-label">First name<input className="field" value={form.firstName} onChange={(event) => setForm({ ...form, firstName: event.target.value })} required /></label><label className="field-label">Last name<input className="field" value={form.lastName} onChange={(event) => setForm({ ...form, lastName: event.target.value })} required /></label></div>
              <label className="field-label">Mobile number<input className="field" type="tel" value={form.phone} onChange={(event) => setForm({ ...form, phone: event.target.value })} placeholder="Optional if you add a social contact" /></label>
              <label className="field-label">Social contact<input className="field" value={form.socialContact} onChange={(event) => setForm({ ...form, socialContact: event.target.value })} placeholder="Messenger, Instagram, or another contact" /></label>
              {error && <p className="form-error">{error}</p>}
              <button className="primary-button w-full" disabled={busy}>{busy ? 'Checking in…' : 'Check in as a guest'}</button>
            </form>
          </div>}
        </div>
      </section>
    </div>
  </main>
}
