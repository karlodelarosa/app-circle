import { Heart, ImagePlus, MessageSquareText, Send, X } from "lucide-react";
import { useRef, useState, type FormEvent } from "react";
import { useCircles } from "../AppContext";
import { getErrorMessage } from "../lib/errors";
import { validateFeedPhotos } from "../lib/images";
import { supabase } from "../lib/supabase";
import { createFeedPost, uploadFeedPhotos } from "../services/feed";
import type { CommunityFeedItem, FeedAudience } from "../types";
import { Avatar } from "./Avatar";

export function FeedComposer({ onCreated, onPrayer }: { onCreated: (item?: CommunityFeedItem) => void; onPrayer: () => void }) {
  const { data, demoMode } = useCircles();
  const [body, setBody] = useState("");
  const [audience, setAudience] = useState("organization");
  const [photos, setPhotos] = useState<Array<{ file: File; altText: string }>>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);
  if (!data) return null;

  const choosePhotos = (files: File[]) => {
    try {
      const next = [...photos, ...files];
      validateFeedPhotos(next.map((photo) => "file" in photo ? photo.file : photo));
      setError("");
      setPhotos(next.map((photo) => "file" in photo ? photo : ({ file: photo, altText: "" })));
    } catch (cause) {
      setError(getErrorMessage(cause, "Those photos could not be added."));
    }
  };
  const submit = async (event: FormEvent) => {
    event.preventDefault();
    const value = body.trim();
    if (!value && !photos.length) return;
    if (photos.some((photo) => !photo.altText.trim())) {
      setError("Describe each photo before sharing.");
      return;
    }
    const scope: FeedAudience = audience === "organization" ? "organization" : "circle";
    setBusy(true);
    setError("");
    try {
      if (demoMode || !supabase) {
        onCreated({
          id: crypto.randomUUID(), type: "post", sourceId: crypto.randomUUID(), audience: scope,
          groupId: scope === "circle" ? audience : undefined,
          destinationName: scope === "organization" ? "Entire organization" : data.groups.find((group) => group.id === audience)?.name || "Circle",
          authorPersonId: data.currentUser.personId, authorName: data.currentUser.fullName,
          authorAvatarUrl: data.currentUser.avatarUrl, body: value, createdAt: new Date().toISOString(),
          photos: [], comments: [], commentCount: 0, likeCount: 0, likedByMe: false, canEdit: true, canModerate: data.currentUser.role === "admin",
        });
      } else {
        const uploaded = await uploadFeedPhotos(supabase, data.organization.id, data.currentUser.personId!, photos);
        await createFeedPost(supabase, {
          organizationId: data.organization.id,
          authorPersonId: data.currentUser.personId!,
          audience: scope,
          groupId: scope === "circle" ? audience : undefined,
          body: value,
          photos: uploaded,
        });
        onCreated();
      }
      setBody("");
      setAudience("organization");
      setPhotos([]);
      if (inputRef.current) inputRef.current.value = "";
    } catch (cause) {
      setError(getErrorMessage(cause, "Your update could not be shared."));
    } finally {
      setBusy(false);
    }
  };

  return (
    <form className="paper-panel p-4 sm:p-5" onSubmit={submit} aria-label="Create a community post">
      <div className="flex gap-3">
        <Avatar person={data.currentUser} />
        <label className="sr-only" htmlFor="feed-update">Share an update</label>
        <textarea id="feed-update" className="field mt-0 min-h-24 resize-y" maxLength={5000} value={body} onChange={(event) => setBody(event.target.value)} placeholder={`Share something with ${data.organization.name}…`} />
      </div>
      {photos.length > 0 && (
        <div className="mt-4 grid gap-3 sm:grid-cols-2">
          {photos.map((photo, index) => (
            <div className="relative" key={`${photo.file.name}-${index}`}>
              <label className="field-label">
                Describe {photo.file.name}
                <input className="field pr-10" maxLength={300} required value={photo.altText} onChange={(event) => setPhotos((current) => current.map((item, itemIndex) => itemIndex === index ? { ...item, altText: event.target.value } : item))} />
              </label>
              <button type="button" className="absolute bottom-2 right-2 p-2 text-muted hover:text-ink" aria-label={`Remove ${photo.file.name}`} onClick={() => setPhotos((current) => current.filter((_, itemIndex) => itemIndex !== index))}><X size={15} /></button>
            </div>
          ))}
        </div>
      )}
      <div className="mt-4 flex flex-col gap-3 border-t border-line pt-4 sm:flex-row sm:items-end sm:justify-between">
        <div className="flex flex-wrap items-end gap-3">
          <label className="field-label text-xs">
            Audience
            <select className="field mt-1 min-w-48 bg-paper text-sm" aria-label="Post audience" value={audience} onChange={(event) => setAudience(event.target.value)}>
              <option value="organization">Entire organization</option>
              {data.groups.map((group) => <option value={group.id} key={group.id}>{group.name}</option>)}
            </select>
          </label>
          <button className="secondary-button" type="button" disabled={photos.length >= 4} onClick={() => inputRef.current?.click()}>
            <ImagePlus size={16} /> Add photos
          </button>
          <button className="secondary-button" type="button" onClick={onPrayer}>
            <Heart size={16} /> Prayer request
          </button>
          <input ref={inputRef} className="sr-only" type="file" accept="image/jpeg,image/png,image/webp" multiple onChange={(event) => { choosePhotos(Array.from(event.target.files ?? [])); event.target.value = ""; }} />
        </div>
        <button className="primary-button justify-center" disabled={busy || (!body.trim() && !photos.length)}>
          {photos.length ? <MessageSquareText size={16} /> : <Send size={16} />} {busy ? "Sharing…" : "Post update"}
        </button>
      </div>
      {error && <p className="form-error mt-3" role="alert">{error}</p>}
    </form>
  );
}
