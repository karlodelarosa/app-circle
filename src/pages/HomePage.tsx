import { CalendarDays, ChevronRight, Clock3, Heart, MapPin } from "lucide-react";
import { Link } from "react-router-dom";
import { useCircles } from "../AppContext";
import { CommunityFeed } from "../components/CommunityFeed";
import { formatDate, formatTime } from "../lib/format";
import { gatheringLifecycle } from "../lib/gatheringLifecycle";

export function HomePage() {
  const { data } = useCircles();
  if (!data) return null;

  const meetings = data.dashboard?.meetings ?? data.accessibleMeetings ?? data.meetings;
  const prayers = data.dashboard?.prayers ?? data.prayers;
  const upcoming = meetings
    .filter((meeting) => ["upcoming", "live"].includes(gatheringLifecycle(meeting)))
    .sort((a, b) => a.meetingDate.localeCompare(b.meetingDate))
    .slice(0, 3);
  const activePrayers = prayers.filter((prayer) => !prayer.isAnswered).slice(0, 3);

  return (
    <div className="grid gap-8 xl:grid-cols-[minmax(0,1fr)_20rem] xl:items-start">
      <div className="min-w-0">
        <CommunityFeed />
      </div>

      <aside className="space-y-6 xl:sticky xl:top-24" aria-label="Community summaries">
        <section className="paper-panel overflow-hidden" aria-labelledby="upcoming-events-title">
          <div className="flex items-center justify-between border-b border-line p-5">
            <div>
              <p className="page-kicker">What’s ahead</p>
              <h2 id="upcoming-events-title" className="mt-2 font-display text-2xl">Upcoming events</h2>
            </div>
            <CalendarDays size={19} className="text-olive" aria-hidden="true" />
          </div>
          {upcoming.length ? (
            <div className="divide-y divide-line px-5">
              {upcoming.map((meeting) => (
                <article key={meeting.id} className="py-4">
                  <p className="text-xs font-medium text-olive">{formatDate(meeting.meetingDate, { weekday: "short", month: "short", day: "numeric" })}</p>
                  <h3 className="mt-1 font-display text-xl leading-tight"><Link className="hover:text-olive" to={`/gatherings/${meeting.id}`}>{meeting.title}</Link></h3>
                  <p className="mt-2 flex items-center gap-1.5 text-xs text-muted"><Clock3 size={13} /> {formatTime(meeting.meetingDate)}</p>
                  <p className="mt-1 flex items-center gap-1.5 text-xs text-muted"><MapPin size={13} /> {meeting.location}</p>
                </article>
              ))}
            </div>
          ) : <p className="p-5 text-sm text-muted">No upcoming gatherings yet.</p>}
          <Link className="flex items-center justify-between border-t border-line p-5 text-sm font-medium text-olive hover:bg-parchment" to="/gatherings">View all gatherings <ChevronRight size={15} /></Link>
        </section>

        <section className="paper-panel overflow-hidden" aria-labelledby="prayer-requests-title">
          <div className="flex items-center justify-between border-b border-line p-5">
            <div>
              <p className="page-kicker">Care</p>
              <h2 id="prayer-requests-title" className="mt-2 font-display text-2xl">Prayer requests</h2>
            </div>
            <Heart size={19} className="text-olive" aria-hidden="true" />
          </div>
          {activePrayers.length ? (
            <div className="divide-y divide-line px-5">
              {activePrayers.map((prayer) => (
                <article key={prayer.id} className="py-4">
                  <p className="text-xs font-medium text-olive">{prayer.destinationName}</p>
                  <h3 className="mt-1 font-display text-xl leading-tight">{prayer.title}</h3>
                  <p className="mt-2 line-clamp-2 text-xs leading-5 text-muted">{prayer.description}</p>
                  <p className="mt-2 text-xs text-muted">{prayer.prayerCount} praying</p>
                </article>
              ))}
            </div>
          ) : <p className="p-5 text-sm text-muted">No active prayer requests.</p>}
          <Link className="flex items-center justify-between border-t border-line p-5 text-sm font-medium text-olive hover:bg-parchment" to="/prayer">Open prayer board <ChevronRight size={15} /></Link>
        </section>
      </aside>
    </div>
  );
}
