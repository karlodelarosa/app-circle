import {
  ArrowLeft,
  Check,
  Mail,
  MessageCircle,
  Phone,
  Search,
  UserCheck,
  UserPlus,
  UsersRound,
} from "lucide-react";
import { useEffect, useState, type FormEvent } from "react";
import { Link, Navigate, useNavigate, useParams } from "react-router-dom";
import { useCircles } from "../AppContext";
import { Modal } from "../components/Modal";
import { getErrorMessage } from "../lib/errors";
import { formatDate } from "../lib/format";
import { supabase } from "../lib/supabase";
import {
  loadGuestConnection,
  loadGuestConnections,
  resolveGuestConnection,
  searchPeople,
  updateGuestConnection,
} from "../services/circles";
import type {
  ConnectionStatus,
  GuestConnection,
  PersonSearchResult,
} from "../types";

type QueueFilter = "attention" | "active" | "connected" | "closed";

const statusCopy: Record<ConnectionStatus, string> = {
  new: "New",
  contacted: "Contacted",
  visited: "Visited",
  connected: "Connected",
  closed: "Closed",
};

const demoConnections: GuestConnection[] = [
  {
    id: "demo-connection",
    organizationId: "demo-org",
    groupId: "demo-group",
    groupName: "Grace & Ground",
    name: "Elena Ramos",
    email: "elena@example.com",
    phone: "+63 917 555 0142",
    preferredContact: "email",
    followUpOptIn: true,
    consentedAt: new Date().toISOString(),
    status: "new",
    lastActivityAt: new Date().toISOString(),
    rsvpCount: 1,
    interestCount: 1,
    attended: false,
    rsvps: [
      {
        id: "demo-rsvp",
        gatheringId: "meeting-1",
        title: "Rooted in grace",
        startsAt: new Date().toISOString(),
        status: "attending",
      },
    ],
    interests: [
      {
        id: "demo-interest",
        message: "I would love to learn more before the next gathering.",
        status: "new",
        createdAt: new Date().toISOString(),
      },
    ],
    activities: [],
  },
];

function ConnectionStatusLabel({ status }: { status: ConnectionStatus }) {
  return (
    <span
      className={`rounded-full px-3 py-1 text-xs ${
        status === "connected"
          ? "bg-[#E4E5D8] text-olive"
          : status === "closed"
            ? "bg-parchment text-muted"
            : "bg-[#EEE8DA] text-ink"
      }`}
    >
      {statusCopy[status]}
    </span>
  );
}

export function ConnectionsPage() {
  const { data, demoMode, refresh } = useCircles();
  const { connectionId } = useParams();
  const [filter, setFilter] = useState<QueueFilter>("attention");
  const [groupId, setGroupId] = useState("");
  const [connections, setConnections] = useState<GuestConnection[]>([]);
  const [selected, setSelected] = useState<GuestConnection>();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const canLead = Boolean(
    data &&
      (data.currentUser.role === "admin" ||
        data.groups.some((group) => group.role === "leader")),
  );

  const loadQueue = async () => {
    if (!data || !canLead) return;
    setLoading(true);
    setError("");
    try {
      if (!supabase) {
        const visible = demoConnections.filter(
          (item) =>
            (!groupId || item.groupId === groupId) &&
            (filter === "attention"
              ? item.followUpOptIn && item.status === "new"
              : filter === "active"
                ? ["new", "contacted", "visited"].includes(item.status)
                : item.status === filter),
        );
        setConnections(visible);
      } else {
        setConnections(
          await loadGuestConnections(supabase, groupId || undefined, filter),
        );
      }
    } catch (cause) {
      setError(getErrorMessage(cause, "Guest connections could not be loaded."));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void loadQueue();
  }, [filter, groupId, canLead]);

  useEffect(() => {
    if (!connectionId || !canLead) {
      setSelected(undefined);
      return;
    }
    setLoading(true);
    setError("");
    const detail = !supabase
      ? Promise.resolve(demoConnections.find((item) => item.id === connectionId))
      : loadGuestConnection(supabase, connectionId);
    void detail
      .then((value) => setSelected(value))
      .catch((cause) =>
        setError(getErrorMessage(cause, "This connection could not be loaded.")),
      )
      .finally(() => setLoading(false));
  }, [connectionId, canLead]);

  if (!data) return null;
  if (!canLead) return <Navigate to="/" replace />;
  if (connectionId)
    return (
      <ConnectionDetail
        connection={selected}
        loading={loading}
        error={error}
        demoMode={demoMode}
        currentPersonId={data.currentUser.personId}
        organizationId={data.organization.id}
        onChanged={async (next) => {
          setSelected(next);
          await refresh();
        }}
      />
    );

  const filters: { id: QueueFilter; label: string }[] = [
    { id: "attention", label: "Needs attention" },
    { id: "active", label: "Active" },
    { id: "connected", label: "Connected" },
    { id: "closed", label: "Closed" },
  ];
  return (
    <div>
      <div className="page-heading">
        <div>
          <p className="page-kicker">Care that continues</p>
          <h1>Guest connections</h1>
          <p>
            Keep one shared next step for each person who has asked to connect.
          </p>
        </div>
      </div>
      <div className="mt-8 flex flex-col gap-4 border-b border-line pb-5 sm:flex-row sm:items-end sm:justify-between">
        <div className="flex gap-1 overflow-x-auto pb-1" aria-label="Connection filters">
          {filters.map((item) => (
            <button
              key={item.id}
              onClick={() => setFilter(item.id)}
              aria-pressed={filter === item.id}
              className={`min-h-11 shrink-0 rounded-full px-4 text-sm ${filter === item.id ? "bg-olive text-paper" : "text-muted hover:bg-paper"}`}
            >
              {item.label}
            </button>
          ))}
        </div>
        {data.groups.length > 1 && (
          <label className="text-xs text-muted">
            Circle
            <select
              className="field mt-1 min-w-52"
              value={groupId}
              onChange={(event) => setGroupId(event.target.value)}
            >
              <option value="">All Circles</option>
              {data.groups
                .filter((group) => data.currentUser.role === "admin" || group.role === "leader")
                .map((group) => (
                  <option key={group.id} value={group.id}>
                    {group.name}
                  </option>
                ))}
            </select>
          </label>
        )}
      </div>
      {error && <p className="form-error mt-6" role="alert">{error}</p>}
      {loading ? (
        <p className="mt-8 text-sm text-muted">Loading connections…</p>
      ) : connections.length ? (
        <div className="mt-4 divide-y divide-line">
          {connections.map((connection) => (
            <Link
              key={connection.id}
              to={`/connections/${connection.id}`}
              className="grid gap-4 py-6 sm:grid-cols-[1fr_auto] sm:items-center"
            >
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-3">
                  <h2 className="font-display text-3xl">{connection.name}</h2>
                  <ConnectionStatusLabel status={connection.status} />
                </div>
                <p className="mt-2 text-sm text-muted">
                  {connection.groupName} · {connection.preferredContact === "either" ? "Email or phone" : connection.preferredContact}
                </p>
                <p className="mt-2 text-xs text-muted">
                  {connection.interestCount > 0 ? "Asked to connect" : "Gathering guest"}
                  {connection.attended ? " · Attended" : ""}
                  {connection.claimedByName ? ` · With ${connection.claimedByName}` : ""}
                </p>
              </div>
              <span className="text-link min-h-11 self-start sm:self-auto">Open connection</span>
            </Link>
          ))}
        </div>
      ) : (
        <div className="empty-state mt-6 border-y border-line">
          <UsersRound />
          <h2>No connections here</h2>
          <p>New guest requests and staged walk-ins will appear here.</p>
        </div>
      )}
    </div>
  );
}

function ConnectionDetail({
  connection,
  loading,
  error,
  demoMode,
  currentPersonId,
  organizationId,
  onChanged,
}: {
  connection?: GuestConnection;
  loading: boolean;
  error: string;
  demoMode: boolean;
  currentPersonId?: string;
  organizationId: string;
  onChanged: (connection: GuestConnection) => Promise<void>;
}) {
  const navigate = useNavigate();
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState("");
  const [note, setNote] = useState("");
  const [convertOpen, setConvertOpen] = useState(false);
  const change = async (
    action: "claim" | "unclaim" | "contacted" | "close" | "reopen" | "note",
    body = "",
  ) => {
    if (!connection) return;
    setBusy(true);
    setActionError("");
    try {
      let next: GuestConnection;
      if (!supabase) {
        const status =
          action === "contacted"
            ? "contacted"
            : action === "close"
              ? "closed"
              : action === "reopen"
                ? connection.attended
                  ? "visited"
                  : "new"
                : connection.status;
        next = {
          ...connection,
          status,
          claimedByPersonId:
            action === "claim"
              ? currentPersonId
              : action === "unclaim"
                ? undefined
                : connection.claimedByPersonId,
          claimedByName:
            action === "claim"
              ? "Karlo de la Rosa"
              : action === "unclaim"
                ? undefined
                : connection.claimedByName,
          activities: [
            {
              id: crypto.randomUUID(),
              type: action === "note" ? "note" : action === "contacted" ? "contacted" : action === "claim" ? "claimed" : action === "unclaim" ? "unclaimed" : "status_changed",
              body,
              createdAt: new Date().toISOString(),
            },
            ...(connection.activities ?? []),
          ],
        };
      } else next = await updateGuestConnection(supabase, connection.id, action, body);
      setNote("");
      await onChanged(next);
    } catch (cause) {
      setActionError(getErrorMessage(cause, "The connection could not be updated."));
    } finally {
      setBusy(false);
    }
  };
  if (loading) return <p className="text-sm text-muted">Loading connection…</p>;
  if (error || !connection)
    return (
      <div className="empty-state">
        <UsersRound />
        <h2>Connection unavailable</h2>
        <p>{error || "This guest connection could not be found."}</p>
        <button className="secondary-button" onClick={() => navigate("/connections")}>Back to connections</button>
      </div>
    );
  return (
    <div className="mx-auto max-w-5xl">
      <Link to="/connections" className="mb-7 inline-flex min-h-11 items-center gap-2 text-sm text-muted hover:text-olive">
        <ArrowLeft size={16} /> Guest connections
      </Link>
      <header className="border-b border-line pb-8">
        <div className="flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <p className="page-kicker">{connection.groupName}</p>
            <h1 className="mt-2 break-words font-display text-5xl sm:text-6xl">{connection.name}</h1>
            <div className="mt-4 flex flex-wrap items-center gap-3">
              <ConnectionStatusLabel status={connection.status} />
              <span className="text-sm text-muted">
                {connection.followUpOptIn ? "Asked to be contacted" : "Event contact only"}
              </span>
            </div>
          </div>
          <div className="flex flex-wrap gap-2">
            {connection.email && <a className="secondary-button min-h-11" href={`mailto:${connection.email}`}><Mail size={16} /> Email</a>}
            {connection.phone && <a className="secondary-button min-h-11" href={`tel:${connection.phone}`}><Phone size={16} /> Call</a>}
          </div>
        </div>
      </header>
      <div className="grid gap-10 py-8 lg:grid-cols-[1fr_.72fr]">
        <section>
          <div className="flex flex-wrap gap-2">
            {connection.claimedByPersonId ? (
              <button className="secondary-button min-h-11" disabled={busy} onClick={() => void change("unclaim")}>
                With {connection.claimedByName || "a leader"} · Unclaim
              </button>
            ) : currentPersonId ? (
              <button className="secondary-button min-h-11" disabled={busy} onClick={() => void change("claim")}><UserCheck size={16} /> Claim follow-up</button>
            ) : null}
            {connection.status === "new" && connection.followUpOptIn && (
              <button className="primary-button min-h-11" disabled={busy} onClick={() => void change("contacted")}><Check size={16} /> Mark contacted</button>
            )}
            {connection.status === "closed" ? (
              <button className="secondary-button min-h-11" disabled={busy} onClick={() => void change("reopen")}>Reopen</button>
            ) : connection.status !== "connected" ? (
              <button className="secondary-button min-h-11" disabled={busy} onClick={() => void change("close")}>Close</button>
            ) : null}
            {connection.status !== "connected" && (
              <button className="primary-button min-h-11" onClick={() => setConvertOpen(true)}><UserPlus size={16} /> Connect to SheepCount</button>
            )}
          </div>
          {actionError && <p className="form-error mt-5" role="alert">{actionError}</p>}
          <form
            className="mt-8 border-y border-line py-6"
            onSubmit={(event) => {
              event.preventDefault();
              void change("note", note);
            }}
          >
            <label className="field-label">
              Private follow-up note
              <textarea className="field min-h-24" maxLength={2000} required value={note} onChange={(event) => setNote(event.target.value)} />
            </label>
            <button className="secondary-button mt-3 min-h-11" disabled={busy || !note.trim()}><MessageCircle size={16} /> Add note</button>
          </form>
          <h2 className="mt-8 font-display text-3xl">Activity</h2>
          <div className="mt-4 border-l border-line pl-5">
            {(connection.activities ?? []).map((activity) => (
              <article key={activity.id} className="relative pb-6">
                <span className="absolute -left-[1.45rem] top-1 h-2 w-2 rounded-full bg-olive" />
                <p className="text-sm font-medium capitalize">{activity.type.replace("_", " ")}</p>
                {activity.body && <p className="mt-1 text-sm leading-6 text-muted">{activity.body}</p>}
                <p className="mt-1 text-xs text-muted">{formatDate(activity.createdAt)}</p>
              </article>
            ))}
            {!(connection.activities ?? []).length && <p className="pb-6 text-sm text-muted">No follow-up notes yet.</p>}
          </div>
        </section>
        <aside className="space-y-7">
          <section className="paper-panel p-6">
            <h2 className="font-display text-2xl">Contact</h2>
            <dl className="mt-5 space-y-4 text-sm">
              <div><dt className="text-xs text-muted">Preferred</dt><dd className="mt-1 capitalize">{connection.preferredContact}</dd></div>
              {connection.email && <div><dt className="text-xs text-muted">Email</dt><dd className="mt-1 break-all">{connection.email}</dd></div>}
              {connection.phone && <div><dt className="text-xs text-muted">Phone</dt><dd className="mt-1">{connection.phone}</dd></div>}
            </dl>
          </section>
          {!!connection.rsvps?.length && (
            <section>
              <h2 className="font-display text-2xl">Gatherings</h2>
              <div className="mt-3 divide-y divide-line border-y border-line">
                {connection.rsvps.map((rsvp) => (
                  <div key={rsvp.id} className="py-4">
                    <p className="font-medium">{rsvp.title}</p>
                    <p className="mt-1 text-xs text-muted">{formatDate(rsvp.startsAt)} · {rsvp.attendedAt ? "Attended" : rsvp.status}</p>
                  </div>
                ))}
              </div>
            </section>
          )}
          {connection.interests?.map((interest) => interest.message && (
            <blockquote key={interest.id} className="border-l-2 border-sage pl-5 text-sm leading-7 text-muted">“{interest.message}”</blockquote>
          ))}
        </aside>
      </div>
      {convertOpen && (
        <ConvertConnectionModal
          connection={connection}
          organizationId={organizationId}
          demoMode={demoMode}
          onClose={() => setConvertOpen(false)}
          onConverted={async () => {
            const next = !supabase
              ? { ...connection, status: "connected" as const, convertedPersonId: "demo-person" }
              : await loadGuestConnection(supabase, connection.id);
            setConvertOpen(false);
            await onChanged(next);
          }}
        />
      )}
    </div>
  );
}

function ConvertConnectionModal({ connection, organizationId, demoMode, onClose, onConverted }: {
  connection: GuestConnection;
  organizationId: string;
  demoMode: boolean;
  onClose: () => void;
  onConverted: () => Promise<void>;
}) {
  const nameParts = connection.name.trim().split(/\s+/);
  const [query, setQuery] = useState(connection.email || connection.phone || connection.name);
  const [results, setResults] = useState<PersonSearchResult[]>([]);
  const [form, setForm] = useState({ firstName: nameParts[0] || "", lastName: nameParts.slice(1).join(" "), email: connection.email, phone: connection.phone });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const findMatches = async (event?: FormEvent) => {
    event?.preventDefault();
    setBusy(true); setError("");
    try {
      setResults(!supabase ? [] : await searchPeople(supabase, organizationId, connection.groupId, query));
    } catch (cause) { setError(getErrorMessage(cause, "People search failed.")); }
    finally { setBusy(false); }
  };
  const resolve = async (personId?: string) => {
    setBusy(true); setError("");
    try {
      if (!demoMode && supabase) await resolveGuestConnection(supabase, connection.id, personId ? { personId } : form);
      await onConverted();
    } catch (cause) { setError(getErrorMessage(cause, "This guest could not be connected.")); }
    finally { setBusy(false); }
  };
  return (
    <Modal title="Connect to SheepCount" onClose={onClose}>
      <p className="text-sm leading-6 text-muted">Search first. Choose an existing person when possible; create a visitor only when there is no match.</p>
      <form className="mt-5 flex gap-2" onSubmit={(event) => void findMatches(event)}>
        <input className="field mt-0" aria-label="Search SheepCount People" value={query} onChange={(event) => setQuery(event.target.value)} />
        <button className="secondary-button min-h-12" disabled={busy || query.trim().length < 2}><Search size={16} /><span className="sr-only">Search</span></button>
      </form>
      {!!results.length && <div className="mt-4 space-y-2">{results.map((person) => (
        <button key={person.id} type="button" className="flex min-h-14 w-full items-center justify-between rounded-xl border border-line p-3 text-left" disabled={busy} onClick={() => void resolve(person.id)}>
          <span><strong className="block text-sm">{person.fullName}</strong><span className="text-xs text-muted">{person.email || person.phone}</span></span>
          <span className="text-xs text-olive">{person.alreadyInGroup ? "Already in Circle" : "Use person"}</span>
        </button>
      ))}</div>}
      <div className="my-6 flex items-center gap-3 text-xs text-muted"><span className="h-px flex-1 bg-line" />No match found<span className="h-px flex-1 bg-line" /></div>
      <div className="grid gap-4 sm:grid-cols-2">
        <label className="field-label">First name<input className="field" required value={form.firstName} onChange={(event) => setForm({ ...form, firstName: event.target.value })} /></label>
        <label className="field-label">Last name<input className="field" required value={form.lastName} onChange={(event) => setForm({ ...form, lastName: event.target.value })} /></label>
        <label className="field-label">Email<input className="field" type="email" value={form.email} onChange={(event) => setForm({ ...form, email: event.target.value })} /></label>
        <label className="field-label">Phone<input className="field" value={form.phone} onChange={(event) => setForm({ ...form, phone: event.target.value })} /></label>
      </div>
      {error && <p className="form-error mt-4" role="alert">{error}</p>}
      <button className="primary-button mt-5 min-h-11 w-full" disabled={busy || !form.firstName || !form.lastName || (!form.email && !form.phone)} onClick={() => void resolve()}>
        <UserPlus size={16} /> {busy ? "Checking…" : "Register visitor and add to Circle"}
      </button>
    </Modal>
  );
}
