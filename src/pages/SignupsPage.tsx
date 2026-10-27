import { Cake, Facebook, Phone, UserRoundCheck, UsersRound } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { useCircles } from "../AppContext";
import { getErrorMessage } from "../lib/errors";
import { supabase } from "../lib/supabase";
import { loadCellGroupSignups, placeCellGroupSignup } from "../services/circles";
import type { CellGroupSignup } from "../types";

const demoSignups: CellGroupSignup[] = [{
  id: "demo-signup", organizationId: "demo-org", personId: "demo-prospect",
  firstName: "Jamie", lastName: "Rivera", fullName: "Jamie Rivera",
  birthdate: "1998-06-14", phone: "+63 917 555 0198",
  facebookContact: "facebook.com/jamie.rivera", status: "unassigned", source: "public",
  consentedAt: new Date().toISOString(), createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(),
}];

const ageOn = (birthdate: string) => {
  const born = new Date(`${birthdate}T00:00:00`);
  const today = new Date();
  let age = today.getFullYear() - born.getFullYear();
  if (today.getMonth() < born.getMonth() || (today.getMonth() === born.getMonth() && today.getDate() < born.getDate())) age -= 1;
  return age;
};

const sourceLabel: Record<CellGroupSignup["source"], string> = {
  public: "Public signup",
  guest_self: "Signed up after RSVP",
  leader_conversion: "Converted by a leader",
};

const facebookHref = (contact: string) => /^https?:\/\//i.test(contact)
  ? contact
  : `https://facebook.com/${contact.replace(/^@/, "")}`;

export function SignupsPage() {
  const { data, demoMode, refresh } = useCircles();
  const [signups, setSignups] = useState<CellGroupSignup[]>([]);
  const [destinations, setDestinations] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [busyId, setBusyId] = useState("");
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const manageableGroups = useMemo(
    () => data?.groups.filter((group) => data.currentUser.role === "admin" || group.role === "leader") ?? [],
    [data],
  );

  useEffect(() => {
    if (!data) return;
    setLoading(true);
    setError("");
    const request = demoMode || !supabase
      ? Promise.resolve(demoSignups)
      : loadCellGroupSignups(supabase, data.organization.id);
    void request
      .then((items) => {
        setSignups(items);
        if (manageableGroups.length === 1) {
          setDestinations(Object.fromEntries(items.map((item) => [item.id, manageableGroups[0].id])));
        }
      })
      .catch((cause) => setError(getErrorMessage(cause, "Cell Group signups could not be loaded.")))
      .finally(() => setLoading(false));
  }, [data?.organization.id, demoMode, manageableGroups.length]);

  if (!data) return null;

  const place = async (signup: CellGroupSignup) => {
    const groupId = destinations[signup.id];
    if (!groupId) return;
    setBusyId(signup.id);
    setError("");
    setMessage("");
    try {
      if (!demoMode && supabase) await placeCellGroupSignup(supabase, signup.id, groupId);
      const groupName = manageableGroups.find((group) => group.id === groupId)?.name || "the Circle";
      setSignups((items) => items.filter((item) => item.id !== signup.id));
      setMessage(`${signup.fullName} was placed in ${groupName}. Their SheepCount classification remains Prospect.`);
      if (!demoMode) await refresh();
    } catch (cause) {
      setError(getErrorMessage(cause, "This signup could not be placed."));
    } finally {
      setBusyId("");
    }
  };

  return <div>
    <div className="page-heading"><div><p className="page-kicker">A shared next step</p><h1>Cell Group signups</h1><p>Place official, unassigned Prospects into a Circle you lead.</p></div></div>
    {message && <p className="mt-6 rounded-xl bg-sage/20 p-4 text-sm text-olive" role="status">{message}</p>}
    {error && <p className="form-error mt-6" role="alert">{error}</p>}
    {loading ? <div className="mt-8 space-y-3" aria-busy="true" aria-label="Loading Cell Group signups"><div className="h-28 animate-pulse rounded-2xl bg-paper" /><div className="h-28 animate-pulse rounded-2xl bg-paper" /></div>
      : signups.length ? <div className="mt-8 divide-y divide-line border-y border-line">{signups.map((signup) => <article key={signup.id} className="grid gap-5 py-7 lg:grid-cols-[1fr_auto] lg:items-center">
        <div className="min-w-0"><div className="flex flex-wrap items-center gap-3"><h2 className="font-display text-3xl">{signup.fullName}</h2><span className="role-label">{sourceLabel[signup.source]}</span></div>
          <div className="mt-3 flex flex-wrap gap-x-5 gap-y-2 text-sm text-muted"><span className="inline-flex items-center gap-2"><Cake size={15} /> {signup.birthdate} · age {ageOn(signup.birthdate)}</span>{signup.phone && <a className="inline-flex items-center gap-2 hover:text-olive" href={`tel:${signup.phone}`}><Phone size={15} /> {signup.phone}</a>}{signup.facebookContact && <a className="inline-flex items-center gap-2 hover:text-olive" href={facebookHref(signup.facebookContact)} target="_blank" rel="noreferrer"><Facebook size={15} /> {signup.facebookContact}</a>}</div>
          {signup.birthdateDiscrepancy && <p className="mt-3 text-sm text-amber-800" role="note">Submitted birthday {signup.birthdateDiscrepancy} differs from the existing People record. Review it before placement.</p>}
          <p className="mt-3 text-xs text-muted">Received {new Date(signup.createdAt).toLocaleDateString()}</p></div>
        <div className="grid gap-3 sm:grid-cols-[minmax(13rem,1fr)_auto] lg:min-w-[25rem]"><label className="field-label">Place {signup.fullName} in<select className="field" aria-label={`Place ${signup.fullName} in`} value={destinations[signup.id] ?? ""} onChange={(event) => setDestinations({ ...destinations, [signup.id]: event.target.value })}><option value="">Choose a Circle</option>{manageableGroups.map((group) => <option key={group.id} value={group.id}>{group.name}</option>)}</select></label>
          <button className="primary-button self-end" disabled={busyId === signup.id || !destinations[signup.id]} onClick={() => void place(signup)}><UserRoundCheck size={16} /> {busyId === signup.id ? "Placing…" : "Place in Circle"}</button></div>
      </article>)}</div>
      : <div className="empty-state mt-8 border-y border-line" role="status"><UsersRound /><h2>No unassigned signups</h2><p>New official Cell Group signups will appear here.</p></div>}
  </div>;
}
