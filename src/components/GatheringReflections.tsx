import { Check, MessageCircle, Pencil, Send, Trash2 } from "lucide-react";
import { useEffect, useState, type FormEvent } from "react";
import { Link } from "react-router-dom";
import { useCircles } from "../AppContext";
import { getErrorMessage } from "../lib/errors";
import { relativeDate } from "../lib/format";
import { supabase } from "../lib/supabase";
import {
  createGatheringReflection,
  deleteGatheringReflection,
  loadGatheringReflections,
  updateGatheringReflection,
} from "../services/circles";
import type { GatheringReflection, Meeting } from "../types";
import { Avatar } from "./Avatar";

const MAX_LENGTH = 2000;

function ReflectionCard({
  reflection,
  member,
  isAuthor,
  canModerate,
  busy,
  onSave,
  onRemove,
}: {
  reflection: GatheringReflection;
  member: { id: string; fullName: string; avatarUrl?: string; role: string };
  isAuthor: boolean;
  canModerate: boolean;
  busy: boolean;
  onSave: (body: string) => Promise<boolean>;
  onRemove: () => Promise<void>;
}) {
  const [editing, setEditing] = useState(false);
  const [body, setBody] = useState(reflection.body);

  return (
    <article className="py-5">
      <div className="flex items-start gap-3">
        <Avatar person={member} size="sm" />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
            <h3 className="font-medium">{reflection.authorName}</h3>
            <span className="text-xs text-muted">
              {relativeDate(reflection.createdAt)}
              {reflection.updatedAt !== reflection.createdAt ? " · Edited" : ""}
            </span>
          </div>
          {editing ? (
            <div className="mt-3">
              <label className="sr-only" htmlFor={`edit-reflection-${reflection.id}`}>
                Edit your reflection
              </label>
              <textarea
                id={`edit-reflection-${reflection.id}`}
                className="field min-h-28 resize-y"
                maxLength={MAX_LENGTH}
                value={body}
                onChange={(event) => setBody(event.target.value)}
              />
              <div className="mt-3 flex flex-wrap justify-end gap-2">
                <button type="button" className="secondary-button" onClick={() => {
                  setBody(reflection.body);
                  setEditing(false);
                }}>
                  Cancel
                </button>
                <button type="button" className="primary-button" disabled={busy || !body.trim()} onClick={() => void onSave(body).then((saved) => saved && setEditing(false))}>
                  <Check size={16} /> Save
                </button>
              </div>
            </div>
          ) : (
            <p className="mt-2 whitespace-pre-line break-words leading-7 text-muted">
              {reflection.body}
            </p>
          )}
          {!editing && (isAuthor || canModerate) && (
            <div className="mt-3 flex gap-4">
              {isAuthor && (
                <button
                  type="button"
                  className="inline-flex items-center gap-1.5 text-xs font-medium text-olive hover:underline"
                  aria-label={`Edit ${reflection.authorName}'s reflection`}
                  onClick={() => setEditing(true)}
                >
                  <Pencil size={13} /> Edit
                </button>
              )}
              <button
                type="button"
                className="inline-flex items-center gap-1.5 text-xs font-medium text-muted hover:text-ink hover:underline"
                aria-label={`Remove ${reflection.authorName}'s reflection`}
                disabled={busy}
                onClick={() => void onRemove()}
              >
                <Trash2 size={13} /> Remove
              </button>
            </div>
          )}
        </div>
      </div>
    </article>
  );
}

export function GatheringReflections({
  meeting,
  canModerate,
  initialReflections = [],
}: {
  meeting: Meeting;
  canModerate: boolean;
  initialReflections?: GatheringReflection[];
}) {
  const { data, demoMode } = useCircles();
  const [reflections, setReflections] = useState(initialReflections);
  const [body, setBody] = useState("");
  const [loading, setLoading] = useState(!demoMode && Boolean(supabase));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  const personId = data?.currentUser.personId;
  const canParticipate = Boolean(personId);

  const reload = async () => {
    if (!supabase) return;
    setReflections(await loadGatheringReflections(supabase, meeting.id));
  };

  useEffect(() => {
    if (demoMode || !supabase) {
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    loadGatheringReflections(supabase, meeting.id)
      .then((items) => {
        if (active) setReflections(items);
      })
      .catch((cause) => {
        if (active) setError(getErrorMessage(cause, "Reflections could not be loaded."));
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [meeting.id, demoMode]);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    const value = body.trim();
    if (!data || !personId || !value) return;
    setBusy(true);
    setError("");
    setNotice("");
    try {
      if (demoMode || !supabase) {
        const now = new Date().toISOString();
        setReflections((items) => [...items, {
          id: crypto.randomUUID(),
          gatheringId: meeting.id,
          organizationId: data.organization.id,
          authorPersonId: personId,
          authorName: data.currentUser.fullName,
          body: value,
          createdAt: now,
          updatedAt: now,
        }]);
      } else {
        await createGatheringReflection(
          supabase,
          data.organization.id,
          meeting.id,
          personId,
          value,
        );
        await reload();
      }
      setBody("");
      setNotice("Your reflection was shared with this gathering’s community.");
    } catch (cause) {
      setError(getErrorMessage(cause, "Your reflection could not be shared."));
    } finally {
      setBusy(false);
    }
  };

  const saveEdit = async (reflection: GatheringReflection, nextBody: string) => {
    const value = nextBody.trim();
    if (!value) return false;
    setBusy(true);
    setError("");
    try {
      if (demoMode || !supabase) {
        setReflections((items) => items.map((item) => item.id === reflection.id
          ? { ...item, body: value, updatedAt: new Date().toISOString() }
          : item));
      } else {
        await updateGatheringReflection(supabase, reflection.id, value);
        await reload();
      }
      return true;
    } catch (cause) {
      setError(getErrorMessage(cause, "The reflection could not be updated."));
      return false;
    } finally {
      setBusy(false);
    }
  };

  const remove = async (reflection: GatheringReflection) => {
    if (!window.confirm(`Remove ${reflection.authorName}’s reflection?`)) return;
    setBusy(true);
    setError("");
    try {
      if (demoMode || !supabase)
        setReflections((items) => items.filter((item) => item.id !== reflection.id));
      else {
        await deleteGatheringReflection(supabase, reflection.id);
        await reload();
      }
    } catch (cause) {
      setError(getErrorMessage(cause, "The reflection could not be removed."));
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="mt-7 border-y border-line py-8" aria-labelledby="after-gathering-heading">
      <div className="grid gap-8 lg:grid-cols-[minmax(0,.75fr)_minmax(0,1.25fr)]">
        <div>
          <p className="page-kicker">Continue together</p>
          <h2 id="after-gathering-heading" className="mt-2 font-display text-4xl">
            After the gathering
          </h2>
          <p className="mt-3 max-w-md leading-7 text-muted">
            A private place for members to remember what mattered and carry it into the week.
          </p>
          {canParticipate ? (
            <form className="mt-6" onSubmit={submit}>
              <label className="field-label" htmlFor="gathering-reflection">
                What stayed with you?
              </label>
              <textarea
                id="gathering-reflection"
                className="field mt-2 min-h-32 resize-y"
                maxLength={MAX_LENGTH}
                value={body}
                onChange={(event) => setBody(event.target.value)}
                placeholder="A thought, question, or practice you want to remember…"
              />
              <div className="mt-2 flex items-center justify-between gap-4">
                <span className="text-xs text-muted">{body.length.toLocaleString()} / 2,000</span>
                <button className="primary-button" disabled={busy || !body.trim()}>
                  <Send size={16} /> {busy ? "Sharing…" : "Share reflection"}
                </button>
              </div>
            </form>
          ) : (
            <p className="mt-6 rounded-xl bg-paper p-4 text-sm leading-6 text-muted">
              Link this account to a People record before sharing a reflection.
            </p>
          )}
        </div>

        <div aria-live="polite">
          {loading ? (
            <div className="space-y-3" aria-busy="true" aria-label="Loading reflections">
              <div className="h-24 animate-pulse rounded-2xl bg-paper" />
              <div className="h-24 animate-pulse rounded-2xl bg-paper" />
            </div>
          ) : reflections.length ? (
            <div className="divide-y divide-line border-y border-line">
              {reflections.map((reflection) => {
                const isAuthor = reflection.authorPersonId === personId;
                const member = data?.members.find((item) => item.id === reflection.authorPersonId)
                  ?? { id: reflection.authorPersonId, fullName: reflection.authorName, role: "member" };
                return (
                  <ReflectionCard
                    key={reflection.id}
                    reflection={reflection}
                    member={member}
                    isAuthor={isAuthor}
                    canModerate={canModerate}
                    busy={busy}
                    onSave={(nextBody) => saveEdit(reflection, nextBody)}
                    onRemove={() => remove(reflection)}
                  />
                );
              })}
            </div>
          ) : (
            <div className="grid min-h-56 place-items-center border-y border-line px-6 text-center">
              <div>
                <MessageCircle className="mx-auto text-olive" />
                <h3 className="mt-4 font-display text-2xl">Begin the reflection</h3>
                <p className="mt-2 text-sm leading-6 text-muted">
                  Share the first thought your Circle can carry into the week.
                </p>
              </div>
            </div>
          )}
          {notice && <p className="mt-4 text-sm text-olive" role="status">{notice}</p>}
          {error && <p className="form-error mt-4" role="alert">{error}</p>}
          {reflections.length > 0 && (
            <p className="mt-5 text-sm leading-6 text-muted">
              Want to carry this further? <Link className="text-link" to="/prayer">Turn this into a prayer request</Link>
              {" or "}<Link className="text-link" to="/share-testimony">submit it as a testimony</Link>.
            </p>
          )}
        </div>
      </div>
    </section>
  );
}
