import { useState, type FormEvent } from "react";
import { Search, UserPlus, UsersRound } from "lucide-react";
import { useCircles } from "../AppContext";
import { supabase } from "../lib/supabase";
import { getErrorMessage } from "../lib/errors";
import {
  addPersonToGroup,
  registerVisitor,
  searchPeople,
} from "../services/circles";
import type { PersonSearchResult } from "../types";

export function PeoplePage({ compact = false }: { compact?: boolean }) {
  const { data, demoMode, refresh } = useCircles();
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<PersonSearchResult[]>([]);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [visitor, setVisitor] = useState(false);
  const [form, setForm] = useState({
    firstName: "",
    lastName: "",
    email: "",
    phone: "",
  });
  if (!data?.group)
    return (
      <div className="empty-state">
        <UsersRound />
        <h2>Select a Circle first</h2>
      </div>
    );
  const group = data.group;
  const canLead = data.currentUser.role === "admin" || group.role === "leader";
  if (!canLead)
    return (
      <div className="empty-state">
        <UsersRound />
        <h2>Leader access required</h2>
        <p>
          People records are available only to assigned leaders and organization
          administrators.
        </p>
      </div>
    );
  const runSearch = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setMessage("");
    try {
      if (demoMode) {
        setResults(
          data.members
            .filter((m) =>
              m.fullName.toLowerCase().includes(query.toLowerCase()),
            )
            .map((m) => ({
              id: m.id,
              fullName: m.fullName,
              email: m.email,
              phone: "",
              membershipType: "Member",
              alreadyInGroup: true,
            })),
        );
      } else if (supabase)
        setResults(
          await searchPeople(supabase, data.organization.id, group.id, query),
        );
    } catch (c) {
      setMessage(getErrorMessage(c, "Search failed."));
    } finally {
      setBusy(false);
    }
  };
  const add = async (person: PersonSearchResult) => {
    if (demoMode || !supabase) {
      setMessage(`${person.fullName} is already in this demo Circle.`);
      return;
    }
    setBusy(true);
    try {
      await addPersonToGroup(supabase, group.id, person.id);
      setMessage(
        `${person.fullName} was added. This does not provision a login.`,
      );
      await refresh();
    } catch (c) {
      setMessage(getErrorMessage(c, "Person could not be added."));
    } finally {
      setBusy(false);
    }
  };
  const create = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true);
    try {
      if (!demoMode && supabase)
        await registerVisitor(supabase, group.id, form);
      setMessage(
        demoMode
          ? `${form.firstName} was added to this demo session only.`
          : `${form.firstName} was registered as a visitor and added to ${group.name}.`,
      );
      setVisitor(false);
      setForm({ firstName: "", lastName: "", email: "", phone: "" });
      if (!demoMode) await refresh();
    } catch (c) {
      setMessage(getErrorMessage(c, "Visitor could not be registered."));
    } finally {
      setBusy(false);
    }
  };
  return (
    <div>
      <div
        className={
          compact
            ? "flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between"
            : "page-heading"
        }
      >
        <div>
          {!compact && <p className="page-kicker">SheepCount directory</p>}
          {compact && (
            <h2 className="font-display text-2xl">
              Find someone in SheepCount
            </h2>
          )}
          {!compact && <h1>People</h1>}
          <p>
            Search before adding anyone. Official People records stay in
            SheepCount.
          </p>
        </div>
        <button className="primary-button" onClick={() => setVisitor(!visitor)}>
          <UserPlus size={17} /> Register visitor
        </button>
      </div>
      {visitor && (
        <form
          onSubmit={create}
          className="mt-6 grid gap-4 rounded-2xl border border-line bg-parchment p-5 sm:grid-cols-2"
        >
          <h2 className="font-display text-3xl sm:col-span-2">
            Register a visitor
          </h2>
          <label className="field-label">
            First name
            <input
              className="field"
              required
              value={form.firstName}
              onChange={(e) => setForm({ ...form, firstName: e.target.value })}
            />
          </label>
          <label className="field-label">
            Last name
            <input
              className="field"
              required
              value={form.lastName}
              onChange={(e) => setForm({ ...form, lastName: e.target.value })}
            />
          </label>
          <label className="field-label">
            Email
            <input
              className="field"
              type="email"
              value={form.email}
              onChange={(e) => setForm({ ...form, email: e.target.value })}
            />
          </label>
          <label className="field-label">
            Phone
            <input
              className="field"
              value={form.phone}
              onChange={(e) => setForm({ ...form, phone: e.target.value })}
            />
          </label>
          <p className="text-xs leading-5 text-muted sm:col-span-2">
            Email or phone is required. Existing matches are returned instead of
            creating a duplicate.
          </p>
          <button
            className="primary-button sm:col-span-2"
            disabled={busy || (!form.email && !form.phone)}
          >
            Check and register
          </button>
        </form>
      )}
      <form onSubmit={runSearch} className="mt-6 flex gap-3">
        <label className="relative flex-1">
          <span className="sr-only">Search People</span>
          <Search
            className="absolute left-4 top-1/2 -translate-y-1/2 text-muted"
            size={18}
          />
          <input
            className="field mt-0 pl-11"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search name, email, or phone"
            required
            minLength={2}
          />
        </label>
        <button className="secondary-button" disabled={busy}>
          {busy ? "Searching…" : "Search"}
        </button>
      </form>
      {message && (
        <p
          role="status"
          className="mt-4 rounded-xl bg-paper p-4 text-sm text-muted"
        >
          {message}
        </p>
      )}
      <div className="mt-6 divide-y divide-line rounded-3xl border border-line bg-paper">
        {results.map((person) => (
          <div key={person.id} className="flex items-center gap-4 p-5">
            <div className="grid h-11 w-11 place-items-center rounded-full bg-parchment font-display text-lg">
              {person.fullName.charAt(0)}
            </div>
            <div className="min-w-0 flex-1">
              <p className="font-medium">{person.fullName}</p>
              <p className="truncate text-xs text-muted">
                {person.email || person.phone || person.membershipType}
              </p>
            </div>
            {person.alreadyInGroup ? (
              <span className="text-xs text-muted">Already in Circle</span>
            ) : (
              <button
                className="secondary-button"
                onClick={() => void add(person)}
              >
                Add
              </button>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
