import { Heart, MessageCircle, Pin, RefreshCw, Search, X } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { useCircles } from "../AppContext";
import { getErrorMessage } from "../lib/errors";
import { getDemoFeedPreferenceIds } from "../lib/demoFeedPreferences";
import { supabase } from "../lib/supabase";
import { loadCommunityFeed, markCommunityFeedSeen, searchCommunityFeed } from "../services/feed";
import type { CommunityFeedItem, FeedCursor } from "../types";
import { FeedCard } from "./FeedCard";
import { FeedComposer } from "./FeedComposer";
import { Modal } from "./Modal";
import { PrayerForm } from "./PrayerForm";

export function CommunityFeed() {
  const { data, demoMode } = useCircles();
  const organizationId = data?.organization.id;
  const demoFeed = data?.communityFeed;
  const [items, setItems] = useState<CommunityFeedItem[]>([]);
  const [pinnedItems, setPinnedItems] = useState<CommunityFeedItem[]>([]);
  const [filter, setFilter] = useState("all");
  const [searchOpen, setSearchOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [type, setType] = useState("");
  const [authorPersonId, setAuthorPersonId] = useState("");
  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");
  const [cursor, setCursor] = useState<FeedCursor>();
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState("");
  const [prayerOpen, setPrayerOpen] = useState(false);
  const searchWasActive = useRef(false);

  const load = useCallback(async (append = false, pageCursor?: FeedCursor) => {
    if (!organizationId) return;
    if (demoMode || !supabase) {
      const savedIds = new Set(getDemoFeedPreferenceIds("saved"));
      const hiddenIds = new Set(getDemoFeedPreferenceIds("hidden"));
      const source = (demoFeed ?? [])
        .filter((item) => !hiddenIds.has(item.id))
        .filter((item) => filter === "all" || (filter === "organization" ? item.audience === "organization" : item.groupId === filter))
        .map((item) => savedIds.has(item.id) ? { ...item, savedByMe: true } : item);
      setItems(source);
      setPinnedItems(source.filter((item) => item.isPinned));
      setCursor(undefined); setLoading(false); setLoadingMore(false); return;
    }
    if (append) setLoadingMore(true);
    else setLoading(true);
    setError("");
    try {
      const page = await loadCommunityFeed(supabase, {
        cursor: append ? pageCursor : undefined,
        organizationOnly: filter === "organization",
        circleId: !["all", "organization"].includes(filter) ? filter : undefined,
      });
      setItems((current) => append ? [...current, ...page.items] : page.items);
      if (!append) setPinnedItems(page.pinnedItems ?? []);
      setCursor(page.nextCursor);
      if (!append) void markCommunityFeedSeen(supabase).catch(() => undefined);
    } catch (cause) { setError(getErrorMessage(cause, "The community feed could not be loaded.")); }
    finally { setLoading(false); setLoadingMore(false); }
  }, [demoFeed, demoMode, filter, organizationId]);

  useEffect(() => { void load(false); }, [load]);
  useEffect(() => {
    const hasSearch = Boolean(query.trim() || type || authorPersonId || dateFrom || dateTo);
    if (!hasSearch || !organizationId || demoMode || !supabase) {
      if (!hasSearch && searchWasActive.current && organizationId && !demoMode && supabase) void load(false);
      searchWasActive.current = hasSearch;
      return;
    }
    searchWasActive.current = true;
    let active = true;
    const timeout = window.setTimeout(() => {
      void searchCommunityFeed(supabase!, {
        query,
        type,
        circleId: !["all", "organization"].includes(filter) ? filter : undefined,
        organizationOnly: filter === "organization",
        authorPersonId,
        dateFrom,
        dateTo,
      }).then((results) => { if (active) setItems(results); }).catch((cause) => { if (active) setError(getErrorMessage(cause, "Community search could not be completed.")); });
    }, 250);
    return () => { active = false; window.clearTimeout(timeout); };
  }, [query, type, authorPersonId, dateFrom, dateTo, filter, organizationId, demoMode, load]);
  if (!data) return null;
  const update = (next: CommunityFeedItem) => {
    setItems((current) => current.map((item) => item.id === next.id ? next : item));
    setPinnedItems((current) => next.isPinned
      ? current.some((item) => item.id === next.id) ? current.map((item) => item.id === next.id ? next : item) : [next, ...current]
      : current.filter((item) => item.id !== next.id));
  };
  const removeItem = (id: string) => {
    setItems((current) => current.filter((entry) => entry.id !== id));
    setPinnedItems((current) => current.filter((entry) => entry.id !== id));
  };
  const hasSearch = Boolean(query.trim() || type || authorPersonId || dateFrom || dateTo);
  const searchedItems = (demoMode || !supabase) && hasSearch
    ? items.filter((item) => {
      const day = (item.activityAt ?? item.createdAt).slice(0, 10);
      return (!query.trim() || `${item.authorName} ${item.title ?? ""} ${item.body ?? ""}`.toLowerCase().includes(query.trim().toLowerCase()))
        && (!type || item.type === type)
        && (!authorPersonId || item.authorPersonId === authorPersonId)
        && (!dateFrom || day >= dateFrom)
        && (!dateTo || day <= dateTo);
    })
    : items;
  const pinnedIds = new Set(pinnedItems.map((item) => item.id));
  const visibleItems = hasSearch ? searchedItems : searchedItems.filter((item) => !pinnedIds.has(item.id));

  return (
    <section aria-labelledby="community-feed-title">
      <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
        <h1 id="community-feed-title" className="font-display text-xl sm:text-3xl">Community feed</h1>
        <div className="flex items-center gap-1">
          <label>
            <span className="sr-only">Show</span>
            <select className="min-h-11 max-w-28 rounded-xl border-0 bg-transparent py-2 pl-2 pr-7 text-sm text-olive focus-visible:outline-olive sm:max-w-48" value={filter} onChange={(event) => setFilter(event.target.value)}>
              <option value="all">All activity</option>
              <option value="organization">Entire organization</option>
              {data.groups.map((group) => <option value={group.id} key={group.id}>{group.name}</option>)}
            </select>
          </label>
          <button type="button" aria-label={searchOpen ? "Close community search" : "Open community search"} aria-expanded={searchOpen} aria-controls="community-search" className="relative inline-flex h-11 w-11 items-center justify-center rounded-xl text-olive hover:bg-paper focus-visible:outline-olive" onClick={() => setSearchOpen(!searchOpen)}>
            {searchOpen ? <X size={18} /> : <Search size={18} />}
            {hasSearch && <span className="absolute right-1 top-1 h-2 w-2 rounded-full bg-olive"><span className="sr-only">Search filters active</span></span>}
          </button>
        </div>
      </div>
      <div id="community-search" hidden={!searchOpen}>
      <label className="relative mb-4 block">
        <span className="sr-only">Search community</span>
        <Search size={17} className="pointer-events-none absolute left-4 top-1/2 -translate-y-1/2 text-muted" />
        <input type="search" aria-label="Search community" className="field mt-0 pl-11" placeholder="Search people and community posts" value={query} onChange={(event) => setQuery(event.target.value)} />
      </label>
      <details className="group mb-4 rounded-2xl border border-line bg-paper/60">
        <summary className="flex min-h-11 cursor-pointer list-none items-center justify-between px-4 py-2 text-sm font-medium text-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-olive">More search filters <span className="text-xs text-olive">{[type, authorPersonId, dateFrom, dateTo].filter(Boolean).length || ""}</span></summary>
        <div className="grid gap-3 border-t border-line p-3 sm:grid-cols-2 xl:grid-cols-4" aria-label="Community search filters">
          <label className="field-label text-xs">Activity type<select className="field mt-1 bg-paper text-sm" value={type} onChange={(event) => setType(event.target.value)}><option value="">All types</option><option value="post">Updates</option><option value="reflection">Reflections</option><option value="prayer">Prayers</option><option value="gathering">Gatherings</option><option value="announcement">Announcements</option></select></label>
          <label className="field-label text-xs">Author<select className="field mt-1 bg-paper text-sm" value={authorPersonId} onChange={(event) => setAuthorPersonId(event.target.value)}><option value="">All authors</option>{data.members.map((member) => <option key={member.id} value={member.id}>{member.fullName}</option>)}</select></label>
          <label className="field-label text-xs">From date<input className="field mt-1 bg-paper text-sm" type="date" value={dateFrom} onChange={(event) => setDateFrom(event.target.value)} /></label>
          <label className="field-label text-xs">To date<input className="field mt-1 bg-paper text-sm" type="date" value={dateTo} onChange={(event) => setDateTo(event.target.value)} /></label>
        </div>
      </details>
      </div>
      <FeedComposer
        onCreated={(item) => item ? setItems((current) => [item, ...current]) : void load(false)}
        onPrayer={() => setPrayerOpen(true)}
      />
      {error && <div className="mt-4 flex items-center justify-between gap-4 rounded-xl border border-line bg-paper p-4" role="alert"><span className="text-sm">{error}</span><button className="secondary-button" onClick={() => void load(false)}><RefreshCw size={15} /> Retry</button></div>}
      {!hasSearch && pinnedItems.length > 0 && <section className="mt-5" aria-labelledby="pinned-community-title">
        <h2 id="pinned-community-title" className="mb-3 flex items-center gap-2 text-xs font-medium text-muted"><Pin size={14} /> Pinned for this community</h2>
        <div className="space-y-4">{pinnedItems.map((item) => <FeedCard key={`pin-${item.id}`} item={item} onUpdate={update} onRemove={() => removeItem(item.id)} />)}</div>
      </section>}
      {loading ? (
        <div className="mt-5 space-y-4" aria-busy="true" aria-label="Loading community feed">{[1, 2, 3].map((item) => <div className="h-52 animate-pulse rounded-2xl bg-paper" key={item} />)}</div>
      ) : visibleItems.length ? (
        <div className="mt-5 space-y-5">
          {visibleItems.some((item) => item.isNew) && <div className="flex items-center gap-3 text-xs font-medium text-olive" role="separator"><span className="h-px flex-1 bg-olive/30" />New activity<span className="h-px flex-1 bg-olive/30" /></div>}
          {visibleItems.map((item) => <FeedCard key={item.id} item={item} onUpdate={update} onRemove={() => removeItem(item.id)} />)}
        </div>
      ) : (
        <div className="mt-5 grid min-h-64 place-items-center border-y border-line text-center" role="status"><div><MessageCircle className="mx-auto text-olive" /><h2 className="mt-4 font-display text-2xl">The conversation starts here</h2><p className="mt-2 text-sm text-muted">Share an update, a photo, or a prayer with your community.</p></div></div>
      )}
      {cursor && !hasSearch && <button className="secondary-button mx-auto mt-6 flex" disabled={loadingMore} onClick={() => void load(true, cursor)}>{loadingMore ? "Loading…" : "Load more"}</button>}
      <p className="mt-5 flex items-center justify-center gap-2 text-xs text-muted"><Heart size={13} /> Visible only to signed-in members with the selected audience.</p>
      {prayerOpen && (
        <Modal title="Share a prayer request" onClose={() => setPrayerOpen(false)}>
          <PrayerForm onDone={() => { setPrayerOpen(false); void load(false); }} />
        </Modal>
      )}
    </section>
  );
}
