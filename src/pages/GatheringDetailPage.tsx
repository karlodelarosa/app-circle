import { useEffect, useRef, useState, type FormEvent } from "react";
import {
  ArrowLeft,
  CalendarDays,
  Check,
  Copy,
  MapPin,
  Share2,
  UserPlus,
  UsersRound,
} from "lucide-react";
import { Link, useParams } from "react-router-dom";
import { useCircles } from "../AppContext";
import { Avatar } from "../components/Avatar";
import { GatheringReflections } from "../components/GatheringReflections";
import { Modal } from "../components/Modal";
import { getErrorMessage } from "../lib/errors";
import {
  formatGatheringDateTime,
  gatheringLifecycle,
  gatheringRelativeStatus,
  rsvpLabel,
} from "../lib/gatheringLifecycle";
import { gatheringCoverImage } from "../lib/images";
import { gatheringShareUrl } from "../lib/publicLinks";
import { copyText, shareLink } from "../lib/share";
import { supabase } from "../lib/supabase";
import {
  loadGatheringAttendance,
  recordAttendance,
  setGatheringCompletion,
  stageWalkIn,
} from "../services/circles";
import type { ContactPreference, RsvpStatus } from "../types";

const rsvpOptions: { value: RsvpStatus; label: string }[] = [
  { value: "attending", label: "I’m going" },
  { value: "tentative", label: "Maybe" },
  { value: "declined", label: "Can’t go" },
];

export function GatheringDetailPage() {
  const { id } = useParams();
  const { data, demoMode, refresh, setRsvp } = useCircles();
  const [guests, setGuests] = useState<
    {
      id: string;
      guest_name: string;
      status: string;
      email: string;
      phone: string;
      converted_person_id?: string;
      attended_at?: string;
    }[]
  >([]);
  const [selected, setSelected] = useState<string[]>([]);
  const [guestSelected, setGuestSelected] = useState<string[]>([]);
  const [walkInOpen, setWalkInOpen] = useState(false);
  const [walkInBusy, setWalkInBusy] = useState(false);
  const [walkInError, setWalkInError] = useState("");
  const [walkInNotice, setWalkInNotice] = useState("");
  const [walkInForm, setWalkInForm] = useState({
    firstName: "",
    lastName: "",
    email: "",
    phone: "",
    preferredContact: "either" as ContactPreference,
    consent: false,
  });
  const [saved, setSaved] = useState(false);
  const [rsvpBusy, setRsvpBusy] = useState(false);
  const [rsvpError, setRsvpError] = useState("");
  const [attendanceBusy, setAttendanceBusy] = useState(false);
  const [attendanceError, setAttendanceError] = useState("");
  const [guestLoadError, setGuestLoadError] = useState("");
  const [completionBusy, setCompletionBusy] = useState(false);
  const [completionError, setCompletionError] = useState("");
  const [completionConfirmOpen, setCompletionConfirmOpen] = useState(false);
  const [shareStatus, setShareStatus] = useState("");
  const attendanceInitializedFor = useRef<string>();
  const meeting = (data?.accessibleMeetings ?? data?.meetings)?.find((item) => item.id === id);
  const attendanceMembers = meeting?.scope === "organization"
    ? data?.organizationMembers ?? []
    : data?.members ?? [];
  const attending =
    data && meeting
      ? attendanceMembers.filter(
          (member) => meeting.rsvps[member.id] === "attending",
        )
      : [];
  const canLead = Boolean(
    data &&
    meeting &&
    (meeting.canManage ?? data.currentUser.role !== "member"),
  );
  useEffect(() => {
    if (!meeting) return;
    if (attendanceInitializedFor.current === meeting.id) return;
    attendanceInitializedFor.current = meeting.id;
    setSelected([]);
    setGuestSelected([]);
    setSaved(false);
  }, [meeting]);
  useEffect(() => {
    if (!meeting || demoMode || !supabase || !canLead) return;
    let active = true;
    setGuestLoadError("");
    void Promise.all([
      loadGatheringAttendance(supabase, meeting.id),
      supabase
        .from("circle_guest_rsvps")
        .select("id,guest_name,status,email,phone,converted_person_id,attended_at")
        .eq("gathering_id", meeting.id),
    ])
        .then(([attendance, { data: rows, error }]) => {
          if (!active) return;
          if (error) {
            setGuestLoadError(getErrorMessage(error, "Guest RSVPs could not be loaded."));
            return;
          }
          setGuests(rows ?? []);
          if (attendance.saved) {
            setSelected(attendance.personIds);
            setGuestSelected(attendance.guestRsvpIds);
            setSaved(true);
          }
        })
        .catch((cause) => {
          if (active)
            setGuestLoadError(
              getErrorMessage(cause, "Attendance and guest RSVPs could not be loaded."),
            );
        });
    return () => {
      active = false;
    };
  }, [meeting?.id, canLead, demoMode]);
  if (!data) return null;
  const base = "";
  if (!meeting)
    return (
      <div className="empty-state">
        <CalendarDays />
        <h2>Gathering not found</h2>
        <Link to={`${base}/gatherings`} className="text-link">
          Return to gatherings
        </Link>
      </div>
    );
  const lifecycle = gatheringLifecycle(meeting);
  const attendanceEditable =
    meeting.status === "scheduled" && lifecycle !== "upcoming";
  const saveAttendance = async () => {
    setAttendanceBusy(true);
    setAttendanceError("");
    setSaved(false);
    try {
      if (!demoMode && supabase)
        await recordAttendance(supabase, meeting.id, selected, guestSelected);
      setSaved(true);
    } catch (cause) {
      setAttendanceError(
        getErrorMessage(cause, "Attendance could not be saved."),
      );
    } finally {
      setAttendanceBusy(false);
    }
  };
  const chooseRsvp = async (status: RsvpStatus) => {
    setRsvpBusy(true);
    setRsvpError("");
    try {
      await setRsvp(meeting.id, status);
    } catch (cause) {
      setRsvpError(getErrorMessage(cause, "Your RSVP could not be saved."));
    } finally {
      setRsvpBusy(false);
    }
  };
  const changeCompletion = async (completed: boolean) => {
    setCompletionBusy(true);
    setCompletionError("");
    try {
      if (!demoMode && supabase)
        await setGatheringCompletion(supabase, meeting.id, completed);
      setCompletionConfirmOpen(false);
      await refresh();
    } catch (cause) {
      setCompletionError(
        getErrorMessage(cause, "The gathering status could not be changed."),
      );
    } finally {
      setCompletionBusy(false);
    }
  };
  const addWalkIn = async (event: FormEvent) => {
    event.preventDefault();
    if (!data.group) return;
    setWalkInBusy(true);
    setWalkInError("");
    try {
      const result = !demoMode && supabase
        ? await stageWalkIn(supabase, meeting.id, {
            name: `${walkInForm.firstName} ${walkInForm.lastName}`.trim(),
            email: walkInForm.email,
            phone: walkInForm.phone,
            preferredContact: walkInForm.preferredContact,
            consent: walkInForm.consent,
          })
        : {
            guestRsvpId: crypto.randomUUID(),
            connectionId: crypto.randomUUID(),
          };
      const fullName = `${walkInForm.firstName} ${walkInForm.lastName}`.trim();
      setGuests((items) =>
        items.some((guest) => guest.id === result.guestRsvpId)
          ? items
          : [
              ...items,
              {
                id: result.guestRsvpId,
                guest_name: fullName,
                status: "attending",
                email: walkInForm.email,
                phone: walkInForm.phone,
              },
            ],
      );
      setGuestSelected((ids) =>
        ids.includes(result.guestRsvpId)
          ? ids
          : [...ids, result.guestRsvpId],
      );
      setSaved(false);
      setWalkInNotice(
        `${fullName} was staged as a guest and selected for attendance. No SheepCount People record was created.`,
      );
      setWalkInForm({
        firstName: "",
        lastName: "",
        email: "",
        phone: "",
        preferredContact: "either",
        consent: false,
      });
      setWalkInOpen(false);
    } catch (cause) {
      setWalkInError(
        getErrorMessage(cause, "The walk-in visitor could not be registered."),
      );
    } finally {
      setWalkInBusy(false);
    }
  };
  const invitationUrl = meeting.slug
    ? gatheringShareUrl(data.organization.slug, meeting.slug)
    : "";
  const copyInvitation = async () => {
    setShareStatus("");
    try {
      await copyText(invitationUrl);
      setShareStatus("RSVP link copied.");
    } catch {
      setShareStatus("The RSVP link could not be copied.");
    }
  };
  const shareInvitation = async () => {
    setShareStatus("");
    try {
      const result = await shareLink(meeting.title, invitationUrl);
      if (result === "copied") setShareStatus("RSVP link copied.");
    } catch {
      setShareStatus("The invitation could not be shared.");
    }
  };
  const canShare = Boolean(
    canLead &&
      lifecycle === "upcoming" &&
      meeting.visibility === "public" &&
      meeting.guestRsvpEnabled &&
      meeting.slug,
  );
  return (
    <div className="mx-auto max-w-4xl">
      <Link
        to={`${base}/gatherings`}
        className="mb-7 inline-flex items-center gap-2 text-sm text-muted hover:text-olive"
      >
        <ArrowLeft size={16} /> All gatherings
      </Link>
      <article className="overflow-hidden rounded-[1.75rem] border border-line bg-paper">
        <header className="relative flex min-h-[20rem] items-end overflow-hidden border-b border-line p-6 sm:min-h-[24rem] sm:p-10">
          <img
            src={gatheringCoverImage(meeting.slug || meeting.id, meeting.coverUrl)}
            alt=""
            className="absolute inset-0 h-full w-full object-cover object-center"
          />
          <div className="absolute inset-0 bg-[#30362A]/75" />
          <div className="relative max-w-4xl text-paper">
            <p className="text-sm text-[#D9DDCE]">
              {meeting.status === "cancelled"
                ? "Cancelled gathering"
                : meeting.status === "completed"
                  ? "Completed gathering"
                : lifecycle === "live"
                  ? "Happening now"
                : lifecycle === "attendance_pending"
                  ? "This gathering has ended"
                : meeting.scope === "organization"
                  ? "Everyone is welcome"
                  : meeting.destinationName || "Our next gathering"}
            </p>
            <h1 className="mt-2 max-w-4xl font-display text-4xl leading-[1.02] sm:text-6xl lg:text-7xl">
              {meeting.title}
            </h1>
            <p className="mt-4 font-display text-2xl text-[#D9DDCE] sm:text-3xl">
              {meeting.studyTopic}
            </p>
          </div>
        </header>
        <div className="grid gap-8 p-6 sm:p-10 md:grid-cols-[1fr_.75fr]">
          <div>
            <div className="space-y-3 text-sm">
              <p className="flex items-start gap-3">
                <CalendarDays size={18} className="mt-0.5 text-olive" />
                <span>
                  {formatGatheringDateTime(meeting.meetingDate, meeting.endsAt)}
                  {lifecycle === "attendance_pending" && (
                    <><br /><span className="text-muted">{gatheringRelativeStatus(meeting.endsAt)}</span></>
                  )}
                </span>
              </p>
              <p className="flex items-start gap-3">
                <MapPin size={18} className="mt-0.5 text-olive" />
                <span>{meeting.location}</span>
              </p>
            </div>
            <div className="mt-8 border-l-2 border-sage pl-5">
              <h2 className="font-display text-2xl">A note for the evening</h2>
              <p className="mt-2 leading-7 text-muted">{meeting.notes}</p>
            </div>
            {canShare && (
              <div className="mt-8 border-t border-line pt-6">
                <p className="text-xs text-muted">Guest invitation</p>
                <div className="mt-3 flex flex-wrap gap-2">
                  <button
                    className="secondary-button"
                    onClick={() => void shareInvitation()}
                  >
                    <Share2 size={16} /> Share invitation
                  </button>
                  <button
                    className="secondary-button"
                    onClick={() => void copyInvitation()}
                  >
                    <Copy size={16} /> Copy RSVP link
                  </button>
                </div>
                {shareStatus && (
                  <p className="mt-3 text-sm text-muted" role="status">
                    {shareStatus}
                  </p>
                )}
              </div>
            )}
          </div>
          <div className="border-t border-line pt-7 md:border-l md:border-t-0 md:pl-8 md:pt-0">
            <h2 className="flex items-center gap-2 font-display text-2xl">
              <UsersRound size={20} /> Who’s coming
            </h2>
            <div className="mt-4 space-y-3">
              {attending.length ? (
                attending.map((member) => (
                  <div key={member.id} className="flex items-center gap-3">
                    <Avatar person={member} />
                    <span className="text-sm">{member.fullName}</span>
                  </div>
                ))
              ) : (
                <p className="text-sm text-muted">
                  No members have said they’re going yet.
                </p>
              )}
            </div>
            <p className="mt-5 text-xs leading-5 text-muted">
              This list shows confirmed Circle members. {canLead
                ? "Guest RSVPs appear in the leader attendance list below."
                : "Guest RSVPs are visible to gathering leaders."}
            </p>
          </div>
        </div>
        {lifecycle === "upcoming" && data.currentUser.personId && (
          <footer className="border-t border-line px-6 py-5 sm:px-10">
            <p className="mb-3 text-xs text-muted">Can you make it?</p>
            <div className="flex flex-wrap gap-2">
              {rsvpOptions.map((option) => (
                <button
                  key={option.value}
                  onClick={() => void chooseRsvp(option.value)}
                  disabled={rsvpBusy}
                  aria-pressed={meeting.rsvps[data.currentUser.personId!] === option.value}
                  className={`rsvp-button ${meeting.rsvps[data.currentUser.personId!] === option.value ? "rsvp-button-active" : ""}`}
                >
                  {option.label}
                </button>
              ))}
            </div>
            {rsvpError && (
              <p className="form-error mt-3" role="alert">
                {rsvpError}
              </p>
            )}
          </footer>
        )}
        {(lifecycle === "live" || lifecycle === "attendance_pending") &&
          data.currentUser.personId && (
            <footer className="border-t border-line px-6 py-5 sm:px-10">
              <p className="text-sm font-medium">
                {lifecycle === "live" ? "Happening now" : "This gathering has ended"}
              </p>
              <p className="mt-1 text-sm text-muted">RSVPs are closed.</p>
            </footer>
          )}
      </article>
      {meeting.status === "completed" && (
        <GatheringReflections meeting={meeting} canModerate={canLead} />
      )}
      {canLead && (
        <section className="paper-panel mt-7 p-6 sm:p-8">
          {lifecycle === "attendance_pending" && (
            <div className="mb-7 rounded-xl border border-olive/25 bg-parchment p-4" role="status">
              <p className="font-medium text-olive">Attendance needs review</p>
              <p className="mt-1 text-sm text-muted">Save the final roster, then complete this gathering.</p>
            </div>
          )}
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className="page-kicker">Leader view</p>
              <h2 className="mt-1 font-display text-3xl">
                RSVPs and attendance
              </h2>
              <p className="mt-2 text-sm text-muted">
                Known people are recorded in SheepCount attendance. Unconverted
                guests remain staged in Circles.
              </p>
            </div>
            {saved && meeting.status !== "completed" && (
              <span className="flex items-center gap-2 text-sm text-olive">
                <Check size={16} />
                Saved
              </span>
            )}
          </div>
          <div className="mt-7 grid gap-8 md:grid-cols-2">
            <div>
              <div className="flex items-center justify-between gap-3">
                <h3 className="font-medium">People</h3>
                {attendanceEditable && (
                  <button
                    className="text-link"
                    onClick={() => {
                      setWalkInError("");
                      setWalkInOpen(true);
                    }}
                  >
                    <UserPlus size={15} /> Add walk-in
                  </button>
                )}
              </div>
              <div className="mt-3 space-y-2">
                {attendanceMembers.map((member) => (
                  <label
                    key={member.id}
                    className="flex items-center gap-3 rounded-xl border border-line p-3 text-sm"
                  >
                    <input
                      type="checkbox"
                      checked={selected.includes(member.id)}
                      disabled={!attendanceEditable}
                      onChange={(event) => {
                        setSaved(false);
                        setSelected(
                          event.target.checked
                            ? [...selected, member.id]
                            : selected.filter((id) => id !== member.id),
                        );
                      }}
                    />
                    <Avatar person={member} size="sm" />
                    {member.fullName}
                    <span className="ml-auto text-xs text-muted">
                      {rsvpLabel(meeting.rsvps[member.id])}
                    </span>
                  </label>
                ))}
              </div>
            </div>
            <div>
              <h3 className="font-medium">Guest RSVPs</h3>
              <div className="mt-3 space-y-2">
                {guestLoadError ? (
                  <p className="form-error" role="alert">{guestLoadError}</p>
                ) : guests.length ? (
                  guests.map((guest) => (
                    <label
                      key={guest.id}
                      className="flex items-center gap-3 rounded-xl border border-line p-3 text-sm"
                    >
                      <input
                        type="checkbox"
                        checked={guestSelected.includes(guest.id)}
                        disabled={!attendanceEditable}
                        onChange={(event) => {
                          setSaved(false);
                          setGuestSelected(
                            event.target.checked
                              ? [...guestSelected, guest.id]
                              : guestSelected.filter((id) => id !== guest.id),
                          );
                        }}
                      />
                      <span>{guest.guest_name}</span>
                      <span className="ml-auto text-xs text-muted">
                        {guest.converted_person_id ? "Matched" : guest.status}
                      </span>
                    </label>
                  ))
                ) : (
                  <p className="text-sm text-muted">No guest RSVPs yet.</p>
                )}
              </div>
            </div>
          </div>
          {walkInNotice && (
            <p
              role="status"
              className="mt-5 rounded-xl bg-parchment p-4 text-sm text-muted"
            >
              {walkInNotice}
            </p>
          )}
          <div className="mt-7 border-t border-line pt-6">
            <div className="flex flex-wrap items-center gap-3">
              {meeting.status !== "completed" && (
                <button
                  className={saved && lifecycle === "attendance_pending" ? "secondary-button" : "primary-button"}
                  onClick={() => void saveAttendance()}
                  disabled={attendanceBusy || !attendanceEditable}
                >
                  {attendanceBusy ? "Saving…" : "Save attendance"}
                </button>
              )}
              {meeting.status === "completed" ? (
                <button
                  className="secondary-button"
                  onClick={() => void changeCompletion(false)}
                  disabled={completionBusy}
                >
                  {completionBusy ? "Reopening…" : "Reopen gathering"}
                </button>
              ) : lifecycle === "attendance_pending" ? (
                <button
                  className={saved ? "primary-button" : "secondary-button"}
                  onClick={() => setCompletionConfirmOpen(true)}
                  disabled={completionBusy || !saved}
                >
                  {completionBusy ? "Completing…" : "Complete gathering"}
                </button>
              ) : null}
            </div>
            {lifecycle === "upcoming" && (
              <p className="mt-3 text-xs leading-5 text-muted">
                Attendance becomes available when the gathering begins.
              </p>
            )}
            {lifecycle === "live" && (
              <p className="mt-3 text-xs leading-5 text-muted">
                Record attendance now. Completion becomes available after the gathering ends.
              </p>
            )}
            {lifecycle === "attendance_pending" && !saved && (
              <p className="mt-3 text-xs leading-5 text-muted">Save attendance before completing this gathering.</p>
            )}
            {saved && (
              <p className="mt-3 text-sm text-olive" role="status">
                Attendance saved. This gathering is still {meeting.status}.
              </p>
            )}
            {attendanceError && (
              <p className="form-error mt-3" role="alert">
                {attendanceError}
              </p>
            )}
            {completionError && (
              <p className="form-error mt-3" role="alert">
                {completionError}
              </p>
            )}
          </div>
        </section>
      )}
      {completionConfirmOpen && (
        <Modal title="Complete this gathering?" onClose={() => setCompletionConfirmOpen(false)}>
          <p className="leading-7 text-muted">
            Attendance will become read-only and the gathering will move to Previous gatherings. You can reopen it later to make corrections.
          </p>
          <div className="mt-6 flex flex-wrap justify-end gap-3">
            <button className="secondary-button" onClick={() => setCompletionConfirmOpen(false)}>Cancel</button>
            <button className="primary-button" disabled={completionBusy} onClick={() => void changeCompletion(true)}>
              {completionBusy ? "Completing…" : "Complete gathering"}
            </button>
          </div>
        </Modal>
      )}
      {walkInOpen && (
        <Modal
          title="Add a walk-in visitor"
          onClose={() => setWalkInOpen(false)}
        >
          <form onSubmit={addWalkIn} className="grid gap-4 sm:grid-cols-2">
            <p className="text-sm leading-6 text-muted sm:col-span-2">
              Record attendance now and review possible SheepCount matches
              later. This does not create a People record or Circle membership.
            </p>
            <label className="field-label">
              First name
              <input
                className="field"
                required
                autoFocus
                value={walkInForm.firstName}
                onChange={(event) =>
                  setWalkInForm({
                    ...walkInForm,
                    firstName: event.target.value,
                  })
                }
              />
            </label>
            <label className="field-label">
              Last name
              <input
                className="field"
                required
                value={walkInForm.lastName}
                onChange={(event) =>
                  setWalkInForm({ ...walkInForm, lastName: event.target.value })
                }
              />
            </label>
            <label className="field-label">
              Email
              <input
                className="field"
                type="email"
                value={walkInForm.email}
                onChange={(event) =>
                  setWalkInForm({ ...walkInForm, email: event.target.value })
                }
              />
            </label>
            <label className="field-label">
              Phone
              <input
                className="field"
                value={walkInForm.phone}
                onChange={(event) =>
                  setWalkInForm({ ...walkInForm, phone: event.target.value })
                }
              />
            </label>
            <label className="field-label sm:col-span-2">
              Preferred contact
              <select
                className="field"
                value={walkInForm.preferredContact}
                onChange={(event) =>
                  setWalkInForm({
                    ...walkInForm,
                    preferredContact: event.target.value as ContactPreference,
                  })
                }
              >
                <option value="either">Either email or phone</option>
                <option value="email">Email</option>
                <option value="phone">Phone</option>
              </select>
            </label>
            <label className="flex items-start gap-3 text-sm leading-6 text-muted sm:col-span-2">
              <input
                type="checkbox"
                className="mt-1 h-4 w-4 shrink-0"
                checked={walkInForm.consent}
                onChange={(event) =>
                  setWalkInForm({ ...walkInForm, consent: event.target.checked })
                }
              />
              The guest agreed that a Circle leader may contact them after this gathering.
            </label>
            {walkInError && (
              <p className="form-error sm:col-span-2" role="alert">
                {walkInError}
              </p>
            )}
            <button
              className="primary-button sm:col-span-2"
              disabled={
                walkInBusy ||
                (!walkInForm.email && !walkInForm.phone) ||
                (walkInForm.preferredContact === "email" && !walkInForm.email) ||
                (walkInForm.preferredContact === "phone" && !walkInForm.phone)
              }
            >
              {walkInBusy ? "Saving…" : "Stage guest and select"}
            </button>
          </form>
        </Modal>
      )}
    </div>
  );
}
