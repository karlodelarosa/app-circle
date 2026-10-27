import { Check, UsersRound } from "lucide-react";
import { useState, type FormEvent } from "react";
import { Link, useLocation, useParams } from "react-router-dom";
import { supabase } from "../lib/supabase";
import { submitCellGroupSignup } from "../services/public";
import type { CellGroupSignupInput } from "../types";

type SignupPrefill = Partial<CellGroupSignupInput>;

const emptyForm: CellGroupSignupInput = {
  firstName: "",
  lastName: "",
  birthdate: "",
  phone: "",
  facebookContact: "",
  consent: false,
};

export function CellGroupSignupPage() {
  const { orgSlug = "" } = useParams();
  const location = useLocation();
  const prefill = (location.state as { signupPrefill?: SignupPrefill } | null)
    ?.signupPrefill;
  const [form, setForm] = useState<CellGroupSignupInput>({
    ...emptyForm,
    ...prefill,
    consent: false,
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [done, setDone] = useState(false);
  const today = new Date().toISOString().slice(0, 10);

  const submit = (event: FormEvent) => {
    event.preventDefault();
    if (!form.phone.trim() && !form.facebookContact.trim()) {
      setError("Add a mobile number or Facebook contact.");
      return;
    }
    setBusy(true);
    setError("");
    void submitCellGroupSignup(supabase, orgSlug, form)
      .then(() => setDone(true))
      .catch(() => setError("Your signup could not be completed. Please check your details and try again."))
      .finally(() => setBusy(false));
  };

  return (
    <main className="public-section">
      <div className="mx-auto grid max-w-5xl overflow-hidden rounded-[2rem] border border-line bg-paper lg:grid-cols-[.78fr_1.22fr]">
        <div className="bg-[#F0EBDD] p-7 sm:p-10">
          <UsersRound className="text-olive" size={28} />
          <p className="page-kicker mt-7">A place to belong</p>
          <h1 className="mt-2 font-display text-5xl leading-none sm:text-6xl">
            Sign up for a Cell Group
          </h1>
          <p className="mt-6 leading-7 text-muted">
            Share a few details and a Cell Group leader can place you in a
            group. You can still visit public gatherings while you wait.
          </p>
          <p className="mt-5 text-sm leading-6 text-muted">
            This signup does not reserve a seat or limit who may attend a
            gathering.
          </p>
        </div>
        <div className="p-7 sm:p-10">
          {done ? (
            <div className="py-8" role="status">
              <span className="grid h-14 w-14 place-items-center rounded-full bg-sage/30 text-olive">
                <Check size={28} />
              </span>
              <h2 className="mt-5 font-display text-4xl">Your signup was received.</h2>
              <p className="mt-3 max-w-md leading-7 text-muted">
                A Cell Group leader can now help place you in a group. You’re
                welcome at public gatherings in the meantime.
              </p>
              <Link className="primary-button mt-7" to={`/${orgSlug}/gatherings`}>
                See upcoming gatherings
              </Link>
            </div>
          ) : (
            <form className="space-y-5" onSubmit={submit}>
              <div className="grid gap-4 sm:grid-cols-2">
                <label className="field-label">
                  First name
                  <input
                    className="field"
                    required
                    maxLength={80}
                    autoComplete="given-name"
                    value={form.firstName}
                    onChange={(event) => setForm({ ...form, firstName: event.target.value })}
                  />
                </label>
                <label className="field-label">
                  Last name
                  <input
                    className="field"
                    required
                    maxLength={80}
                    autoComplete="family-name"
                    value={form.lastName}
                    onChange={(event) => setForm({ ...form, lastName: event.target.value })}
                  />
                </label>
              </div>
              <label className="field-label">
                Birthday
                <input
                  className="field"
                  type="date"
                  required
                  min="1900-01-01"
                  max={today}
                  autoComplete="bday"
                  value={form.birthdate}
                  onChange={(event) => setForm({ ...form, birthdate: event.target.value })}
                />
              </label>
              <div className="grid gap-4 sm:grid-cols-2">
                <label className="field-label">
                  Mobile number
                  <input
                    className="field"
                    type="tel"
                    maxLength={40}
                    autoComplete="tel"
                    value={form.phone}
                    onChange={(event) => setForm({ ...form, phone: event.target.value })}
                  />
                </label>
                <label className="field-label">
                  Facebook link or username
                  <input
                    className="field"
                    maxLength={300}
                    value={form.facebookContact}
                    onChange={(event) => setForm({ ...form, facebookContact: event.target.value })}
                  />
                </label>
              </div>
              <p className="text-xs leading-5 text-muted">
                Add at least one contact method so a leader can reach you.
              </p>
              <label className="flex items-start gap-3 text-sm leading-6 text-muted">
                <input
                  className="mt-1 h-4 w-4 shrink-0"
                  type="checkbox"
                  required
                  checked={form.consent}
                  onChange={(event) => setForm({ ...form, consent: event.target.checked })}
                />
                I agree that the church may store these details and contact me
                about Cell Group placement.
              </label>
              {error && <p className="form-error" role="alert">{error}</p>}
              <button className="primary-button min-h-11 w-full justify-center" disabled={busy || !form.consent}>
                {busy ? "Submitting…" : "Submit my signup"}
              </button>
            </form>
          )}
        </div>
      </div>
    </main>
  );
}
