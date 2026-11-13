import { Bell, BellOff, ChevronDown, Plus } from "lucide-react";
import { useEffect, useState } from "react";
import { useLocation } from "react-router-dom";
import { useCircles } from "../AppContext";
import { getErrorMessage } from "../lib/errors";
import { relativeDate } from "../lib/format";
import { supabase } from "../lib/supabase";
import { addPrayerUpdate, loadPrayerUpdates, setPrayerFollow } from "../services/feed";
import type { CommunityFeedItem, PrayerUpdate, PrayerUpdateType } from "../types";

const updateLabels: Record<PrayerUpdateType, string> = {
  progress: "Update",
  praise: "Praise report",
  answered: "Answered",
  reopened: "Prayer reopened",
};

export function PrayerJourney({ item, onUpdate }: { item: CommunityFeedItem; onUpdate: (item: CommunityFeedItem) => void }) {
  const { data, demoMode } = useCircles();
  const { hash } = useLocation();
  const targetedUpdateId = hash.startsWith("#prayer-update-") ? hash.slice("#prayer-update-".length) : undefined;
  const [updates, setUpdates] = useState<PrayerUpdate[]>(item.latestPrayerUpdate ? [item.latestPrayerUpdate] : []);
  const [expanded, setExpanded] = useState(Boolean(targetedUpdateId));
  const [editing, setEditing] = useState(false);
  const [body, setBody] = useState("");
  const [type, setType] = useState<PrayerUpdateType>("progress");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const prayer = item.prayer;

  useEffect(() => {
    if (!targetedUpdateId || !prayer || !supabase || demoMode || updates.some((update) => update.id === targetedUpdateId)) return;
    let active = true;
    loadPrayerUpdates(supabase, prayer.id).then((loaded) => {
      if (!active) return;
      setUpdates(loaded);
      window.requestAnimationFrame(() => document.getElementById(`prayer-update-${targetedUpdateId}`)?.scrollIntoView({ block: "center" }));
    }).catch((cause) => active && setError(getErrorMessage(cause, "The linked prayer update could not be loaded.")));
    return () => { active = false; };
  }, [demoMode, prayer, targetedUpdateId, updates]);
  useEffect(() => {
    if (!targetedUpdateId || !updates.some((update) => update.id === targetedUpdateId)) return;
    window.requestAnimationFrame(() => document.getElementById(`prayer-update-${targetedUpdateId}`)?.scrollIntoView({ block: "center" }));
  }, [targetedUpdateId, updates]);
  if (!prayer) return null;

  const follow = async () => {
    const followed = !item.followedByMe;
    onUpdate({ ...item, followedByMe: followed });
    if (supabase && !demoMode) {
      try { await setPrayerFollow(supabase, prayer.id, followed); }
      catch (cause) { onUpdate(item); setError(getErrorMessage(cause, "Your follow preference could not be saved.")); }
    }
  };

  const expand = async () => {
    const next = !expanded;
    setExpanded(next);
    if (next && supabase && !demoMode) {
      try { setUpdates(await loadPrayerUpdates(supabase, prayer.id)); }
      catch (cause) { setError(getErrorMessage(cause, "Prayer updates could not be loaded.")); }
    }
  };

  const share = async () => {
    if (!body.trim()) return;
    setBusy(true); setError("");
    try {
      const now = new Date().toISOString();
      const id = supabase && !demoMode ? await addPrayerUpdate(supabase, item.prayer!.id, type, body) : crypto.randomUUID();
      const update: PrayerUpdate = {
        id, prayerId: item.prayer!.id, authorPersonId: item.authorPersonId ?? "", authorName: item.authorName,
        type, body: body.trim(), createdAt: now, canEdit: true, canModerate: item.canModerate,
      };
      setUpdates((current) => [...current, update]);
      setExpanded(true); setEditing(false); setBody("");
      onUpdate({
        ...item, activityAt: now, latestPrayerUpdate: update,
        prayer: { ...item.prayer!, isAnswered: ["answered", "praise"].includes(type) ? true : type === "reopened" ? false : item.prayer!.isAnswered, answeredNotes: ["answered", "praise"].includes(type) ? update.body : type === "reopened" ? undefined : item.prayer!.answeredNotes },
      });
    } catch (cause) { setError(getErrorMessage(cause, "The prayer update could not be shared.")); }
    finally { setBusy(false); }
  };

  return (
    <div className="mt-4 border-y border-line py-3">
      <div className="flex flex-wrap items-center gap-2">
        <button type="button" disabled={!data?.currentUser.personId} className={`secondary-button border-0 ${item.followedByMe ? "text-olive" : ""}`} onClick={() => void follow()}>
          {item.followedByMe ? <BellOff size={15} /> : <Bell size={15} />}{item.followedByMe ? "Following" : "Follow updates"}
        </button>
        {item.canEdit && <button type="button" className="secondary-button border-0" onClick={() => setEditing((current) => !current)}><Plus size={15} /> Add prayer update</button>}
      </div>
      {item.latestPrayerUpdate && !expanded && (
        <button type="button" className="mt-3 w-full border-l-2 border-olive pl-4 text-left" onClick={() => void expand()}>
          <span className="text-xs font-medium text-olive">{updateLabels[item.latestPrayerUpdate.type]} · {relativeDate(item.latestPrayerUpdate.createdAt)}</span>
          <span className="mt-1 block text-sm leading-6">{item.latestPrayerUpdate.body}</span>
          <span className="mt-2 inline-flex items-center gap-1 text-xs text-muted">View prayer journey <ChevronDown size={13} /></span>
        </button>
      )}
      {expanded && updates.length > 0 && (
        <ol className="mt-4 space-y-4 border-l border-line pl-4" aria-label="Prayer journey">
          {updates.map((update) => <li key={update.id} id={`prayer-update-${update.id}`} className="scroll-mt-28">
            <p className="text-xs font-medium text-olive">{updateLabels[update.type]} · {relativeDate(update.createdAt)}</p>
            <p className="mt-1 whitespace-pre-line text-sm leading-6">{update.body}</p>
          </li>)}
        </ol>
      )}
      {editing && (
        <div className="mt-4 space-y-3 rounded-xl bg-parchment p-4">
          <label className="field-label text-xs">Update type<select className="field" value={type} onChange={(event) => setType(event.target.value as PrayerUpdateType)}>
            <option value="progress">Progress update</option><option value="praise">Praise report</option><option value="answered">Mark answered</option><option value="reopened">Reopen prayer</option>
          </select></label>
          <label className="field-label text-xs">Prayer update<textarea className="field min-h-24 resize-y" maxLength={2000} value={body} onChange={(event) => setBody(event.target.value)} /></label>
          <div className="flex justify-end gap-2"><button type="button" className="secondary-button" onClick={() => setEditing(false)}>Cancel</button><button type="button" className="primary-button" disabled={busy || !body.trim()} onClick={() => void share()}>Share update</button></div>
        </div>
      )}
      {error && <p className="form-error mt-3" role="alert">{error}</p>}
    </div>
  );
}
