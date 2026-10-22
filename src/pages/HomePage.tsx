import {
  CalendarDays,
  ChevronRight,
  CircleUserRound,
  ExternalLink,
  HeartHandshake,
  Images,
  Megaphone,
  Quote,
} from "lucide-react";
import { Link } from "react-router-dom";
import { useCircles } from "../AppContext";
import { formatDate, formatTime } from "../lib/format";
import type { RsvpStatus } from "../types";

const choices: { value: RsvpStatus; label: string }[] = [
  { value: "attending", label: "I’m going" },
  { value: "tentative", label: "Maybe" },
  { value: "declined", label: "Can’t go" },
];

export function HomePage() {
  const { data, setRsvp } = useCircles();
  if (!data) return null;
  const canLead =
    data.currentUser.role === "admin" || data.group?.role === "leader";
  const next = data.meetings
    .filter(
      (meeting) =>
        meeting.status === "scheduled" &&
        new Date(meeting.meetingDate) >= new Date(),
    )
    .sort((a, b) => a.meetingDate.localeCompare(b.meetingDate))[0];
  const my =
    next && data.currentUser.personId
      ? next.rsvps[data.currentUser.personId]
      : undefined;
  const latestAnnouncement = data.announcements[0];
  const latestGallery = data.galleries[0];
  const latestTestimony = data.testimonies[0];

  return (
    <div>
      <header className="flex flex-col gap-5 border-b border-line pb-7 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-sm text-olive">Welcome back</p>
          <h1 className="mt-1 font-display text-5xl leading-none sm:text-6xl">
            {data.currentUser.fullName.split(" ")[0]}
          </h1>
          <p className="mt-3 max-w-xl text-sm leading-6 text-muted">
            Here’s what is happening in your community and where you can take
            part next.
          </p>
        </div>
        {data.currentUser.role === "admin" && (
          <a
            href={`/${encodeURIComponent(data.organization.slug)}?browse=1`}
            target="_blank"
            rel="noreferrer"
            className="secondary-button"
          >
            <ExternalLink size={16} /> View public page
          </a>
        )}
      </header>

      <section className="py-9">
        <div className="section-heading">
          <div>
            <h2>Community updates</h2>
            <p>The latest word for your Circle this week.</p>
          </div>
        </div>
        <div className="grid gap-5 lg:grid-cols-[1.35fr_.65fr]">
          {latestAnnouncement ? (
            <article className="border-l-2 border-olive py-3 pl-5 sm:pl-8">
              <div className="flex items-center gap-2 text-sm text-olive">
                <Megaphone size={16} /> Latest announcement
              </div>
              <h3 className="mt-4 max-w-3xl font-display text-4xl leading-tight sm:text-5xl">
                {latestAnnouncement.title}
              </h3>
              <p className="mt-4 max-w-2xl whitespace-pre-line leading-7 text-muted">
                {latestAnnouncement.body}
              </p>
              <p className="mt-5 text-xs text-muted">
                Shared {formatDate(latestAnnouncement.publishedAt)}
              </p>
            </article>
          ) : (
            <div className="border-l-2 border-sage py-3 pl-5 sm:pl-8">
              <h3 className="font-display text-3xl">No new announcements</h3>
              <p className="mt-2 max-w-xl text-sm leading-6 text-muted">
                Important community notes will appear here when they are
                published.
              </p>
              {canLead && (
                <Link className="text-link mt-4" to="/content">
                  Publish an update <ChevronRight size={15} />
                </Link>
              )}
            </div>
          )}
          {canLead && data.connectionAttentionCount > 0 ? (
            <Link
              to="/connections"
              className="flex min-h-44 flex-col justify-between rounded-3xl bg-olive p-6 text-paper"
            >
              <HeartHandshake />
              <div>
                <strong className="font-display text-3xl font-normal">
                  {data.connectionAttentionCount} guest
                  {data.connectionAttentionCount === 1 ? "" : "s"} waiting
                </strong>
                <span className="mt-3 flex items-center justify-between text-sm text-paper/75">
                  Continue their welcome <ChevronRight size={16} />
                </span>
              </div>
            </Link>
          ) : (
            <Link to="/circles" className="quick-action min-h-32">
              <span className="quick-icon">
                <CircleUserRound />
              </span>
              <span>
                <strong>Your Circles</strong>
                <small>
                  {data.groups.length} connected {data.groups.length === 1 ? "Circle" : "Circles"}
                </small>
              </span>
              <ChevronRight className="ml-auto text-muted" size={18} />
            </Link>
          )}
        </div>
      </section>

      <section className="border-t border-line py-10">
        <div className="section-heading">
          <div>
            <h2>Next gathering</h2>
            <p>Your next opportunity to show up and share life together.</p>
          </div>
        </div>
        {next ? (
          <article className="overflow-hidden rounded-[2rem] border border-line bg-paper">
            <div
              className={`relative flex min-h-64 flex-col justify-end overflow-hidden p-6 sm:min-h-80 sm:p-9 ${next.coverUrl ? "text-paper" : "bg-[#EFEBDF]"}`}
            >
              {next.coverUrl && (
                <>
                  <img
                    src={next.coverUrl}
                    alt=""
                    className="absolute inset-0 h-full w-full object-cover"
                  />
                  <div className="absolute inset-0 bg-gradient-to-t from-ink/90 via-ink/50 to-transparent" />
                </>
              )}
              <p className={`relative text-sm ${next.coverUrl ? "text-paper/80" : "text-olive"}`}>
                {formatDate(next.meetingDate)} at {formatTime(next.meetingDate)}
              </p>
              <h3 className="relative mt-2 max-w-4xl font-display text-4xl leading-tight sm:text-6xl">
                {next.title}
              </h3>
              <p className={`relative mt-3 text-sm ${next.coverUrl ? "text-paper/80" : "text-muted"}`}>
                {next.location}
              </p>
            </div>
            <div className="grid gap-6 p-6 sm:p-8 lg:grid-cols-[1fr_auto] lg:items-end">
              <div>
                <p className="max-w-2xl leading-7 text-muted">
                  {next.summary || next.notes}
                </p>
                {data.currentUser.personId ? (
                  <div className="mt-5 flex flex-wrap gap-2">
                    {choices.map((choice) => (
                      <button
                        key={choice.value}
                        onClick={() => void setRsvp(next.id, choice.value)}
                        aria-pressed={my === choice.value}
                        className={`rsvp-button ${my === choice.value ? "rsvp-button-active" : ""}`}
                      >
                        {choice.label}
                      </button>
                    ))}
                  </div>
                ) : (
                  <p className="mt-5 rounded-xl bg-parchment p-4 text-sm text-muted">
                    Your login is not linked to a SheepCount People record. Ask
                    your administrator to link it before RSVPing.
                  </p>
                )}
              </div>
              <Link className="primary-button" to={`/gatherings/${next.id}`}>
                View gathering <ChevronRight size={15} />
              </Link>
            </div>
          </article>
        ) : (
          <div className="empty-state border-y border-line">
            <CalendarDays />
            <h3>No gathering planned</h3>
            <p>
              {canLead
                ? "Plan the next time your community will gather."
                : "Your leader will share the next gathering here."}
            </p>
            {canLead && <Link className="primary-button" to="/gatherings">Plan a gathering</Link>}
          </div>
        )}
      </section>

      <section className="border-t border-line py-10">
        <div className="section-heading">
          <div>
            <h2>Community life</h2>
            <p>Photographs and stories from life together.</p>
          </div>
        </div>
        {latestGallery || latestTestimony ? (
          <div className="grid gap-6 lg:grid-cols-[1.2fr_.8fr]">
            {latestGallery && (
              <a
                href={`/${data.organization.slug}/galleries/${latestGallery.slug}?browse=1`}
                target="_blank"
                rel="noreferrer"
                className="group relative min-h-72 overflow-hidden rounded-[2rem]"
              >
                <img
                  src={latestGallery.coverUrl || "/assets/devotional-table.webp"}
                  alt=""
                  className="absolute inset-0 h-full w-full object-cover"
                />
                <div className="absolute inset-0 bg-gradient-to-t from-ink/85 via-ink/25 to-transparent" />
                <div className="absolute inset-x-0 bottom-0 p-7 text-paper">
                  <Images size={19} />
                  <h3 className="mt-3 font-display text-4xl">{latestGallery.title}</h3>
                  <p className="mt-2 text-sm text-paper/75">{latestGallery.description}</p>
                </div>
              </a>
            )}
            {latestTestimony && (
              <article className="flex min-h-72 flex-col justify-between border-l-2 border-sage px-6 py-5">
                <Quote className="text-olive" />
                <div>
                  <h3 className="font-display text-3xl leading-tight">{latestTestimony.title}</h3>
                  <p className="mt-3 line-clamp-4 text-sm leading-6 text-muted">{latestTestimony.body}</p>
                  <p className="mt-5 text-xs text-olive">{latestTestimony.authorName}</p>
                </div>
              </article>
            )}
          </div>
        ) : (
          <div className="border-y border-line py-8 text-sm text-muted">
            Published photographs and testimonies will gather here over time.
          </div>
        )}
      </section>

      <section className="border-t border-line py-10">
        <Link to="/circles" className="quick-action">
          <span className="quick-icon"><CircleUserRound /></span>
          <span>
            <strong>Explore your Circles</strong>
            <small>People, places, and gatherings for each Circle</small>
          </span>
          <ChevronRight className="ml-auto text-muted" size={18} />
        </Link>
      </section>
    </div>
  );
}
