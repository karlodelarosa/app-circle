import {
  CalendarDays,
  ChevronRight,
  CircleUserRound,
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
  const base = "";
  const next = data.meetings.find(
    (m) => m.status === "scheduled" && new Date(m.meetingDate) >= new Date(),
  );
  const my =
    next && data.currentUser.personId
      ? next.rsvps[data.currentUser.personId]
      : undefined;
  return (
    <div>
      <section className="relative flex min-h-[22rem] flex-col justify-end overflow-hidden rounded-[2rem] p-7 text-paper sm:min-h-[26rem] sm:p-10">
        <img
          src="/assets/devotional-table.webp"
          alt=""
          className="absolute inset-0 h-full w-full object-cover"
        />
        <div className="absolute inset-0 bg-ink/60" />
        <p className="relative text-sm text-paper/75">
          Welcome back, {data.currentUser.fullName.split(" ")[0]}
        </p>
        <h1 className="relative mt-3 max-w-2xl font-display text-5xl leading-[1.02] sm:text-7xl">
          Make room for one another.
        </h1>
        <p className="relative mt-5 max-w-xl leading-7 text-paper/85">
          Your gatherings, Circles, and community stories are gathered
          here—without turning participation into another dashboard.
        </p>
      </section>
      <div className="mt-8 grid gap-6 lg:grid-cols-[1.35fr_.65fr]">
        <section>
          {next ? (
            <article className="paper-panel overflow-hidden">
              <div className="border-b border-line bg-[#EFEBDF] p-6 sm:p-8">
                <p className="text-xs text-olive">Our next gathering</p>
                <h2 className="mt-2 font-display text-4xl">{next.title}</h2>
                <p className="mt-3 text-sm text-muted">
                  {formatDate(next.meetingDate)} at{" "}
                  {formatTime(next.meetingDate)} · {next.location}
                </p>
              </div>
              <div className="p-6 sm:p-8">
                <p className="leading-7 text-muted">
                  {next.summary || next.notes}
                </p>
                {data.currentUser.personId ? (
                  <div className="mt-6 flex flex-wrap gap-2">
                    {choices.map((c) => (
                      <button
                        key={c.value}
                        onClick={() => void setRsvp(next.id, c.value)}
                        aria-pressed={my === c.value}
                        className={`rsvp-button ${my === c.value ? "rsvp-button-active" : ""}`}
                      >
                        {c.label}
                      </button>
                    ))}
                  </div>
                ) : (
                  <p className="mt-5 rounded-xl bg-parchment p-4 text-sm text-muted">
                    Your login is not linked to a SheepCount People record. Ask
                    your administrator to link it before RSVPing.
                  </p>
                )}
                <Link
                  className="text-link mt-6"
                  to={`${base}/gatherings/${next.id}`}
                >
                  View gathering <ChevronRight size={15} />
                </Link>
              </div>
            </article>
          ) : (
            <div className="empty-state paper-panel">
              <CalendarDays />
              <h2>No gathering planned</h2>
            </div>
          )}
        </section>
        <aside className="space-y-5">
          <Link to={`${base}/circles`} className="quick-action">
            <span className="quick-icon">
              <CircleUserRound />
            </span>
            <span>
              <strong>My Circles</strong>
              <small>
                {data.groups.length} connected{" "}
                {data.groups.length === 1 ? "Circle" : "Circles"}
              </small>
            </span>
            <ChevronRight className="ml-auto text-muted" size={18} />
          </Link>
          {data.announcements.slice(0, 2).map((a) => (
            <article key={a.id} className="paper-panel p-5">
              <Megaphone size={17} className="text-olive" />
              <h2 className="mt-4 font-display text-2xl">{a.title}</h2>
              <p className="mt-2 text-sm leading-6 text-muted">{a.body}</p>
            </article>
          ))}
        </aside>
      </div>
      {data.testimonies.length > 0 && (
        <section className="mt-12">
          <div className="section-heading">
            <div>
              <h2>Recent testimonies</h2>
              <p>Stories published by your community.</p>
            </div>
          </div>
          <div className="grid gap-5 sm:grid-cols-2">
            {data.testimonies.map((t) => (
              <article className="paper-panel p-6" key={t.id}>
                <Quote className="text-sage" />
                <h3 className="mt-5 font-display text-3xl">{t.title}</h3>
                <p className="mt-3 line-clamp-3 text-sm leading-6 text-muted">
                  {t.body}
                </p>
                <p className="mt-5 text-xs text-olive">{t.authorName}</p>
              </article>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}
