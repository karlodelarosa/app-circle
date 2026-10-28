import { ImagePlus, Trash2 } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { useCircles } from "../AppContext";
import { toDateTimeLocal } from "../lib/format";
import { getErrorMessage } from "../lib/errors";
import { validateGatheringCover } from "../lib/images";
import type { Meeting } from "../types";

export function MeetingForm({
  meeting,
  onDone,
}: {
  meeting?: Meeting;
  onDone: () => void;
}) {
  const { data, saveMeeting } = useCircles();
  const manageableGroups = data?.groups.filter(
    (group) => data.currentUser.role === "admin" || group.role === "leader",
  ) ?? [];
  const hasSingleLeaderDestination =
    data?.currentUser.role !== "admin" && manageableGroups.length === 1;
  const [scope, setScope] = useState<"circle" | "organization">(
    meeting?.scope ?? "circle",
  );
  const [groupId, setGroupId] = useState(
    meeting?.groupId ?? (hasSingleLeaderDestination ? manageableGroups[0].id : ""),
  );
  const [title, setTitle] = useState(meeting?.title ?? "");
  const [meetingDate, setMeetingDate] = useState(
    meeting ? toDateTimeLocal(meeting.meetingDate) : "",
  );
  const [endsAt, setEndsAt] = useState(
    meeting ? toDateTimeLocal(meeting.endsAt) : "",
  );
  const [endManuallyEdited, setEndManuallyEdited] = useState(Boolean(meeting));
  const [location, setLocation] = useState(meeting?.location ?? "");
  const [studyTopic, setStudyTopic] = useState(meeting?.studyTopic ?? "");
  const [notes, setNotes] = useState(meeting?.notes ?? "");
  const [summary, setSummary] = useState(meeting?.summary ?? "");
  const [visibility, setVisibility] = useState<"private" | "public">(
    meeting?.visibility ?? "private",
  );
  const [guestRsvpEnabled, setGuestRsvpEnabled] = useState(
    meeting?.guestRsvpEnabled ?? false,
  );
  const [coverFile, setCoverFile] = useState<File>();
  const [removeCover, setRemoveCover] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const coverPreview = useMemo(
    () =>
      coverFile
        ? URL.createObjectURL(coverFile)
        : removeCover
          ? ""
          : meeting?.coverUrl || "",
    [coverFile, meeting?.coverUrl, removeCover],
  );
  useEffect(
    () => () => {
      if (coverPreview.startsWith("blob:")) URL.revokeObjectURL(coverPreview);
    },
    [coverPreview],
  );
  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      if (new Date(endsAt) <= new Date(meetingDate)) {
        throw new Error("End time must be after the start time.");
      }
      await saveMeeting(
        {
          scope,
          groupId: scope === "circle" ? groupId : undefined,
          title,
          meetingDate: new Date(meetingDate).toISOString(),
          endsAt: new Date(endsAt).toISOString(),
          location,
          studyTopic,
          notes,
          summary,
          visibility,
          guestRsvpEnabled,
          coverUrl: meeting?.coverUrl,
          coverFile,
          removeCover,
        },
        meeting?.id,
      );
      onDone();
    } catch (cause) {
      setError(getErrorMessage(cause, "Gathering could not be saved."));
    } finally {
      setBusy(false);
    }
  };
  return (
    <form onSubmit={submit} className="space-y-4">
      <div className="rounded-2xl border border-olive/20 bg-parchment p-4">
        <fieldset disabled={Boolean(meeting)}>
          <legend className="field-label">Who is this gathering for?</legend>
          <div className="mt-3 grid gap-2 sm:grid-cols-2">
            <label className={`flex min-h-12 cursor-pointer items-center gap-3 rounded-xl border px-4 text-sm ${scope === "organization" ? "border-olive bg-sage text-ink" : "border-line bg-paper text-muted"}`}>
              <input
                type="radio"
                name="gathering-scope"
                value="organization"
                checked={scope === "organization"}
                onChange={() => setScope("organization")}
              />
              Entire organization
            </label>
            <label className={`flex min-h-12 cursor-pointer items-center gap-3 rounded-xl border px-4 text-sm ${scope === "circle" ? "border-olive bg-sage text-ink" : "border-line bg-paper text-muted"}`}>
              <input
                type="radio"
                name="gathering-scope"
                value="circle"
                checked={scope === "circle"}
                onChange={() => setScope("circle")}
              />
              A specific Circle
            </label>
          </div>
        </fieldset>
        {scope === "circle" && (
        <label className="field-label">
          Destination Circle
          <select
            className="field"
            value={groupId}
            onChange={(event) => setGroupId(event.target.value)}
            required
            disabled={Boolean(meeting) || hasSingleLeaderDestination}
          >
            <option value="">Choose a Circle</option>
            {manageableGroups.map((group) => (
              <option key={group.id} value={group.id}>{group.name}</option>
            ))}
          </select>
        </label>
        )}
        <p className="mt-2 text-xs leading-5 text-muted">
          {meeting
            ? "Existing gatherings are reassigned from Publish → Content assignments."
            : scope === "organization"
              ? "Everyone in the organization can see this gathering. Public access still follows the visibility setting below."
              : "This gathering will appear only in the selected Circle’s private views."}
        </p>
      </div>
      <label className="field-label">
        Gathering title
        <input
          className="field"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          required
          autoFocus
          placeholder="An evening of grace"
        />
      </label>
      <div className="grid gap-3 sm:grid-cols-2">
        <label className="field-label">
          Starts
          <input
            className="field"
            type="datetime-local"
            value={meetingDate}
            onChange={(event) => {
              const nextStart = event.target.value;
              setMeetingDate(nextStart);
              if (!endManuallyEdited && nextStart) {
                setEndsAt(
                  toDateTimeLocal(
                    new Date(
                      new Date(nextStart).getTime() + 2 * 60 * 60 * 1000,
                    ).toISOString(),
                  ),
                );
              }
            }}
            required
          />
        </label>
        <label className="field-label">
          Ends
          <input
            className="field"
            type="datetime-local"
            value={endsAt}
            onChange={(event) => {
              setEndsAt(event.target.value);
              setEndManuallyEdited(true);
            }}
            min={meetingDate || undefined}
            required
          />
        </label>
      </div>
      <label className="field-label">
        Location
        <input
          className="field"
          value={location}
          onChange={(e) => setLocation(e.target.value)}
          required
          placeholder="Home, room, or meeting link"
        />
      </label>
      <label className="field-label">
        Study topic
        <input
          className="field"
          value={studyTopic}
          onChange={(e) => setStudyTopic(e.target.value)}
          placeholder="Passage or theme"
        />
      </label>
      <label className="field-label">
        Notes
        <textarea
          className="field min-h-24"
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          placeholder="What should everyone bring or know?"
        />
      </label>
      <label className="field-label">
        Public summary
        <textarea
          className="field min-h-20"
          value={summary}
          onChange={(e) => setSummary(e.target.value)}
          placeholder="A brief welcome for the invitation page"
        />
      </label>
      <div>
        <div className="flex items-center justify-between gap-3">
          <span className="field-label">Cover photo (optional)</span>
          {coverPreview && (
            <button
              type="button"
              className="inline-flex min-h-11 items-center gap-2 text-sm text-muted hover:text-ink"
              onClick={() => {
                setCoverFile(undefined);
                setRemoveCover(true);
              }}
            >
              <Trash2 size={15} /> Remove
            </button>
          )}
        </div>
        {coverPreview && (
          <img
            src={coverPreview}
            alt="Gathering cover preview"
            className="mt-2 aspect-[1200/630] w-full rounded-2xl border border-line object-cover"
          />
        )}
        <label className="secondary-button mt-3 min-h-11 w-full cursor-pointer justify-center">
          <ImagePlus size={17} />
          {coverPreview ? "Replace cover photo" : "Choose cover photo"}
          <input
            className="sr-only"
            type="file"
            accept="image/jpeg,image/png,image/webp"
            onChange={(event) => {
              const file = event.target.files?.[0];
              if (!file) return;
              try {
                validateGatheringCover(file);
                setCoverFile(file);
                setRemoveCover(false);
                setError("");
              } catch (cause) {
                setError(getErrorMessage(cause, "Cover photo is not valid."));
                event.target.value = "";
              }
            }}
          />
        </label>
        <p className="mt-2 text-xs leading-5 text-muted">
          JPG, PNG, or WebP up to 10 MB. The center crop is used on invitations
          and shared links.
        </p>
      </div>
      <div className="grid grid-cols-2 gap-3">
        <label className="field-label">
          Visibility
          <select
            className="field"
            value={visibility}
            onChange={(e) =>
              setVisibility(e.target.value as "private" | "public")
            }
          >
            <option value="private">Private</option>
            <option value="public">Public</option>
          </select>
        </label>
        <label className="mt-7 flex items-center gap-3 text-sm">
          <input
            type="checkbox"
            checked={guestRsvpEnabled}
            onChange={(e) => setGuestRsvpEnabled(e.target.checked)}
          />
          Allow guest RSVP
        </label>
      </div>
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
      <button disabled={busy} className="primary-button w-full">
        {busy ? "Saving…" : meeting ? "Save changes" : "Create gathering"}
      </button>
    </form>
  );
}
