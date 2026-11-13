import { Check, Pencil, Send, Trash2, X } from "lucide-react";
import { useEffect, useState, type FormEvent } from "react";
import { Link, useLocation } from "react-router-dom";
import { useCircles } from "../AppContext";
import { getErrorMessage } from "../lib/errors";
import { supabase } from "../lib/supabase";
import { addFeedComment, deleteFeedComment, loadFeedComments, updateFeedComment } from "../services/feed";
import type { CommunityFeedItem, FeedComment } from "../types";
import { Avatar } from "./Avatar";

export function FeedComments({ item, onChange }: { item: CommunityFeedItem; onChange: (comments: FeedComment[], commentCount?: number) => void }) {
  const { data, demoMode } = useCircles();
  const { hash } = useLocation();
  const targetedCommentId = hash.startsWith("#comment-") ? hash.slice("#comment-".length) : undefined;
  const [body, setBody] = useState("");
  const [expanded, setExpanded] = useState(Boolean(targetedCommentId));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [editingId, setEditingId] = useState<string>();
  const [editingBody, setEditingBody] = useState("");
  const comments = item.comments;

  useEffect(() => {
    if (!targetedCommentId || !supabase || demoMode || comments.some((comment) => comment.id === targetedCommentId)) return;
    let active = true;
    loadFeedComments(supabase, item.id).then((loaded) => {
      if (!active) return;
      onChange(loaded, item.commentCount);
      window.requestAnimationFrame(() => document.getElementById(`comment-${targetedCommentId}`)?.scrollIntoView({ block: "center" }));
    }).catch((cause) => active && setError(getErrorMessage(cause, "The linked comment could not be loaded.")));
    return () => { active = false; };
  }, [comments, demoMode, item.commentCount, item.id, onChange, targetedCommentId]);
  useEffect(() => {
    if (!targetedCommentId || !comments.some((comment) => comment.id === targetedCommentId)) return;
    window.requestAnimationFrame(() => document.getElementById(`comment-${targetedCommentId}`)?.scrollIntoView({ block: "center" }));
  }, [comments, targetedCommentId]);
  if (!data?.currentUser.personId) return null;

  const expand = async () => {
    if (!expanded && item.commentCount > comments.length && supabase && !demoMode) {
      setBusy(true);
      try { onChange(await loadFeedComments(supabase, item.id), item.commentCount); }
      catch (cause) { setError(getErrorMessage(cause, "Comments could not be loaded.")); }
      finally { setBusy(false); }
    }
    setExpanded(true);
  };
  const submit = async (event: FormEvent) => {
    event.preventDefault();
    const value = body.trim();
    if (!value) return;
    setBusy(true); setError("");
    try {
      if (supabase && !demoMode) {
        await addFeedComment(supabase, item.id, data.currentUser.personId!, value);
        onChange(await loadFeedComments(supabase, item.id), item.commentCount + 1);
      } else {
        onChange([...comments, { id: crypto.randomUUID(), authorPersonId: data.currentUser.personId!, authorName: data.currentUser.fullName, authorAvatarUrl: data.currentUser.avatarUrl, body: value, createdAt: new Date().toISOString(), canEdit: true, canModerate: item.canModerate }], item.commentCount + 1);
      }
      setBody(""); setExpanded(true);
    } catch (cause) { setError(getErrorMessage(cause, "Your comment could not be shared.")); }
    finally { setBusy(false); }
  };
  const remove = async (comment: FeedComment) => {
    setBusy(true); setError("");
    try {
      if (supabase && !demoMode) await deleteFeedComment(supabase, comment.id);
      onChange(comments.filter((entry) => entry.id !== comment.id), Math.max(0, item.commentCount - 1));
    } catch (cause) { setError(getErrorMessage(cause, "This comment could not be removed.")); }
    finally { setBusy(false); }
  };
  const save = async (comment: FeedComment) => {
    const value = editingBody.trim();
    if (!value) return;
    setBusy(true); setError("");
    try {
      if (supabase && !demoMode) await updateFeedComment(supabase, comment.id, value);
      onChange(comments.map((entry) => entry.id === comment.id ? { ...entry, body: value, updatedAt: new Date().toISOString() } : entry), item.commentCount);
      setEditingId(undefined); setEditingBody("");
    } catch (cause) { setError(getErrorMessage(cause, "This comment could not be saved.")); }
    finally { setBusy(false); }
  };
  const shown = expanded ? comments : comments.slice(-2);

  return (
    <div className="border-t border-line px-4 py-4 sm:px-5">
      {item.commentCount > shown.length && (
        <button type="button" className="mb-3 text-xs font-medium text-olive hover:underline" disabled={busy} onClick={() => void expand()}>
          View all {item.commentCount} comments
        </button>
      )}
      <div className="space-y-3">
        {shown.map((comment) => (
          <div className="flex scroll-mt-28 gap-2" key={comment.id} id={`comment-${comment.id}`}>
            <Avatar person={{ id: comment.authorPersonId, fullName: comment.authorName, avatarUrl: comment.authorAvatarUrl }} size="sm" />
            <div className="min-w-0 flex-1 rounded-xl bg-parchment px-3 py-2">
              <div className="flex items-start justify-between gap-3">
                <Link className="text-xs font-medium hover:text-olive hover:underline" to={`/members/${comment.authorPersonId}`}>{comment.authorName}</Link>
                <div className="flex gap-2">
                  {comment.canEdit && editingId !== comment.id && <button type="button" aria-label={`Edit ${comment.authorName}'s comment`} onClick={() => { setEditingId(comment.id); setEditingBody(comment.body); }}><Pencil size={13} className="text-muted" /></button>}
                  {(comment.canEdit || comment.canModerate) && <button type="button" aria-label={`Remove ${comment.authorName}'s comment`} disabled={busy} onClick={() => void remove(comment)}><Trash2 size={13} className="text-muted" /></button>}
                </div>
              </div>
              {editingId === comment.id ? <div className="mt-2">
                <label className="sr-only" htmlFor={`edit-comment-${comment.id}`}>Edit comment</label>
                <textarea id={`edit-comment-${comment.id}`} className="field min-h-20 resize-y text-sm" maxLength={2000} value={editingBody} onChange={(event) => setEditingBody(event.target.value)} />
                <div className="mt-2 flex justify-end gap-2">
                  <button type="button" className="icon-button" aria-label="Cancel editing comment" onClick={() => setEditingId(undefined)}><X size={14} /></button>
                  <button type="button" className="icon-button" aria-label="Save comment" disabled={busy || !editingBody.trim()} onClick={() => void save(comment)}><Check size={14} /></button>
                </div>
              </div> : <p className="mt-1 whitespace-pre-line break-words text-sm leading-6">{comment.body}</p>}
            </div>
          </div>
        ))}
      </div>
      {item.commentsEnabled === false ? <p className="mt-4 text-xs text-muted" role="status">Comments are closed for this post.</p> : <form className="mt-4 flex gap-2" onSubmit={submit}>
        <label className="sr-only" htmlFor={`comment-${item.id}`}>Write a comment</label>
        <input id={`comment-${item.id}`} aria-label="Write a comment" className="field mt-0" maxLength={2000} value={body} onChange={(event) => setBody(event.target.value)} placeholder="Write a comment…" />
        <button className="icon-button shrink-0" disabled={busy || !body.trim()} aria-label="Comment"><Send size={16} /></button>
      </form>}
      {error && <p className="form-error mt-3" role="alert">{error}</p>}
    </div>
  );
}
