import {
  CalendarDays,
  ChevronRight,
  Clock3,
  Copy,
  MapPin,
  MoreHorizontal,
  Plus,
  QrCode,
  Users,
} from "lucide-react";
import { useState } from "react";
import { useEffect } from "react";
import { Link } from "react-router-dom";
import { useCircles } from "../AppContext";
import { MeetingForm } from "../components/MeetingForm";
import { Modal } from "../components/Modal";
import { formatDate, formatTime } from "../lib/format";
import { gatheringShareUrl } from "../lib/publicLinks";
import type { Meeting } from "../types";

function GuestInvitationShare({
  meeting,
  organizationSlug,
}: {
  meeting: Meeting;
  organizationSlug: string;
}) {
  const [qr, setQr] = useState("");
  const link = gatheringShareUrl(organizationSlug, meeting.slug || "");
  useEffect(() => {
    void import("qrcode")
      .then(({ default: QRCode }) =>
        QRCode.toDataURL(link, {
          width: 320,
          margin: 2,
          color: { dark: "#292B24", light: "#FCFAF5" },
        }),
      )
      .then(setQr);
  }, [link]);
  return (
    <div className="text-center">
      {qr && (
        <img
          src={qr}
          alt={`QR code for the ${meeting.title} guest invitation`}
          className="mx-auto w-full max-w-72 rounded-xl border border-line"
        />
      )}
      <p className="mt-5 text-sm leading-6 text-muted">
        Guests can view this gathering and RSVP without creating a SheepCount
        People record.
      </p>
      <button
        className="primary-button mt-5 w-full"
        onClick={() => void navigator.clipboard?.writeText(link)}
      >
        <Copy size={16} /> Copy guest link
      </button>
    </div>
  );
}

export function GatheringsPage() {
  const { data, cancelMeeting } = useCircles();
  const [editing, setEditing] = useState<Meeting | "new" | null>(null);
  const [menu, setMenu] = useState<string | null>(null);
  const [sharing, setSharing] = useState<Meeting | null>(null);
  if (!data) return null;
  const isLeader =
    data.currentUser.role === "admin" || data.group?.role === "leader";
  const base = "";
  const now = new Date().toISOString();
  const upcoming = data.meetings
    .filter((item) => item.meetingDate >= now)
    .sort((a, b) => a.meetingDate.localeCompare(b.meetingDate));
  const previous = data.meetings
    .filter((item) => item.meetingDate < now)
    .sort((a, b) => b.meetingDate.localeCompare(a.meetingDate));

  return (
    <div>
      <div className="page-heading">
        <div>
          <p className="page-kicker">Time around the table</p>
          <h1>Gatherings</h1>
          <p>Come as you are. Leave a little more rooted.</p>
        </div>
        {isLeader && (
          <button className="primary-button" onClick={() => setEditing("new")}>
            <Plus size={17} /> Plan a gathering
          </button>
        )}
      </div>
      <section className="mt-8">
        <h2 className="subheading">Coming up</h2>
        {upcoming.length ? (
          <div className="mt-4 space-y-4">
            {upcoming.map((meeting, index) => {
              const attending = Object.values(meeting.rsvps).filter(
                (status) => status === "attending",
              ).length;
              return (
                <article
                  key={meeting.id}
                  className={`gathering-card ${meeting.status === "cancelled" ? "opacity-60" : ""}`}
                >
                  <div className="date-block">
                    <span>
                      {formatDate(meeting.meetingDate, { month: "short" })}
                    </span>
                    <strong>{new Date(meeting.meetingDate).getDate()}</strong>
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-start justify-between gap-4">
                      <div>
                        <div className="flex items-center gap-2">
                          <h3>{meeting.title}</h3>
                          {meeting.status === "cancelled" && (
                            <span className="status-badge">Cancelled</span>
                          )}
                        </div>
                        <p className="mt-1 font-display text-lg text-olive">
                          {meeting.studyTopic}
                        </p>
                      </div>
                      {isLeader && meeting.status !== "cancelled" && (
                        <div className="relative">
                          <button
                            className="icon-button"
                            onClick={() =>
                              setMenu(menu === meeting.id ? null : meeting.id)
                            }
                            aria-label="Gathering actions"
                          >
                            <MoreHorizontal size={19} />
                          </button>
                          {menu === meeting.id && (
                            <div className="action-menu">
                              <button
                                onClick={() => {
                                  setEditing(meeting);
                                  setMenu(null);
                                }}
                              >
                                Edit gathering
                              </button>
                              <button
                                className="text-red-700"
                                onClick={() => {
                                  if (
                                    window.confirm(
                                      "Cancel this gathering? Members will continue to see it as cancelled.",
                                    )
                                  )
                                    void cancelMeeting(meeting.id);
                                  setMenu(null);
                                }}
                              >
                                Cancel gathering
                              </button>
                            </div>
                          )}
                        </div>
                      )}
                    </div>
                    <div className="mt-4 flex flex-wrap gap-x-5 gap-y-2 text-sm text-muted">
                      <span>
                        <Clock3 size={15} /> {formatTime(meeting.meetingDate)}
                      </span>
                      <span>
                        <MapPin size={15} /> {meeting.location}
                      </span>
                      <span>
                        <Users size={15} /> {attending} going
                      </span>
                    </div>
                    {isLeader &&
                      meeting.status === "scheduled" &&
                      meeting.visibility === "public" &&
                      meeting.guestRsvpEnabled &&
                      meeting.slug && (
                        <div className="mt-4 flex flex-wrap items-center gap-2">
                          <button
                            className="secondary-button"
                            onClick={() => setSharing(meeting)}
                          >
                            <QrCode size={15} /> Show invitation QR
                          </button>
                          <button
                            className="secondary-button"
                            onClick={() =>
                              void navigator.clipboard?.writeText(
                                gatheringShareUrl(
                                  data.organization.slug,
                                  meeting.slug || "",
                                ),
                              )
                            }
                          >
                            <Copy size={15} /> Copy guest link
                          </button>
                        </div>
                      )}
                    {index === 0 && (
                      <p className="mt-4 line-clamp-2 max-w-2xl text-sm leading-6 text-muted">
                        {meeting.notes}
                      </p>
                    )}
                    <Link
                      to={`${base}/gatherings/${meeting.id}`}
                      className="mt-4 inline-flex items-center gap-1 text-sm font-medium text-olive"
                    >
                      View gathering <ChevronRight size={15} />
                    </Link>
                  </div>
                </article>
              );
            })}
          </div>
        ) : (
          <div className="empty-state mt-4">
            <CalendarDays />
            <h2>No gathering planned</h2>
            <p>
              {isLeader
                ? "Plan the next time your circle will meet."
                : "Your leader will share the next gathering here."}
            </p>
          </div>
        )}
      </section>
      <section className="mt-12">
        <div className="section-heading">
          <div>
            <h2>From our study table</h2>
            <p>Notes and passages from previous gatherings.</p>
          </div>
        </div>
        <div className="divide-y divide-line border-y border-line">
          {previous.map((meeting) => (
            <Link
              key={meeting.id}
              to={`${base}/gatherings/${meeting.id}`}
              className="study-row"
            >
              <div>
                <div className="text-xs text-muted">
                  {formatDate(meeting.meetingDate, {
                    month: "long",
                    day: "numeric",
                    year: "numeric",
                  })}
                </div>
                <h3>{meeting.title}</h3>
                <p>{meeting.studyTopic}</p>
              </div>
              <ChevronRight size={18} />
            </Link>
          ))}
        </div>
      </section>
      {editing && (
        <Modal
          title={editing === "new" ? "Plan a gathering" : "Edit gathering"}
          onClose={() => setEditing(null)}
        >
          <MeetingForm
            meeting={editing === "new" ? undefined : editing}
            onDone={() => setEditing(null)}
          />
        </Modal>
      )}
      {sharing && (
        <Modal title="Guest invitation" onClose={() => setSharing(null)}>
          <GuestInvitationShare
            meeting={sharing}
            organizationSlug={data.organization.slug}
          />
        </Modal>
      )}
    </div>
  );
}
