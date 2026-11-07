import { ChevronRight, Clock3, ExternalLink, Heart, Images, MapPin, Users } from "lucide-react";
import { useState } from "react";
import { Link } from "react-router-dom";
import { useCircles } from "../AppContext";
import { Avatar } from "../components/Avatar";
import { DashboardJumbotron } from "../components/DashboardJumbotron";
import { formatDate, formatTime } from "../lib/format";
import { gatheringLifecycle } from "../lib/gatheringLifecycle";
import type { Meeting } from "../types";

type EventFilter = "both" | "organization" | "circles";

const dayGreeting = () => {
  const hour = new Date().getHours();
  if (hour < 12) return "Good morning";
  if (hour < 18) return "Good afternoon";
  return "Good evening";
};

const matchesFilter = (meeting: Meeting, filter: EventFilter) => {
  if (filter === "organization") return meeting.scope === "organization";
  if (filter === "circles") return meeting.scope !== "organization";
  return true;
};

export function HomePage() {
  const { data } = useCircles();
  const [eventFilter, setEventFilter] = useState<EventFilter>("both");
  const [showAllEvents, setShowAllEvents] = useState(false);
  if (!data) return null;

  const dashboardMeetings = data.dashboard?.meetings ?? data.accessibleMeetings ?? data.meetings;
  const dashboardPrayers = data.dashboard?.prayers ?? data.prayers;
  const dashboardAnnouncements = data.dashboard?.announcements ?? data.announcements;
  const dashboardMembers = data.organizationMembers ?? data.members;
  const upcoming = dashboardMeetings
    .filter((meeting) => ["upcoming", "live"].includes(gatheringLifecycle(meeting)))
    .sort((a, b) => a.meetingDate.localeCompare(b.meetingDate));
  const filteredEvents = upcoming.filter((meeting) => matchesFilter(meeting, eventFilter));
  const visibleEvents = showAllEvents ? filteredEvents : filteredEvents.slice(0, 5);
  const prayers = dashboardPrayers.filter((prayer) => !prayer.isAnswered).slice(0, 3);
  const announcement = dashboardAnnouncements[0];
  const highlights = (data.dashboard?.highlights ?? data.galleries.filter((gallery) => gallery.isOrganizationHighlight))
    .slice()
    .sort((a, b) => (b.highlightedAt ?? b.publishedAt).localeCompare(a.highlightedAt ?? a.publishedAt))
    .slice(0, 3);
  const defaultHeroImage = data.organization.imageUrl || "/assets/devotional-table.webp";
  const emptyEventMessage = eventFilter === "organization"
    ? "There are no organization events scheduled yet."
    : eventFilter === "circles"
      ? "There are no Circle events scheduled yet."
      : "There are no upcoming events scheduled yet.";

  return (
    <div>
      <header className="flex flex-col gap-4 border-b border-line pb-5 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-xs uppercase tracking-[0.14em] text-olive">
            {new Intl.DateTimeFormat(undefined, { weekday: "long", month: "long", day: "numeric" }).format(new Date())}
          </p>
          <h1 className="mt-2 font-display text-5xl leading-none sm:text-[3.25rem]">
            {dayGreeting()}, {data.currentUser.fullName.split(" ")[0]}.
          </h1>
          <p className="mt-3 text-sm text-muted">Here’s what is happening across {data.organization.name}.</p>
        </div>
        {data.currentUser.role === "admin" && (
          <a href={`/${data.organization.slug}?browse=1`} target="_blank" rel="noreferrer" className="secondary-button">
            <ExternalLink size={16} /> View public page
          </a>
        )}
      </header>

      <section className="py-6">
        <DashboardJumbotron
          defaultImage={defaultHeroImage}
          welcomeImage="/assets/welcome-table.webp"
          gatherings={upcoming.slice(0, 3)}
          circleName={data.organization.name}
          circlePath="/circles"
          ctaLabel="View all Circles"
        />
      </section>

      {announcement && (
        <section className="paper-panel mb-6 p-6 sm:p-8" aria-labelledby="dashboard-announcement-title">
          <div className="flex items-center justify-between gap-4">
            <p className="text-xs uppercase tracking-[0.14em] text-olive">Latest announcement</p>
            <span className="role-label">{announcement.destinationName || "Members"}</span>
          </div>
          <h2 id="dashboard-announcement-title" className="mt-5 font-display text-4xl">{announcement.title}</h2>
          <p className="mt-4 max-w-3xl whitespace-pre-line leading-7 text-muted">{announcement.body}</p>
          <p className="mt-5 text-xs text-muted">Shared {formatDate(announcement.publishedAt)}</p>
        </section>
      )}

      <section className="paper-panel p-5 sm:p-7" aria-labelledby="upcoming-events-title" aria-label="Upcoming events">
        <div className="flex flex-col gap-5 border-b border-line pb-5 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <p className="text-xs uppercase tracking-[0.14em] text-olive">What’s ahead</p>
            <h2 id="upcoming-events-title" className="mt-2 font-display text-3xl">Upcoming events</h2>
          </div>
          <fieldset>
            <legend className="sr-only">Filter upcoming events</legend>
            <div className="inline-flex rounded-xl border border-line bg-parchment p-1">
              {([[
                "both", "Both",
              ], [
                "organization", "Organization",
              ], [
                "circles", "Circles",
              ]] as const).map(([value, label]) => (
                <label key={value} className={`cursor-pointer rounded-lg px-3 py-2 text-xs font-medium transition-colors ${eventFilter === value ? "bg-olive text-paper" : "text-muted hover:text-ink"}`}>
                  <input
                    className="sr-only"
                    type="radio"
                    name="event-filter"
                    value={value}
                    checked={eventFilter === value}
                    onChange={() => {
                      setEventFilter(value);
                      setShowAllEvents(false);
                    }}
                  />
                  {label}
                </label>
              ))}
            </div>
          </fieldset>
        </div>

        {visibleEvents.length ? (
          <div className="divide-y divide-line">
            {visibleEvents.map((meeting) => {
              const attending = Object.entries(meeting.rsvps)
                .filter(([, status]) => status === "attending")
                .map(([id]) => dashboardMembers.find((member) => member.id === id))
                .filter((member) => member !== undefined);
              const guestCount = meeting.guestRsvpCounts?.attending ?? 0;
              const confirmedCount = attending.length + guestCount;
              const visibleAttendees = attending.slice(0, 4);
              const extraAttendees = Math.max(attending.length - visibleAttendees.length, 0);
              return (
                <article key={meeting.id} className="grid grid-cols-[auto_minmax(0,1fr)] gap-4 py-5 sm:gap-5">
                  <time className="dashboard-date-block" dateTime={meeting.meetingDate} aria-label={formatDate(meeting.meetingDate)}>
                    <span>{formatDate(meeting.meetingDate, { month: "short" })}</span>
                    <strong>{new Date(meeting.meetingDate).getDate()}</strong>
                    <small>{formatDate(meeting.meetingDate, { weekday: "short" })}</small>
                  </time>
                  <div className="min-w-0">
                    <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                      <div className="min-w-0">
                        <div className="flex flex-wrap items-center gap-2">
                          <Link to={`/gatherings/${meeting.id}`} className="hover:text-olive focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-olive">
                            <h3 className="font-display text-2xl sm:text-3xl">{meeting.title}</h3>
                          </Link>
                          {gatheringLifecycle(meeting) === "live" && <span className="status-badge">Happening now</span>}
                        </div>
                        <p className="mt-1 text-xs text-muted">{meeting.destinationName || (meeting.scope === "organization" ? "Everyone" : "Circle gathering")}</p>
                      </div>
                      {attending.length ? (
                        <div className="flex shrink-0 -space-x-2" aria-label={`${attending.map((member) => member.fullName).join(", ")} going`}>
                          {visibleAttendees.map((member) => <Avatar key={member.id} person={member} />)}
                          {extraAttendees > 0 && <span aria-hidden="true" className="inline-flex h-9 w-9 items-center justify-center rounded-full bg-olive text-xs font-semibold text-paper ring-2 ring-paper">+{extraAttendees}</span>}
                        </div>
                      ) : guestCount ? (
                        <p className="shrink-0 text-xs text-muted">{guestCount} {guestCount === 1 ? "guest" : "guests"} confirmed</p>
                      ) : (
                        <p className="shrink-0 text-xs text-muted">No one confirmed yet</p>
                      )}
                    </div>
                    <div className="mt-3 flex flex-wrap gap-x-5 gap-y-2 text-xs text-muted">
                      <span className="inline-flex items-center gap-1.5"><Clock3 size={14} />{formatTime(meeting.meetingDate)}–{formatTime(meeting.endsAt)}</span>
                      <span className="inline-flex items-center gap-1.5"><MapPin size={14} />{meeting.location}</span>
                      <span className="inline-flex items-center gap-1.5"><Users size={14} />{confirmedCount} going</span>
                    </div>
                    <Link to={`/gatherings/${meeting.id}`} className="text-link mt-4">View event <ChevronRight size={14} /></Link>
                  </div>
                </article>
              );
            })}
          </div>
        ) : (
          <div className="py-10 text-center" role="status">
            <p className="text-sm text-muted">{emptyEventMessage}</p>
            <Link className="text-link mt-3" to="/gatherings">View gatherings <ChevronRight size={14} /></Link>
          </div>
        )}
        {filteredEvents.length > 5 && (
          <div className="border-t border-line pt-5 text-center">
            <button type="button" className="secondary-button" onClick={() => setShowAllEvents((current) => !current)}>
              {showAllEvents ? "Show less" : "Show more"}
            </button>
          </div>
        )}
      </section>

      {highlights.length > 0 && (
        <section className="mt-8" aria-labelledby="circle-highlights-title" aria-label="Recently in our Circles">
          <div className="section-heading">
            <div>
              <p className="text-xs uppercase tracking-[0.14em] text-olive">Shared life</p>
              <h2 id="circle-highlights-title" className="mt-2">Recently in our Circles</h2>
              <p>Stories and photographs shared across the organization.</p>
            </div>
          </div>
          <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">
            {highlights.map((gallery) => (
              <article key={gallery.id} className="paper-panel overflow-hidden">
                <a href={`/${data.organization.slug}/galleries/${gallery.slug}?browse=1`} target="_blank" rel="noreferrer" className="group block h-full">
                  <img src={gallery.coverUrl || "/assets/devotional-table.webp"} alt="" className="aspect-[4/3] w-full object-cover" />
                  <div className="p-5">
                    <p className="text-xs font-medium text-olive">{gallery.destinationName || "Circle highlight"}</p>
                    <h3 className="mt-2 font-display text-3xl leading-tight group-hover:text-olive">{gallery.title}</h3>
                    <p className="mt-3 line-clamp-3 text-sm leading-6 text-muted">{gallery.description}</p>
                    <p className="mt-4 flex items-center gap-2 text-xs text-muted"><Images size={14} />{gallery.photos.length} {gallery.photos.length === 1 ? "photo" : "photos"} · {formatDate(gallery.highlightedAt ?? gallery.publishedAt, { month: "short", day: "numeric" })}</p>
                  </div>
                </a>
              </article>
            ))}
          </div>
        </section>
      )}

      <section className="paper-panel mt-8 overflow-hidden" aria-labelledby="prayer-requests-title">
        <div className="flex items-center justify-between border-b border-line p-6">
          <div>
            <p className="text-xs uppercase tracking-[0.14em] text-olive">Care</p>
            <h2 id="prayer-requests-title" className="mt-2 font-display text-3xl">Prayer requests</h2>
          </div>
          <Link to="/prayer" className="text-link">View all <ChevronRight size={14} /></Link>
        </div>
        <div className="divide-y divide-line px-6">
          {prayers.length ? prayers.map((prayer) => (
            <Link key={prayer.id} to="/prayer" className="flex gap-4 py-5">
              <span className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-sage text-olive"><Heart size={17} /></span>
              <span className="min-w-0">
                <strong className="block text-sm font-medium">{prayer.title}</strong>
                <small className="mt-1 block text-xs text-muted">{prayer.destinationName ? `${prayer.destinationName} · ` : ""}{prayer.prayerCount} {prayer.prayerCount === 1 ? "person is" : "people are"} praying</small>
              </span>
            </Link>
          )) : <p className="py-8 text-sm text-muted">No open requests right now.</p>}
        </div>
      </section>
    </div>
  );
}
