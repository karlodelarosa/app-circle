import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  type FormEvent,
  type ReactNode,
} from "react";
import {
  ArrowLeft,
  CalendarDays,
  ChevronRight,
  Copy,
  Images,
  MapPin,
  Menu,
  Megaphone,
  Share2,
  Smartphone,
  UsersRound,
  X,
} from "lucide-react";
import {
  Link,
  NavLink,
  useLocation,
  useParams,
  useSearchParams,
} from "react-router-dom";
import { Brand } from "../components/AppShell";
import { RouteOutlet, StandaloneRouteBar } from "../components/RouteExperience";
import { Turnstile } from "../components/Turnstile";
import { useStandalone } from "../hooks/useStandalone";
import { formatDate, formatTime } from "../lib/format";
import {
  formatGatheringDateTime,
  gatheringLifecycle,
  gatheringRelativeStatus,
} from "../lib/gatheringLifecycle";
import { gatheringCoverImage } from "../lib/images";
import {
  gatheringShareUrl,
  LAST_PUBLIC_ORG_KEY,
  publicCommunityUrl,
  withBrowseMode,
} from "../lib/publicLinks";
import { copyText, shareLink } from "../lib/share";
import { supabase } from "../lib/supabase";
import {
  galleryBySlug,
  loadPublicSpace,
  loadPublicGathering,
  requestCircleConnection,
  submitGuestRsvp,
} from "../services/public";
import type { ContactPreference, PublicSpace, RsvpStatus } from "../types";

interface PublicContextValue {
  space: PublicSpace;
  browse: boolean;
  href: (path: string) => string;
}

const PublicContext = createContext<PublicContextValue | null>(null);
const usePublic = () => {
  const value = useContext(PublicContext);
  if (!value) throw new Error("Public space unavailable");
  return value;
};

interface InstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
}

function useInstallPrompt() {
  const [promptEvent, setPromptEvent] = useState<InstallPromptEvent>();
  const standalone = useStandalone();
  const isIos = /iphone|ipad|ipod/i.test(navigator.userAgent);
  useEffect(() => {
    const capture = (event: Event) => {
      event.preventDefault();
      setPromptEvent(event as InstallPromptEvent);
    };
    window.addEventListener("beforeinstallprompt", capture);
    return () => window.removeEventListener("beforeinstallprompt", capture);
  }, []);
  const install = async () => {
    if (!promptEvent) return;
    await promptEvent.prompt();
    await promptEvent.userChoice;
    setPromptEvent(undefined);
  };
  return { canInstall: Boolean(promptEvent), install, isIos, standalone };
}

export function PublicShell() {
  const { orgSlug = "ministry-lens-church" } = useParams();
  const [searchParams] = useSearchParams();
  const browse = searchParams.get("browse") === "1";
  const [space, setSpace] = useState<PublicSpace | null>(null);
  const [error, setError] = useState("");
  const [menu, setMenu] = useState(false);
  const { pathname } = useLocation();
  useEffect(() => {
    setSpace(null);
    setError("");
    void loadPublicSpace(supabase, orgSlug)
      .then((next) => {
        setSpace(next);
        localStorage.setItem(LAST_PUBLIC_ORG_KEY, next.organization.slug);
      })
      .catch((cause) =>
        setError(
          cause instanceof Error
            ? cause.message
            : "Community page unavailable.",
        ),
      );
  }, [orgSlug]);
  if (error)
    return (
      <main className="grid min-h-screen place-items-center bg-parchment p-6">
        <div className="max-w-md text-center">
          <h1 className="font-display text-4xl">
            This community page is unavailable.
          </h1>
          <p className="mt-3 text-muted">{error}</p>
        </div>
      </main>
    );
  if (!space)
    return (
      <div className="grid min-h-screen place-items-center bg-parchment">
        <div className="h-9 w-9 animate-spin rounded-full border-2 border-line border-t-olive" />
      </div>
    );
  const base = `/${orgSlug}`;
  const href = (path: string) => withBrowseMode(path, browse);
  const links = [
    ["Gatherings", `${base}/gatherings`],
    ...(space.announcements.length ? [["Updates", `${base}/updates`]] : []),
    ...(space.testimonies.length ? [["Testimonies", `${base}/testimonies`]] : []),
    ...(space.galleries.length ? [["Gallery", `${base}/galleries`]] : []),
    ...(space.circles.length ? [["Join a Circle", `${base}/circles`]] : []),
  ];
  const publicFallback = pathname.match(/\/gatherings\/[^/]+$/)
    ? `${base}/gatherings`
    : pathname.match(/\/testimonies\/[^/]+$/)
      ? `${base}/testimonies`
      : pathname.match(/\/galleries\/[^/]+$/)
        ? `${base}/galleries`
        : pathname.match(/\/circles\/[^/]+$/)
          ? `${base}/circles`
          : base;
  return (
    <PublicContext.Provider value={{ space, browse, href }}>
      <div className="min-h-screen bg-parchment text-ink">
        <div className="sticky top-0 z-40">
        {browse && (
          <div className="bg-olive text-paper">
            <div className="mx-auto flex min-h-11 max-w-7xl items-center justify-between gap-4 px-5 text-xs lg:px-10">
              <span>Public preview</span>
              <Link to="/" className="inline-flex min-h-11 items-center gap-2 font-medium">
                <ArrowLeft size={14} /> Back to dashboard
              </Link>
            </div>
          </div>
        )}
        <header className="border-b border-line/80 bg-paper/95 backdrop-blur">
          <div className="mx-auto flex h-20 max-w-7xl items-center justify-between px-5 lg:px-10">
            <Link to={href(base)}>
              <Brand />
            </Link>
            <nav
              className="hidden items-center gap-7 md:flex"
              aria-label="Public navigation"
            >
              {links.map(([label, to]) => (
                <NavLink
                  key={to}
                  to={href(to)}
                  className={({ isActive }) =>
                    `text-sm ${isActive ? "text-olive" : "text-muted hover:text-ink"}`
                  }
                >
                  {label}
                </NavLink>
              ))}
              <Link
                className="secondary-button"
                to={`/sign-in?organization=${orgSlug}`}
              >
                Sign in
              </Link>
            </nav>
            <button
              className="icon-button md:hidden"
              onClick={() => setMenu(!menu)}
              aria-label={menu ? "Close navigation" : "Open navigation"}
              aria-expanded={menu}
              aria-controls="public-mobile-navigation"
            >
              {menu ? <X /> : <Menu />}
            </button>
          </div>
          {menu && (
            <nav id="public-mobile-navigation" aria-label="Public mobile navigation" className="grid gap-1 border-t border-line p-4 md:hidden">
              {links.map(([label, to]) => (
                <Link
                  key={to}
                  to={href(to)}
                  onClick={() => setMenu(false)}
                  className="min-h-11 rounded-xl px-4 py-3 text-sm text-muted"
                >
                  {label}
                </Link>
              ))}
              <Link
                to={`/sign-in?organization=${orgSlug}`}
                className="primary-button mt-2"
              >
                Sign in
              </Link>
            </nav>
          )}
        </header>
        <StandaloneRouteBar
          homeTo={href(base)}
          homeLabel="Home"
          fallbackTo={href(publicFallback)}
          hidden={pathname === base}
        />
        </div>
        <RouteOutlet />
        <footer className="border-t border-line bg-paper">
          <div className="mx-auto flex max-w-7xl flex-col gap-5 px-5 py-10 sm:flex-row sm:items-center sm:justify-between lg:px-10">
            <Brand />
            <p className="max-w-md text-sm leading-6 text-muted">
              {space.organization.name} on Circles. Gather in person, grow in
              faith, and make room for one another.
            </p>
          </div>
        </footer>
      </div>
    </PublicContext.Provider>
  );
}

export function PublicHomePage() {
  const { space, href } = usePublic();
  const slug = space.organization.slug;
  return (
    <main>
      <section className="public-hero">
        <img
          src={space.heroImageUrl || "/assets/devotional-table.webp"}
          alt="An open Bible and warm drink prepared for community"
        />
        <div className="public-hero-wash" />
        <div className="relative mx-auto flex min-h-[34rem] max-w-7xl items-end px-5 pb-14 pt-24 sm:min-h-[38rem] lg:px-10 lg:pb-24">
          <div className="max-w-2xl">
            <p className="text-sm text-olive">
              Welcome to {space.organization.name}
            </p>
            <h1>{space.heroTitle}</h1>
            <p className="mt-6 max-w-xl text-lg leading-8 text-[#4E5046]">
              {space.introduction}
            </p>
            <div className="mt-8 grid gap-3 sm:flex sm:flex-wrap">
              <Link
                className="primary-button min-h-11 justify-center"
                to={href(`/${slug}/gatherings`)}
              >
                Find a gathering
              </Link>
              {space.circles.length > 0 && (
                <Link
                  className="secondary-button min-h-11 justify-center"
                  to={href(`/${slug}/circles`)}
                >
                  Join a Circle
                </Link>
              )}
              <Link
                className="secondary-button min-h-11 justify-center"
                to={`/${slug}/cell-group-signup`}
              >
                Sign up for a Cell Group
              </Link>
            </div>
          </div>
        </div>
      </section>
      {space.announcements[0] && (
        <section className="border-b border-line bg-paper">
          <div className="public-section grid gap-6 py-10 sm:py-14 lg:grid-cols-[auto_1fr_auto] lg:items-center">
            <span className="grid h-11 w-11 place-items-center rounded-full bg-[#E4E5D8] text-olive">
              <Megaphone size={18} />
            </span>
            <div>
              <p className="text-sm text-olive">Latest community update</p>
              <h2 className="mt-2 font-display text-3xl leading-tight sm:text-4xl">
                {space.announcements[0].title}
              </h2>
              <p className="mt-3 max-w-3xl text-sm leading-6 text-muted">
                {space.announcements[0].body}
              </p>
            </div>
            <Link className="text-link" to={href(`/${slug}/updates`)}>
              All updates <ChevronRight size={15} />
            </Link>
          </div>
        </section>
      )}
      <section className="public-section">
        <div className="section-heading">
          <div>
            <h2>Come as you are</h2>
            <p>Upcoming public gatherings from our community.</p>
          </div>
          <Link className="text-link" to={href(`/${slug}/gatherings`)}>
            See all <ChevronRight size={15} />
          </Link>
        </div>
        <div className="grid gap-5 md:grid-cols-2">
          {space.gatherings.slice(0, 2).map((item) => (
            <GatheringTile key={item.id} item={item} />
          ))}
        </div>
      </section>
      {space.galleries[0] && (
        <section className="border-t border-line">
          <div className="public-section grid gap-8 lg:grid-cols-[.8fr_1.2fr] lg:items-center">
            <div>
              <p className="page-kicker">Life together</p>
              <h2 className="mt-2 font-display text-4xl leading-tight sm:text-5xl">
                Photographs from our community.
              </h2>
              <p className="mt-4 max-w-md leading-7 text-muted">
                {space.galleries[0].description}
              </p>
              <Link className="text-link mt-6" to={href(`/${slug}/galleries`)}>
                Visit the Gallery <ChevronRight size={15} />
              </Link>
            </div>
            <Link
              to={href(`/${slug}/galleries/${space.galleries[0].slug}`)}
              className="group relative min-h-80 overflow-hidden rounded-[2rem]"
            >
              <img src={space.galleries[0].coverUrl || "/assets/devotional-table.webp"} alt="" className="absolute inset-0 h-full w-full object-cover" />
              <div className="absolute inset-0 bg-gradient-to-t from-ink/80 via-transparent to-transparent" />
              <h3 className="absolute inset-x-0 bottom-0 p-7 font-display text-4xl text-paper">
                {space.galleries[0].title}
              </h3>
            </Link>
          </div>
        </section>
      )}
      <section className="bg-paper">
        <div className="public-section grid gap-8 lg:grid-cols-[.8fr_1.2fr]">
          <div>
            <p className="page-kicker">Stories among us</p>
            <h2 className="mt-2 font-display text-4xl leading-tight sm:text-5xl">
              Faith becomes visible in ordinary lives.
            </h2>
            <Link className="text-link mt-6" to={href(`/${slug}/testimonies`)}>
              Read testimonies <ChevronRight size={15} />
            </Link>
          </div>
          <div className="grid gap-px bg-line sm:grid-cols-2">
            {space.testimonies.slice(0, 2).map((item) => (
              <Link
                key={item.id}
                to={href(`/${slug}/testimonies/${item.slug}`)}
                className="bg-paper p-7"
              >
                <p className="font-display text-3xl leading-tight">
                  {item.title}
                </p>
                <p className="mt-4 line-clamp-3 text-sm leading-6 text-muted">
                  {item.body}
                </p>
                <p className="mt-5 text-xs text-olive">{item.authorName}</p>
              </Link>
            ))}
          </div>
        </div>
      </section>
    </main>
  );
}

function GatheringTile({ item }: { item: PublicSpace["gatherings"][number] }) {
  const { space, href } = usePublic();
  return (
    <Link
      to={href(`/${space.organization.slug}/gatherings/${item.slug}`)}
      className="group grid min-h-72 overflow-hidden rounded-[2rem] border border-line bg-paper sm:grid-cols-[.9fr_1.1fr]"
    >
      <div className="p-7">
        <div className="flex flex-wrap items-center gap-2 text-xs text-olive">
          <span>{formatDate(item.meetingDate)}</span>
          {gatheringLifecycle(item) === "live" && <span className="status-badge">Happening now</span>}
          {item.destinationName && <span className="status-badge">{item.destinationName}</span>}
        </div>
        <h3 className="mt-3 font-display text-3xl leading-tight">
          {item.title}
        </h3>
        <p className="mt-3 text-sm leading-6 text-muted">
          {item.summary || item.notes}
        </p>
        <span className="text-link mt-7">
          View gathering <ChevronRight size={15} />
        </span>
      </div>
      <img
        src={gatheringCoverImage(item.slug || item.id, item.coverUrl)}
        alt=""
        className="h-full min-h-52 w-full object-cover transition-transform duration-500 motion-reduce:transition-none group-hover:scale-[1.02]"
      />
    </Link>
  );
}

export function PublicGatheringsPage() {
  const { space } = usePublic();
  return (
    <PublicIndex
      title="Gatherings"
      intro="Shared meals, honest conversation, Scripture, and prayer. Choose an evening and let us know you’re coming."
    >
      <div className="grid gap-5 md:grid-cols-2">
        {space.gatherings.map((item) => (
          <GatheringTile key={item.id} item={item} />
        ))}
      </div>
    </PublicIndex>
  );
}

function DiscoverySection({
  space,
  gatheringId,
  groupId,
}: {
  space: PublicSpace;
  gatheringId: string;
  groupId?: string;
}) {
  const slug = space.organization.slug;
  const readOnly = (path: string) => withBrowseMode(path, true);
  const group = groupId
    ? space.circles.find((item) => item.id === groupId)
    : undefined;
  const nextGathering =
    space.gatherings.find(
      (item) => item.id !== gatheringId && item.groupId === groupId,
    ) ?? space.gatherings.find((item) => item.id !== gatheringId);
  const testimony =
    space.testimonies.find((item) => item.groupId === groupId) ??
    space.testimonies[0];
  const groupGatheringIds = new Set(
    space.gatherings
      .filter((item) => item.groupId === groupId)
      .map((item) => item.id),
  );
  const gallery =
    space.galleries.find(
      (item) =>
        item.groupId === groupId ||
        (item.gatheringId && groupGatheringIds.has(item.gatheringId)),
    ) ?? space.galleries[0];
  if (!group && !nextGathering && !testimony && !gallery) return null;
  return (
    <section id="circle-life" className="public-section scroll-mt-28">
      <header className="mb-8 max-w-2xl">
        <p className="text-sm text-olive">A glimpse of community</p>
        <h2 className="mt-2 font-display text-4xl leading-tight sm:text-5xl">
          Life in {group?.name || space.organization.name}
        </h2>
        <p className="mt-3 leading-7 text-muted">
          See the gatherings, stories, and ordinary moments that shape this
          community.
        </p>
      </header>
      <div className="grid gap-5 lg:grid-cols-12">
        {group && (
          <Link
            to={readOnly(`/${slug}/circles/${group.slug}`)}
            className="group relative min-h-80 overflow-hidden rounded-[2rem] lg:col-span-7"
          >
            <img
              src={group.coverUrl || "/assets/devotional-table.webp"}
              alt=""
              className="absolute inset-0 h-full w-full object-cover transition-transform duration-500 motion-reduce:transition-none group-hover:scale-[1.02]"
            />
            <div className="absolute inset-0 bg-ink/55" />
            <div className="relative flex min-h-80 flex-col justify-end p-7 text-paper sm:p-9">
              <UsersRound />
              <h3 className="mt-4 font-display text-4xl leading-tight sm:text-5xl">
                {group.name}
              </h3>
              <p className="mt-3 max-w-xl text-sm leading-6 text-paper/80">
                {group.description}
              </p>
              <span className="mt-6 text-sm">View this Circle</span>
            </div>
          </Link>
        )}
        {nextGathering && (
          <Link
            to={readOnly(`/${slug}/gatherings/${nextGathering.slug}`)}
            className="flex min-h-80 flex-col justify-between rounded-[2rem] border border-line bg-paper p-7 lg:col-span-5"
          >
            <CalendarDays className="text-olive" />
            <div>
              <p className="text-sm text-olive">
                {formatDate(nextGathering.meetingDate)}
              </p>
              <h3 className="mt-3 font-display text-4xl leading-tight">
                {nextGathering.title}
              </h3>
              <p className="mt-3 text-sm leading-6 text-muted">
                {nextGathering.summary || nextGathering.notes}
              </p>
            </div>
          </Link>
        )}
        {testimony && (
          <Link
            to={readOnly(`/${slug}/testimonies/${testimony.slug}`)}
            className="border-l-2 border-sage px-5 py-4 sm:px-8 lg:col-span-5"
          >
            <p className="text-sm text-olive">A story among us</p>
            <h3 className="mt-3 font-display text-3xl leading-tight sm:text-4xl">
              {testimony.title}
            </h3>
            <p className="mt-4 line-clamp-3 leading-7 text-muted">
              {testimony.body}
            </p>
          </Link>
        )}
        {gallery && (
          <Link
            to={readOnly(`/${slug}/galleries/${gallery.slug}`)}
            className="group grid min-h-64 overflow-hidden rounded-[2rem] border border-line bg-paper sm:grid-cols-[1fr_.8fr] lg:col-span-7"
          >
            <img
              src={gallery.coverUrl || "/assets/devotional-table.webp"}
              alt=""
              className="h-full min-h-56 w-full object-cover transition-transform duration-500 motion-reduce:transition-none group-hover:scale-[1.02]"
            />
            <div className="flex flex-col justify-end p-6">
              <Images className="text-olive" />
              <h3 className="mt-3 font-display text-3xl leading-tight">
                {gallery.title}
              </h3>
              <p className="mt-2 text-sm leading-6 text-muted">
                {gallery.description}
              </p>
            </div>
          </Link>
        )}
      </div>
    </section>
  );
}

export function PublicGatheringPage() {
  const { space, browse, href } = usePublic();
  const { gatheringSlug } = useParams();
  const [searchParams, setSearchParams] = useSearchParams();
  const indexedItem = space.gatherings.find((entry) => entry.slug === gatheringSlug);
  const [directItem, setDirectItem] = useState<typeof indexedItem>();
  const [itemLoading, setItemLoading] = useState(!indexedItem);
  const [done, setDone] = useState(false);
  const [rsvpId, setRsvpId] = useState<string>();
  const [connectOpen, setConnectOpen] = useState(false);
  const [connectDone, setConnectDone] = useState(false);
  const [connectBusy, setConnectBusy] = useState(false);
  const [connectError, setConnectError] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [returnStatus, setReturnStatus] = useState("");
  const [rsvpBotToken, setRsvpBotToken] = useState("");
  const [connectionBotToken, setConnectionBotToken] = useState("");
  const updateRsvpBotToken = useCallback((token: string) => setRsvpBotToken(token), []);
  const updateConnectionBotToken = useCallback((token: string) => setConnectionBotToken(token), []);
  const [form, setForm] = useState({
    name: "",
    email: "",
    phone: "",
    status: "attending" as RsvpStatus,
  });
  const [connectForm, setConnectForm] = useState({
    preferredContact: "either" as ContactPreference,
    message: "",
    consent: false,
  });
  const install = useInstallPrompt();
  useEffect(() => {
    if (indexedItem) {
      setDirectItem(indexedItem);
      setItemLoading(false);
      return;
    }
    setItemLoading(true);
    void loadPublicGathering(
      supabase,
      space.organization.slug,
      gatheringSlug || "",
    )
      .then((value) => setDirectItem(value || undefined))
      .catch(() => setDirectItem(undefined))
      .finally(() => setItemLoading(false));
  }, [gatheringSlug, indexedItem, space.organization.slug]);
  const item = indexedItem || directItem;
  if (itemLoading)
    return (
      <div className="grid min-h-64 place-items-center">
        <div className="h-9 w-9 animate-spin rounded-full border-2 border-line border-t-olive" />
      </div>
    );
  if (!item)
    return (
      <PublicIndex
        title="Gathering not found"
        intro="This invitation may have moved or is no longer public."
      />
    );
  const lifecycle = gatheringLifecycle(item);
  const listedCircle = space.circles.find((circle) => circle.id === item.groupId);
  const communityUrl = publicCommunityUrl(space.organization.slug);
  const saveCommunityLink = async () => {
    try {
      await copyText(communityUrl);
      setReturnStatus("Community link copied.");
    } catch {
      setReturnStatus("The community link could not be copied.");
    }
  };
  const shareCommunity = async () => {
    try {
      const result = await shareLink(space.organization.name, communityUrl);
      if (result === "copied") setReturnStatus("Community link copied.");
    } catch {
      setReturnStatus("The community link could not be shared.");
    }
  };
  const submit = (event: FormEvent) => {
    event.preventDefault();
    setBusy(true);
    setError("");
    void submitGuestRsvp(supabase, item.id, form, { botToken: rsvpBotToken })
      .then((result) => {
        setRsvpId(result.id);
        setDone(true);
        const next = new URLSearchParams(searchParams);
        next.set("browse", "1");
        setSearchParams(next, { replace: true });
      })
      .catch((cause) =>
        setError(
          cause instanceof Error ? cause.message : "RSVP could not be saved.",
        ),
      )
      .finally(() => setBusy(false));
  };
  const connect = (event: FormEvent) => {
    if (!item.groupId) return;
    event.preventDefault();
    setConnectBusy(true);
    setConnectError("");
    void requestCircleConnection(supabase, {
      groupId: item.groupId,
      guestRsvpId: rsvpId,
      name: form.name,
      email: form.email,
      phone: form.phone,
      ...connectForm,
    }, { botToken: connectionBotToken })
      .then(() => setConnectDone(true))
      .catch((cause) =>
        setConnectError(
          cause instanceof Error
            ? cause.message
            : "Your connection request could not be sent.",
        ),
      )
      .finally(() => setConnectBusy(false));
  };
  const shareInvitation = async () => {
    const url = gatheringShareUrl(space.organization.slug, item.slug || "");
    try {
      const result = await shareLink(item.title, url);
      if (result === "copied") setReturnStatus("RSVP link copied.");
    } catch {
      setReturnStatus("The invitation could not be shared.");
    }
  };
  return (
    <main>
      <section className="public-section pb-10">
        <Link
          to={href(`/${space.organization.slug}/gatherings`)}
          className="text-link"
        >
          Back to gatherings
        </Link>
        <div className="mt-7 overflow-hidden rounded-[2rem] border border-line bg-paper sm:rounded-[2.25rem]">
          <img
            src={gatheringCoverImage(item.slug || item.id, item.coverUrl)}
            alt=""
            className="h-64 w-full object-cover object-[72%_center] sm:h-96 sm:object-center"
          />
          <div className="grid gap-10 p-6 sm:p-10 lg:grid-cols-[1.2fr_.8fr]">
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-3">
                <p className="page-kicker">{formatDate(item.meetingDate)}</p>
                {item.destinationName && <span className="status-badge">{item.destinationName}</span>}
              </div>
              <h1 className="mt-2 break-words font-display text-5xl leading-none sm:text-7xl">
                {item.title}
              </h1>
              <p className="mt-5 max-w-2xl text-lg leading-8 text-muted">
                {item.summary || item.notes}
              </p>
              <div className="mt-8 space-y-3 text-sm">
                <p className="flex gap-3">
                  <CalendarDays className="shrink-0 text-olive" size={18} />
                  {formatGatheringDateTime(item.meetingDate, item.endsAt)}
                </p>
                <p className="flex gap-3">
                  <MapPin className="shrink-0 text-olive" size={18} />
                  {item.location}
                </p>
              </div>
              {lifecycle === "upcoming" && (
                <button
                  className="secondary-button mt-8 min-h-11"
                  onClick={() => void shareInvitation()}
                >
                  <Share2 size={16} /> Share invitation
                </button>
              )}
              {returnStatus && !done && (
                <p role="status" className="mt-3 text-sm text-olive">
                  {returnStatus}
                </p>
              )}
            </div>
            <div className="border-t border-line pt-8 lg:border-l lg:border-t-0 lg:pl-10 lg:pt-0">
              {lifecycle === "attendance_pending" ? (
                <div className="py-4">
                  <p className="font-display text-4xl leading-tight">
                    This gathering has ended.
                  </p>
                  <p className="mt-3 leading-7 text-muted">
                    {gatheringRelativeStatus(item.endsAt)}. This invitation remains available for reference. See what is coming next in the community.
                  </p>
                  <Link className="primary-button mt-6" to={href(`/${space.organization.slug}/gatherings`)}>
                    See upcoming gatherings
                  </Link>
                </div>
              ) : lifecycle === "live" ? (
                <div className="py-4">
                  <span className="status-badge">Happening now</span>
                  <p className="mt-4 font-display text-4xl leading-tight">
                    The gathering is underway.
                  </p>
                  <p className="mt-3 leading-7 text-muted">
                    RSVPs are closed, but the invitation details remain available.
                  </p>
                </div>
              ) : done ? (
                <div>
                  <p className="font-display text-4xl leading-tight">
                    You’re on the list.
                  </p>
                  <p className="mt-3 leading-7 text-muted">
                    We look forward to welcoming you.
                  </p>
                  <div className="mt-7 grid gap-3">
                    <Link
                      className="primary-button min-h-11 w-full justify-center text-center"
                      to={`/${space.organization.slug}/cell-group-signup`}
                      state={{
                        signupPrefill: {
                          firstName: form.name.trim().split(/\s+/)[0] || "",
                          lastName: form.name.trim().split(/\s+/).slice(1).join(" "),
                          phone: form.phone,
                          guestRsvpId: rsvpId,
                        },
                      }}
                    >
                      Sign up for a Cell Group
                    </Link>
                    {listedCircle ? (
                      <button
                        className="secondary-button min-h-11 w-full justify-center"
                        onClick={() =>
                          document.getElementById("circle-life")?.scrollIntoView({
                            behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth",
                          })
                        }
                      >
                        Explore this Circle
                      </button>
                    ) : (
                      <Link className="primary-button min-h-11 w-full justify-center" to={withBrowseMode(`/${space.organization.slug}/gatherings`, true)}>
                        See upcoming gatherings
                      </Link>
                    )}
                    <Link
                      className="secondary-button min-h-11 w-full justify-center text-center"
                      to={withBrowseMode(`/${space.organization.slug}`, true)}
                    >
                      See all gatherings and community activities
                    </Link>
                  </div>
                  {listedCircle && <div className="mt-8 border-t border-line pt-6">
                    {connectDone ? (
                      <div role="status" className="rounded-2xl bg-parchment p-5">
                        <p className="font-display text-2xl">A leader will be in touch.</p>
                        <p className="mt-2 text-sm leading-6 text-muted">
                          Your request was shared with this Circle’s leaders.
                        </p>
                      </div>
                    ) : connectOpen ? (
                      <form onSubmit={connect} className="space-y-4">
                        <div>
                          <h2 className="font-display text-2xl">Connect with this Circle</h2>
                          <p className="mt-2 text-sm leading-6 text-muted">
                            Ask a leader to contact you about taking a next step.
                          </p>
                        </div>
                        <label className="field-label">
                          Contact me by
                          <select
                            className="field"
                            value={connectForm.preferredContact}
                            onChange={(event) =>
                              setConnectForm({
                                ...connectForm,
                                preferredContact: event.target.value as ContactPreference,
                              })
                            }
                          >
                            {form.email && <option value="email">Email</option>}
                            {form.phone && <option value="phone">Phone</option>}
                            <option value="either">Either email or phone</option>
                          </select>
                        </label>
                        <label className="field-label">
                          Anything you’d like the leader to know? (optional)
                          <textarea
                            className="field min-h-20"
                            maxLength={1000}
                            value={connectForm.message}
                            onChange={(event) =>
                              setConnectForm({ ...connectForm, message: event.target.value })
                            }
                          />
                        </label>
                        <label className="flex items-start gap-3 text-sm leading-6 text-muted">
                          <input
                            className="mt-1 h-4 w-4 shrink-0"
                            type="checkbox"
                            required
                            checked={connectForm.consent}
                            onChange={(event) =>
                              setConnectForm({ ...connectForm, consent: event.target.checked })
                            }
                          />
                          I agree that a Circle leader may contact me about this community.
                        </label>
                        <Turnstile onToken={updateConnectionBotToken} />
                        {connectError && <p className="form-error" role="alert">{connectError}</p>}
                        <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-1 xl:grid-cols-2">
                          <button className="primary-button min-h-11" disabled={connectBusy || !connectForm.consent || !connectionBotToken}>
                            {connectBusy ? "Sending…" : "Ask a leader to contact me"}
                          </button>
                          <button type="button" className="secondary-button min-h-11" onClick={() => setConnectOpen(false)}>
                            Not now
                          </button>
                        </div>
                      </form>
                    ) : (
                      <button className="secondary-button min-h-11 w-full" onClick={() => setConnectOpen(true)}>
                        I’d like to connect with this Circle
                      </button>
                    )}
                  </div>}
                  <details className="mt-8 border-t border-line pt-6">
                    <summary className="cursor-pointer font-display text-2xl">More ways to stay connected</summary>
                    <p className="mt-2 text-sm leading-6 text-muted">
                      Save this community so its public gatherings and stories
                      are easy to find again.
                    </p>
                    <div className="mt-4 grid gap-2 sm:grid-cols-2 lg:grid-cols-1 xl:grid-cols-2">
                      <button
                        className="secondary-button min-h-11 justify-center"
                        onClick={() => void saveCommunityLink()}
                      >
                        <Copy size={16} /> Save community link
                      </button>
                      <button
                        className="secondary-button min-h-11 justify-center"
                        onClick={() => void shareCommunity()}
                      >
                        <Share2 size={16} /> Share community
                      </button>
                    </div>
                    {install.canInstall && !install.standalone && (
                      <button
                        className="secondary-button mt-2 min-h-11 w-full justify-center"
                        onClick={() => void install.install()}
                      >
                        <Smartphone size={16} /> Add Circles to your home screen
                      </button>
                    )}
                    {install.isIos && !install.standalone && (
                      <p className="mt-3 text-xs leading-5 text-muted">
                        On iPhone or iPad, tap Share, then Add to Home Screen.
                      </p>
                    )}
                    {returnStatus && (
                      <p role="status" className="mt-3 text-sm text-olive">
                        {returnStatus}
                      </p>
                    )}
                  </details>
                </div>
              ) : browse ? (
                <div className="py-4">
                  <p className="font-display text-3xl leading-tight">
                    You’re viewing this gathering.
                  </p>
                  <p className="mt-3 leading-7 text-muted">
                    Browse the details and continue exploring public community
                    life.
                  </p>
                </div>
              ) : item.guestRsvpEnabled ? (
                <form onSubmit={submit} className="space-y-4">
                  <h2 className="font-display text-3xl">Will you join us?</h2>
                  <label className="field-label">
                    Your name
                    <input
                      className="field"
                      required
                      value={form.name}
                      onChange={(event) =>
                        setForm({ ...form, name: event.target.value })
                      }
                    />
                  </label>
                  <div className="grid gap-3 sm:grid-cols-2">
                    <label className="field-label">
                      Email
                      <input
                        className="field"
                        type="email"
                        value={form.email}
                        onChange={(event) =>
                          setForm({ ...form, email: event.target.value })
                        }
                      />
                    </label>
                    <label className="field-label">
                      Phone
                      <input
                        className="field"
                        value={form.phone}
                        onChange={(event) =>
                          setForm({ ...form, phone: event.target.value })
                        }
                      />
                    </label>
                  </div>
                  <p className="text-xs text-muted">
                    Add an email or phone number so the leader can identify your
                    RSVP.
                  </p>
                  <label className="field-label">
                    Response
                    <select
                      className="field"
                      value={form.status}
                      onChange={(event) =>
                        setForm({
                          ...form,
                          status: event.target.value as RsvpStatus,
                        })
                      }
                    >
                      <option value="attending">I’m going</option>
                      <option value="tentative">Maybe</option>
                      <option value="declined">Can’t make it</option>
                    </select>
                  </label>
                  <Turnstile onToken={updateRsvpBotToken} />
                  {error && <p className="form-error">{error}</p>}
                  <button
                    className="primary-button min-h-11 w-full justify-center"
                    disabled={busy || !rsvpBotToken || (!form.email && !form.phone)}
                  >
                    {busy ? "Saving…" : "Save my RSVP"}
                  </button>
                </form>
              ) : (
                <p className="text-muted">
                  Guest RSVP is closed for this gathering.
                </p>
              )}
            </div>
          </div>
        </div>
      </section>
      {(done || browse) && lifecycle !== "attendance_pending" && (
        <DiscoverySection
          space={space}
          gatheringId={item.id}
          groupId={item.groupId}
        />
      )}
    </main>
  );
}

export function PublicUpdatesPage() {
  const { space, href } = usePublic();
  if (!space.announcements.length)
    return (
      <PublicIndex
        title="Updates"
        intro="There are no public community updates right now."
      >
        <Link className="primary-button" to={href(`/${space.organization.slug}/gatherings`)}>
          See upcoming gatherings
        </Link>
      </PublicIndex>
    );
  return (
    <PublicIndex title="Updates" intro="Current notes and invitations from our community.">
      <div className="mx-auto max-w-4xl divide-y divide-line border-y border-line">
        {space.announcements.map((item) => (
          <article key={item.id} className="py-7 sm:py-10">
            <p className="text-sm text-olive">{formatDate(item.publishedAt)}</p>
            <h2 className="mt-2 font-display text-3xl leading-tight sm:text-4xl">{item.title}</h2>
            <p className="mt-4 whitespace-pre-line leading-7 text-muted">{item.body}</p>
          </article>
        ))}
      </div>
    </PublicIndex>
  );
}

export function TestimoniesPage() {
  const { space, href } = usePublic();
  return (
    <PublicIndex
      title="Testimonies"
      intro="Stories of grace, courage, healing, and steady faith from people in our community."
    >
      <div className="grid gap-px bg-line md:grid-cols-2">
        {space.testimonies.map((item) => (
          <Link
            className="bg-parchment p-7 sm:p-10"
            key={item.id}
            to={href(`/${space.organization.slug}/testimonies/${item.slug}`)}
          >
            <p className="font-display text-4xl leading-tight">{item.title}</p>
            <p className="mt-4 line-clamp-4 leading-7 text-muted">
              {item.body}
            </p>
            <p className="mt-6 text-sm text-olive">{item.authorName}</p>
          </Link>
        ))}
      </div>
    </PublicIndex>
  );
}

export function TestimonyPage() {
  const { space } = usePublic();
  const { testimonySlug } = useParams();
  const item = space.testimonies.find((entry) => entry.slug === testimonySlug);
  if (!item)
    return (
      <PublicIndex
        title="Testimony not found"
        intro="This story is not available."
      />
    );
  return (
    <main className="public-section">
      <article className="mx-auto max-w-3xl">
        <p className="page-kicker">A story from {space.organization.name}</p>
        <h1 className="mt-3 break-words font-display text-5xl leading-tight sm:text-7xl">
          {item.title}
        </h1>
        <p className="mt-5 text-sm text-olive">Shared by {item.authorName}</p>
        {item.imageUrl && (
          <img
            src={item.imageUrl}
            alt=""
            className="mt-10 max-h-[34rem] w-full rounded-[2rem] object-cover"
          />
        )}
        <p className="mt-10 whitespace-pre-line font-display text-2xl leading-10 text-[#45483F]">
          {item.body}
        </p>
      </article>
    </main>
  );
}

export function GalleriesPage() {
  const { space, href } = usePublic();
  return (
    <PublicIndex title="Gallery" intro="Small glimpses of life together.">
      <div className="grid gap-5 md:grid-cols-2">
        {space.galleries.map((gallery) => (
          <Link
            key={gallery.id}
            to={href(`/${space.organization.slug}/galleries/${gallery.slug}`)}
            className="group relative min-h-80 overflow-hidden rounded-[2rem] sm:min-h-96"
          >
            <img
              src={gallery.coverUrl || "/assets/devotional-table.webp"}
              alt=""
              className="absolute inset-0 h-full w-full object-cover transition-transform duration-500 motion-reduce:transition-none group-hover:scale-[1.02]"
            />
            <div className="absolute inset-0 bg-ink/60" />
            <div className="absolute inset-x-0 bottom-0 p-7 text-white">
              <Images />
              <h2 className="mt-3 font-display text-4xl">{gallery.title}</h2>
              <p className="mt-2 text-sm text-white/75">
                {gallery.description}
              </p>
            </div>
          </Link>
        ))}
      </div>
    </PublicIndex>
  );
}

export function GalleryPage() {
  const { space } = usePublic();
  const { gallerySlug } = useParams();
  const gallery = galleryBySlug(space, gallerySlug || "");
  const [active, setActive] = useState<string>();
  if (!gallery)
    return (
      <PublicIndex
        title="Gallery not found"
        intro="This album is not available."
      />
    );
  return (
    <PublicIndex title={gallery.title} intro={gallery.description}>
      <div className="grid gap-4 sm:grid-cols-2">
        {gallery.photos.map((photo) => (
          <button
            key={photo.id}
            onClick={() => setActive(photo.imageUrl)}
            className="overflow-hidden rounded-3xl"
          >
            <img
              src={photo.imageUrl}
              alt={photo.altText}
              className="h-80 w-full object-cover"
            />
            <span className="block bg-paper p-4 text-left text-sm text-muted">
              {photo.caption}
            </span>
          </button>
        ))}
      </div>
      {active && (
        <button
          className="fixed inset-0 z-50 grid bg-black/90 p-5"
          onClick={() => setActive(undefined)}
          aria-label="Close image"
        >
          <img
            src={active}
            alt=""
            className="m-auto max-h-full max-w-full object-contain"
          />
        </button>
      )}
    </PublicIndex>
  );
}

export function PublicCirclesPage() {
  const { space, href } = usePublic();
  if (!space.circles.length)
    return (
      <PublicIndex
        title="Circles"
        intro="This community has not published any Circle profiles yet."
      >
        <Link className="primary-button" to={href(`/${space.organization.slug}/gatherings`)}>
          See upcoming gatherings
        </Link>
      </PublicIndex>
    );
  return (
    <PublicIndex
      title="Join a Circle"
      intro="Learn about each smaller community, then let a leader know where you would like to belong."
    >
      <div className="mb-8 flex flex-col gap-4 border-y border-line py-6 sm:flex-row sm:items-center sm:justify-between">
        <p className="max-w-2xl text-sm leading-6 text-muted">
          Ready to be placed in a Cell Group? Complete the official signup for
          the shared leader placement list.
        </p>
        <Link className="primary-button shrink-0" to={`/${space.organization.slug}/cell-group-signup`}>
          Sign up for a Cell Group
        </Link>
      </div>
      <div className="grid gap-5 md:grid-cols-2">
        {space.circles.map((group) => (
          <Link
            key={group.id}
            to={href(`/${space.organization.slug}/circles/${group.slug}`)}
            className="paper-panel overflow-hidden"
          >
            <img
              src={group.coverUrl || "/assets/devotional-table.webp"}
              alt=""
              className="aspect-[16/9] w-full object-cover"
            />
            <div className="p-7">
              <h2 className="font-display text-3xl">{group.name}</h2>
              <p className="mt-3 leading-7 text-muted">{group.description}</p>
              <span className="text-link mt-6">
                Learn about this Circle <ChevronRight size={15} />
              </span>
            </div>
          </Link>
        ))}
      </div>
    </PublicIndex>
  );
}

export function PublicCirclePage() {
  const { space, browse, href } = usePublic();
  const { circleSlug } = useParams();
  const group = space.circles.find((entry) => entry.slug === circleSlug);
  const [done, setDone] = useState(false);
  const [formOpen, setFormOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [botToken, setBotToken] = useState("");
  const updateBotToken = useCallback((token: string) => setBotToken(token), []);
  const nameRef = useRef<HTMLInputElement>(null);
  const [form, setForm] = useState({
    name: "",
    email: "",
    phone: "",
    preferredContact: "either" as ContactPreference,
    message: "",
    consent: false,
  });
  if (!group)
    return (
      <PublicIndex
        title="Circle not found"
        intro="This Circle is not publicly listed."
      />
    );
  const nextGathering = space.gatherings
    .filter((item) => item.groupId === group.id)
    .sort((a, b) => a.meetingDate.localeCompare(b.meetingDate))[0];
  const openInterestForm = () => {
    setFormOpen(true);
    window.requestAnimationFrame(() => nameRef.current?.focus());
  };
  return (
    <main className="public-section">
      <div className="grid overflow-hidden rounded-[2rem] border border-line bg-paper lg:grid-cols-2">
        <img
          src={group.coverUrl || "/assets/devotional-table.webp"}
          alt=""
          className="aspect-[16/9] h-full min-h-72 w-full object-cover lg:aspect-auto"
        />
        <div className="p-7 sm:p-10">
          <UsersRound className="text-olive" />
          <h1 className="mt-4 break-words font-display text-5xl">
            {group.name}
          </h1>
          <p className="mt-5 leading-8 text-muted">{group.description}</p>
          <p className="mt-5 text-sm text-olive">{group.location}</p>
          {nextGathering && (
            <Link
              className="mt-7 block border-y border-line py-5"
              to={href(`/${space.organization.slug}/gatherings/${nextGathering.slug}`)}
            >
              <span className="text-xs text-olive">Next public gathering</span>
              <strong className="mt-2 block font-display text-2xl font-normal">{nextGathering.title}</strong>
              <span className="mt-1 block text-sm text-muted">{formatDate(nextGathering.meetingDate)} at {formatTime(nextGathering.meetingDate)}</span>
            </Link>
          )}
          {browse ? (
            <div className="mt-10 border-t border-line pt-7">
              <p className="font-display text-3xl">Keep exploring</p>
              <p className="mt-3 leading-7 text-muted">
                Browse more published gatherings and stories from this
                community.
              </p>
              <Link
                className="secondary-button mt-5 min-h-11 justify-center"
                to={href(`/${space.organization.slug}`)}
              >
                See all community activities
              </Link>
            </div>
          ) : done ? (
            <div className="mt-10 rounded-2xl bg-parchment p-5" role="status">
              <p className="font-display text-2xl">Your interest was sent.</p>
              <p className="mt-2 text-sm leading-6 text-muted">A leader will follow up using the contact you provided.</p>
              <div className="mt-5 flex flex-wrap gap-2">
                <Link className="primary-button" to={href(`/${space.organization.slug}/gatherings`)}>Upcoming gatherings</Link>
                <Link className="secondary-button" to={href(`/${space.organization.slug}`)}>Community home</Link>
              </div>
            </div>
          ) : !formOpen ? (
            <div className="mt-10 border-t border-line pt-7">
              <h2 className="font-display text-3xl">Could this be your Circle?</h2>
              <p className="mt-3 text-sm leading-6 text-muted">Tell a leader you would like to learn more. This sends an interest request; it does not create an account or add you as a member.</p>
              <button type="button" className="primary-button mt-5 w-full" onClick={openInterestForm}>I’m interested in joining</button>
              <Link className="secondary-button mt-3 w-full justify-center text-center" to={`/${space.organization.slug}/cell-group-signup`}>
                Sign up for a Cell Group
              </Link>
            </div>
          ) : (
            <form
              className="mt-10 space-y-4"
              onSubmit={(event) => {
                event.preventDefault();
                setBusy(true);
                setError("");
                void requestCircleConnection(supabase, {
                  groupId: group.id,
                  ...form,
                }, { botToken })
                  .then(() => setDone(true))
                  .catch((cause) =>
                    setError(
                      cause instanceof Error
                        ? cause.message
                        : "Your connection request could not be sent.",
                    ),
                  )
                  .finally(() => setBusy(false));
              }}
            >
              <h2 className="font-display text-3xl">Tell a leader you’re interested</h2>
              <p className="text-sm leading-6 text-muted">A leader will use these details only to follow up about this Circle. This does not create an account or membership.</p>
              <label className="field-label">
                Name
                <input
                  ref={nameRef}
                  className="field"
                  required
                  value={form.name}
                  onChange={(event) =>
                    setForm({ ...form, name: event.target.value })
                  }
                />
              </label>
              <div className="grid gap-3 sm:grid-cols-2">
                <label className="field-label">
                  Email
                  <input
                    className="field"
                    type="email"
                    value={form.email}
                    onChange={(event) =>
                      setForm({ ...form, email: event.target.value })
                    }
                  />
                </label>
                <label className="field-label">
                  Phone
                  <input
                    className="field"
                    value={form.phone}
                    onChange={(event) =>
                      setForm({ ...form, phone: event.target.value })
                    }
                  />
                </label>
              </div>
              <label className="field-label">
                Contact me by
                <select
                  className="field"
                  value={form.preferredContact}
                  onChange={(event) =>
                    setForm({
                      ...form,
                      preferredContact: event.target.value as ContactPreference,
                    })
                  }
                >
                  <option value="either">Either email or phone</option>
                  <option value="email">Email</option>
                  <option value="phone">Phone</option>
                </select>
              </label>
              <label className="field-label">
                Message
                <textarea
                  className="field min-h-24"
                  value={form.message}
                  onChange={(event) =>
                    setForm({ ...form, message: event.target.value })
                  }
                />
              </label>
              <label className="flex items-start gap-3 text-sm leading-6 text-muted">
                <input
                  className="mt-1 h-4 w-4 shrink-0"
                  type="checkbox"
                  required
                  checked={form.consent}
                  onChange={(event) =>
                    setForm({ ...form, consent: event.target.checked })
                  }
                />
                I agree that a Circle leader may contact me about this community.
              </label>
              <Turnstile onToken={updateBotToken} />
              {error && <p className="form-error" role="alert">{error}</p>}
              <button
                className="primary-button min-h-11 w-full"
                disabled={
                  busy ||
                  !botToken ||
                  !form.consent ||
                  (!form.email && !form.phone) ||
                  (form.preferredContact === "email" && !form.email) ||
                  (form.preferredContact === "phone" && !form.phone)
                }
              >
                {busy ? "Sending…" : "Ask a leader to contact me"}
              </button>
            </form>
          )}
        </div>
      </div>
    </main>
  );
}

function PublicIndex({
  title,
  intro,
  children,
}: {
  title: string;
  intro: string;
  children?: ReactNode;
}) {
  return (
    <main className="public-section">
      <header className="mb-10 max-w-3xl sm:mb-12">
        <h1 className="break-words font-display text-5xl leading-none sm:text-7xl">
          {title}
        </h1>
        <p className="mt-5 text-lg leading-8 text-muted">{intro}</p>
      </header>
      {children}
    </main>
  );
}
