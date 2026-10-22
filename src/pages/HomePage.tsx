import {
  ChevronRight,
  Clock3,
  ExternalLink,
  Heart,
  Images,
  MapPin,
  Users,
} from "lucide-react";
import { Link } from "react-router-dom";
import { useCircles } from "../AppContext";
import { Avatar } from "../components/Avatar";
import { DashboardJumbotron } from "../components/DashboardJumbotron";
import { formatDate, formatTime } from "../lib/format";

const dayGreeting = () => {
  const hour = new Date().getHours();
  if (hour < 12) return "Good morning";
  if (hour < 18) return "Good afternoon";
  return "Good evening";
};

export function HomePage() {
  const { data } = useCircles();
  if (!data) return null;

  const upcoming = data.meetings
    .filter(
      (meeting) =>
        meeting.status === "scheduled" &&
        new Date(meeting.meetingDate) >= new Date(),
    )
    .sort((a, b) => a.meetingDate.localeCompare(b.meetingDate));
  const next = upcoming[0];
  const prayers = data.prayers.filter((prayer) => !prayer.isAnswered).slice(0, 3);
  const announcement = data.announcements[0];
  const gallery = data.galleries[0];
  const circleCover = data.publicCircleListings.find(
    (listing) => listing.groupId === data.group?.id,
  )?.coverUrl;
  const defaultHeroImage = circleCover || "/assets/devotional-table.webp";
  const attending = next
    ? Object.entries(next.rsvps)
        .filter(([, status]) => status === "attending")
        .map(([id]) => data.members.find((member) => member.id === id))
        .filter((member) => member !== undefined)
    : [];
  const visibleAttendees = attending.slice(0, 4);
  const additionalAttendees = Math.max(attending.length - visibleAttendees.length, 0);

  return (
    <div>
      <header className="flex flex-col gap-5 border-b border-line pb-7 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-xs uppercase tracking-[0.14em] text-olive">
            {new Intl.DateTimeFormat(undefined, {
              weekday: "long",
              month: "long",
              day: "numeric",
            }).format(new Date())}
          </p>
          <h1 className="mt-2 font-display text-5xl leading-none sm:text-6xl">
            {dayGreeting()}, {data.currentUser.fullName.split(" ")[0]}.
          </h1>
          <p className="mt-3 text-sm text-muted">
            Here’s what is happening in {data.group?.name || "your community"}.
          </p>
        </div>
        {data.currentUser.role === "admin" && (
          <a href={`/${data.organization.slug}?browse=1`} target="_blank" rel="noreferrer" className="secondary-button">
            <ExternalLink size={16} /> View public page
          </a>
        )}
      </header>

      <section className="py-8">
        <DashboardJumbotron
          defaultImage={defaultHeroImage}
          gatherings={upcoming.slice(0, 3)}
          circleName={data.group?.name}
          circlePath={data.group ? `/circles/${data.group.id}` : "/circles"}
        />
      </section>

      <div className="grid items-start gap-5 lg:grid-cols-[minmax(0,1.8fr)_minmax(18rem,.85fr)]">
        <section className="paper-panel p-5 sm:p-7">
          <div className="flex items-center justify-between gap-4 border-b border-line pb-5">
            <div>
              <p className="text-xs uppercase tracking-[0.14em] text-olive">Up next</p>
              <h2 className="mt-2 font-display text-3xl">Following gathering</h2>
            </div>
            <Link to="/gatherings" className="text-link">All gatherings <ChevronRight size={14} /></Link>
          </div>
          {next ? (
            <div className="mt-5 grid grid-cols-[auto_minmax(0,1fr)] gap-4 sm:gap-5">
              <div className="date-block">
                <span>{formatDate(next.meetingDate, { month: "short" })}</span>
                <strong>{new Date(next.meetingDate).getDate()}</strong>
              </div>
              <div className="min-w-0">
                <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                  <div className="min-w-0">
                    <Link to={`/gatherings/${next.id}`} className="hover:text-olive focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-olive">
                      <h3 className="font-display text-2xl sm:text-3xl">{next.title}</h3>
                    </Link>
                    <p className="mt-1 text-sm text-muted">{data.group?.name}</p>
                    {next.studyTopic && (
                      <p className="mt-2 font-display text-lg text-olive">{next.studyTopic}</p>
                    )}
                  </div>
                  {attending.length ? (
                    <div
                      className="flex shrink-0 -space-x-2"
                      aria-label={`${attending.map((member) => member.fullName).join(", ")} going`}
                    >
                      {visibleAttendees.map((member) => <Avatar key={member.id} person={member} />)}
                      {additionalAttendees > 0 && (
                        <span aria-hidden="true" className="inline-flex h-9 w-9 items-center justify-center rounded-full bg-olive text-xs font-semibold text-paper ring-2 ring-paper">
                          +{additionalAttendees}
                        </span>
                      )}
                    </div>
                  ) : (
                    <p className="shrink-0 text-xs text-muted">No one confirmed yet</p>
                  )}
                </div>
                <div className="mt-4 flex flex-wrap gap-x-5 gap-y-2 text-xs text-muted">
                  <span className="inline-flex items-center gap-1.5"><Clock3 size={14} />{formatTime(next.meetingDate)}</span>
                  <span className="inline-flex items-center gap-1.5"><MapPin size={14} />{next.location}</span>
                  <span className="inline-flex items-center gap-1.5"><Users size={14} />{attending.length} going</span>
                </div>
                <Link to={`/gatherings/${next.id}`} className="text-link mt-5">
                  View gathering <ChevronRight size={14} />
                </Link>
              </div>
            </div>
          ) : (
            <div className="py-8 text-sm text-muted">There is no gathering scheduled yet. <Link className="text-link ml-1" to="/gatherings">Plan or view gatherings</Link></div>
          )}
        </section>

        <aside className="paper-panel overflow-hidden lg:col-start-2 lg:row-start-1 lg:row-span-3">
          <div className="flex items-center justify-between border-b border-line p-6">
            <div>
              <p className="text-xs uppercase tracking-[0.14em] text-olive">Care</p>
              <h2 className="mt-2 font-display text-3xl">Prayer requests</h2>
            </div>
            <Link to="/prayer" className="text-link">View all <ChevronRight size={14} /></Link>
          </div>
          <div className="divide-y divide-line px-6">
            {prayers.length ? prayers.map((prayer) => (
              <Link key={prayer.id} to="/prayer" className="flex gap-4 py-5">
                <span className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-sage text-olive"><Heart size={17} /></span>
                <span className="min-w-0">
                  <strong className="block text-sm font-medium">{prayer.title}</strong>
                  <small className="mt-1 block text-xs text-muted">{prayer.prayerCount} {prayer.prayerCount === 1 ? "person is" : "people are"} praying</small>
                </span>
              </Link>
            )) : <p className="py-8 text-sm text-muted">No open requests right now.</p>}
          </div>
        </aside>

        <section className="paper-panel p-6 sm:p-8 lg:col-start-1">
          <div className="flex items-center justify-between">
            <p className="text-xs uppercase tracking-[0.14em] text-olive">Latest announcement</p>
            <span className="role-label">Members</span>
          </div>
          {announcement ? (
            <>
              <h2 className="mt-5 font-display text-4xl">{announcement.title}</h2>
              <p className="mt-5 max-w-2xl whitespace-pre-line leading-7 text-muted">{announcement.body}</p>
              <p className="mt-6 text-xs text-muted">Shared {formatDate(announcement.publishedAt)}</p>
            </>
          ) : (
            <div className="py-8"><h2 className="font-display text-3xl">No current announcement</h2><p className="mt-2 text-sm text-muted">Your next community update will appear here.</p></div>
          )}
        </section>

        {gallery ? (
          <a href={`/${data.organization.slug}/galleries/${gallery.slug}?browse=1`} target="_blank" rel="noreferrer" className="group relative flex min-h-72 overflow-hidden rounded-[2rem] text-paper lg:col-start-1">
            <img src={gallery.coverUrl || "/assets/devotional-table.webp"} alt="" className="absolute inset-0 h-full w-full object-cover" />
            <div className="absolute inset-0 bg-gradient-to-t from-ink/90 via-ink/20 to-transparent" />
            <div className="relative mt-auto p-6 sm:p-8">
              <span className="flex items-center gap-2 text-xs text-paper/75"><Images size={15} />From the gallery</span>
              <h2 className="mt-3 font-display text-4xl">{gallery.title}</h2>
              <p className="mt-3 text-sm text-paper/75">View {gallery.photos.length} {gallery.photos.length === 1 ? "photo" : "photos"}</p>
            </div>
          </a>
        ) : (
          <div className="border-y border-line py-8 text-sm text-muted lg:col-start-1">Published community photographs will gather here over time.</div>
        )}
      </div>
    </div>
  );
}
