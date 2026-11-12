import { CalendarDays, Check, Heart, LockKeyhole, Megaphone, MessageCircle, MoreHorizontal, Pencil, Quote, Trash2, Users, X } from "lucide-react";
import { useState } from "react";
import { Link } from "react-router-dom";
import { useCircles } from "../AppContext";
import { getErrorMessage } from "../lib/errors";
import { formatDate, formatTime, relativeDate } from "../lib/format";
import { supabase } from "../lib/supabase";
import { deleteFeedPost, removeFeedPhoto, setFeedItemHidden, setFeedLike, updateFeedPost } from "../services/feed";
import type { CommunityFeedItem, FeedComment } from "../types";
import { Avatar } from "./Avatar";
import { FeedComments } from "./FeedComments";

const labels = { post: "Update", reflection: "Gathering reflection", prayer: "Prayer request", gathering: "Gathering", announcement: "Announcement" } as const;

export function FeedCard({ item, onUpdate, onRemove }: { item: CommunityFeedItem; onUpdate: (item: CommunityFeedItem) => void; onRemove: () => void }) {
  const { data, demoMode, setRsvp, togglePrayer } = useCircles();
  const [busy, setBusy] = useState(false);
  const [menu, setMenu] = useState(false);
  const [error, setError] = useState("");
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(item.body ?? "");
  if (!data) return null;

  const like = async () => {
    if (!data.currentUser.personId) return;
    const liked = !item.likedByMe;
    onUpdate({ ...item, likedByMe: liked, likeCount: Math.max(0, item.likeCount + (liked ? 1 : -1)) });
    if (supabase && !demoMode) {
      try { await setFeedLike(supabase, item.id, data.currentUser.personId, liked); }
      catch (cause) { onUpdate(item); setError(getErrorMessage(cause, "The Like could not be saved.")); }
    }
  };
  const pray = async () => {
    if (!item.prayer) return;
    setBusy(true); setError("");
    try {
      await togglePrayer(item.prayer.id);
      const prayedByMe = !item.prayer.prayedByMe;
      onUpdate({ ...item, prayer: { ...item.prayer, prayedByMe, prayerCount: Math.max(0, item.prayer.prayerCount + (prayedByMe ? 1 : -1)) } });
    } catch (cause) { setError(getErrorMessage(cause, "Your prayer response could not be saved.")); }
    finally { setBusy(false); }
  };
  const hide = async () => {
    setBusy(true); setError("");
    try { if (supabase && !demoMode) await setFeedItemHidden(supabase, item.id, true); onRemove(); }
    catch (cause) { setError(getErrorMessage(cause, "This item could not be hidden.")); }
    finally { setBusy(false); }
  };
  const remove = async () => {
    if (!window.confirm("Delete this update and its comments?")) return;
    setBusy(true); setError("");
    try { if (supabase && !demoMode && item.sourceId) await deleteFeedPost(supabase, item.sourceId); onRemove(); }
    catch (cause) { setError(getErrorMessage(cause, "This update could not be deleted.")); }
    finally { setBusy(false); }
  };
  const save = async () => {
    const value = draft.trim();
    if (!value) return;
    setBusy(true); setError("");
    try {
      if (supabase && !demoMode && item.sourceId) await updateFeedPost(supabase, item.sourceId, value);
      onUpdate({ ...item, body: value, updatedAt: new Date().toISOString() });
      setEditing(false); setMenu(false);
    } catch (cause) { setError(getErrorMessage(cause, "This update could not be saved.")); }
    finally { setBusy(false); }
  };
  const removePhoto = async (photoId: string) => {
    if (!item.body?.trim() && item.photos.length === 1) {
      setError("Add text before removing the only photo, or delete the update.");
      return;
    }
    setBusy(true); setError("");
    try {
      if (supabase && !demoMode) await removeFeedPhoto(supabase, photoId);
      onUpdate({ ...item, photos: item.photos.filter((photo) => photo.id !== photoId) });
    } catch (cause) { setError(getErrorMessage(cause, "This photo could not be removed.")); }
    finally { setBusy(false); }
  };
  const rsvp = async (status: "attending" | "tentative" | "declined") => {
    if (!item.meeting || !data.currentUser.personId) return;
    setBusy(true); setError("");
    try {
      await setRsvp(item.meeting.id, status);
      onUpdate({ ...item, meeting: { ...item.meeting, rsvps: { ...item.meeting.rsvps, [data.currentUser.personId]: status } } });
    } catch (cause) { setError(getErrorMessage(cause, "Your RSVP could not be saved.")); }
    finally { setBusy(false); }
  };
  const updateComments = (comments: FeedComment[], commentCount = comments.length) => onUpdate({ ...item, comments, commentCount });
  const label = item.type === "reflection" && item.gatheringTitle ? `${labels[item.type]} from ${item.gatheringTitle}` : labels[item.type];

  return (
    <article className="paper-panel overflow-hidden" aria-label={`${label}: ${item.title || item.body || item.authorName}`}>
      <header className="flex items-start gap-3 p-4 sm:p-5">
        <Avatar person={{ id: item.authorPersonId || item.id, fullName: item.authorName, avatarUrl: item.authorAvatarUrl }} />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
            <strong className="text-sm font-medium">{item.authorName}</strong>
            <span className="role-label">{item.destinationName}</span>
          </div>
          <p className="mt-1 flex flex-wrap items-center gap-1.5 text-xs text-muted">
            <span>{label}</span><span aria-hidden="true">·</span><span>{relativeDate(item.createdAt)}</span>
            {item.audience === "circle" && <LockKeyhole size={12} aria-label="Circle only" />}
          </p>
        </div>
        {(item.canEdit || item.canModerate) && (
          <div className="relative">
            <button className="icon-button" aria-label="Post actions" aria-expanded={menu} onClick={() => setMenu((open) => !open)}><MoreHorizontal size={18} /></button>
            {menu && <div className="action-menu right-0" role="menu">
              {item.type === "post" && item.canEdit && <button role="menuitem" disabled={busy} onClick={() => { setEditing(true); setMenu(false); }}><Pencil size={14} /> Edit update</button>}
              {item.type === "post" && (item.canEdit || item.canModerate) && <button role="menuitem" disabled={busy} onClick={() => void remove()}><Trash2 size={14} /> Delete update</button>}
              {item.canModerate && <button role="menuitem" disabled={busy} onClick={() => void hide()}>Hide from feed</button>}
            </div>}
          </div>
        )}
      </header>

      <div className="px-4 pb-4 sm:px-5 sm:pb-5">
        {item.type === "reflection" && item.gatheringId && (
          <Link className="mb-4 flex items-center gap-2 border-y border-line py-3 text-sm text-olive" to={`/gatherings/${item.gatheringId}`}><Quote size={16} /> Open gathering</Link>
        )}
        {item.title && <h2 className="font-display text-2xl leading-tight sm:text-3xl">{item.title}</h2>}
        {editing ? (
          <div className="space-y-3">
            <label className="sr-only" htmlFor={`edit-feed-${item.id}`}>Edit update</label>
            <textarea id={`edit-feed-${item.id}`} className="field min-h-28 resize-y" maxLength={5000} value={draft} onChange={(event) => setDraft(event.target.value)} />
            <div className="flex justify-end gap-2">
              <button type="button" className="secondary-button" onClick={() => { setDraft(item.body ?? ""); setEditing(false); }}><X size={15} /> Cancel</button>
              <button type="button" className="primary-button" disabled={busy || !draft.trim()} onClick={() => void save()}><Check size={15} /> Save</button>
            </div>
          </div>
        ) : item.body ? <p className={`${item.title ? "mt-3" : ""} whitespace-pre-line break-words leading-7 text-[#45483F]`}>{item.body}</p> : null}
        {item.photos.length > 0 && (
          <div className={`mt-4 grid gap-1 overflow-hidden rounded-xl ${item.photos.length > 1 ? "grid-cols-2" : "grid-cols-1"}`}>
            {item.photos.map((photo) => <div className="group relative" key={photo.id}>
              <img src={photo.url} alt={photo.altText} className="max-h-[28rem] h-full w-full object-cover" />
              {item.type === "post" && item.canEdit && <button type="button" className="absolute right-2 top-2 rounded-full bg-ink/75 p-2 text-paper opacity-100 sm:opacity-0 sm:group-hover:opacity-100 sm:focus:opacity-100" aria-label={`Remove photo: ${photo.altText}`} disabled={busy} onClick={() => void removePhoto(photo.id)}><X size={15} /></button>}
            </div>)}
          </div>
        )}
        {item.prayer && (
          <div className="mt-4 flex flex-wrap items-center gap-2 border-y border-line py-3 text-xs">
            <span className="role-label">{item.prayer.category}</span>
            {item.prayer.isAnswered && <span className="status-badge">Answered prayer</span>}
            {item.prayer.isAnswered && item.prayer.answeredNotes && <p className="w-full pt-2 text-sm leading-6 text-muted"><strong className="text-ink">Praise:</strong> {item.prayer.answeredNotes}</p>}
          </div>
        )}
        {item.meeting && (
          <div className="mt-4 border-y border-line py-4">
            <p className="flex items-center gap-2 text-sm"><CalendarDays size={16} className="text-olive" />{formatDate(item.meeting.meetingDate)} at {formatTime(item.meeting.meetingDate)}</p>
            <p className="mt-2 text-sm text-muted">{item.meeting.location}</p>
            <div className="mt-4 flex flex-wrap gap-2">
              {([['attending', 'Going'], ['tentative', 'Maybe'], ['declined', "Can't go"]] as const).map(([status, text]) => (
                <button key={status} className={item.meeting!.rsvps[data.currentUser.personId!] === status ? "primary-button" : "secondary-button"} disabled={busy} onClick={() => void rsvp(status)}>{status === "attending" && <Users size={16} />} {text}</button>
              ))}
              <Link className="secondary-button" to={`/gatherings/${item.meeting.id}`}>View gathering</Link>
            </div>
          </div>
        )}
        {item.type === "announcement" && !item.body && <Megaphone className="text-olive" />}
      </div>

      <div className="flex items-center gap-1 border-t border-line px-3 py-2 sm:px-4">
        <button type="button" className={`secondary-button border-0 ${item.likedByMe ? "text-olive" : ""}`} onClick={() => void like()}>
          <Heart size={16} fill={item.likedByMe ? "currentColor" : "none"} /> {item.likedByMe ? "Unlike" : "Like"}{item.likeCount ? ` · ${item.likeCount}` : ""}
        </button>
        {item.prayer && <button type="button" className={`secondary-button border-0 ${item.prayer.prayedByMe ? "text-olive" : ""}`} disabled={busy} onClick={() => void pray()}><Heart size={16} /> {item.prayer.prayedByMe ? "Praying" : "Pray"} · {item.prayer.prayerCount}</button>}
        <span className="ml-auto inline-flex items-center gap-1 text-xs text-muted"><MessageCircle size={14} /> {item.commentCount}</span>
      </div>
      <FeedComments item={item} onChange={updateComments} />
      {error && <p className="form-error mx-4 mb-4" role="alert">{error}</p>}
    </article>
  );
}
