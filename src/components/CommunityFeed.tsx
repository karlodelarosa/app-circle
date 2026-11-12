import { Heart, MessageCircle, RefreshCw } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { useCircles } from "../AppContext";
import { getErrorMessage } from "../lib/errors";
import { supabase } from "../lib/supabase";
import { loadCommunityFeed } from "../services/feed";
import type { CommunityFeedItem, FeedCursor } from "../types";
import { FeedCard } from "./FeedCard";
import { FeedComposer } from "./FeedComposer";
import { Modal } from "./Modal";
import { PrayerForm } from "./PrayerForm";

export function CommunityFeed() {
  const { data, demoMode } = useCircles();
  const [items, setItems] = useState<CommunityFeedItem[]>([]);
  const [filter, setFilter] = useState("all");
  const [cursor, setCursor] = useState<FeedCursor>();
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState("");
  const [prayerOpen, setPrayerOpen] = useState(false);

  const load = useCallback(async (append = false) => {
    if (!data) return;
    if (demoMode || !supabase) {
      const source = data.communityFeed ?? [];
      setItems(source.filter((item) => filter === "all" || (filter === "organization" ? item.audience === "organization" : item.groupId === filter)));
      setCursor(undefined); setLoading(false); setLoadingMore(false); return;
    }
    if (append) setLoadingMore(true);
    else setLoading(true);
    setError("");
    try {
      const page = await loadCommunityFeed(supabase, {
        cursor: append ? cursor : undefined,
        organizationOnly: filter === "organization",
        circleId: !["all", "organization"].includes(filter) ? filter : undefined,
      });
      setItems((current) => append ? [...current, ...page.items] : page.items);
      setCursor(page.nextCursor);
    } catch (cause) { setError(getErrorMessage(cause, "The community feed could not be loaded.")); }
    finally { setLoading(false); setLoadingMore(false); }
  }, [data, demoMode, filter, cursor]);

  useEffect(() => { void load(false); /* cursor changes after loading, not a reload signal */
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data?.organization.id, filter, demoMode]);
  if (!data) return null;
  const update = (next: CommunityFeedItem) => setItems((current) => current.map((item) => item.id === next.id ? next : item));

  return (
    <section aria-labelledby="community-feed-title">
      <div className="mb-5 flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="page-kicker">Life together</p>
          <h1 id="community-feed-title" className="mt-2 font-display text-4xl sm:text-5xl">Community feed</h1>
          <p className="mt-2 text-sm text-muted">Reflections, prayers, gatherings, and everyday moments from {data.organization.name}.</p>
        </div>
        <label className="field-label text-xs">
          Show
          <select className="field mt-1 min-w-48 bg-paper text-sm" value={filter} onChange={(event) => setFilter(event.target.value)}>
            <option value="all">All activity</option>
            <option value="organization">Entire organization</option>
            {data.groups.map((group) => <option value={group.id} key={group.id}>{group.name}</option>)}
          </select>
        </label>
      </div>
      <FeedComposer
        onCreated={(item) => item ? setItems((current) => [item, ...current]) : void load(false)}
        onPrayer={() => setPrayerOpen(true)}
      />
      {error && <div className="mt-4 flex items-center justify-between gap-4 rounded-xl border border-line bg-paper p-4" role="alert"><span className="text-sm">{error}</span><button className="secondary-button" onClick={() => void load(false)}><RefreshCw size={15} /> Retry</button></div>}
      {loading ? (
        <div className="mt-5 space-y-4" aria-busy="true" aria-label="Loading community feed">{[1, 2, 3].map((item) => <div className="h-52 animate-pulse rounded-2xl bg-paper" key={item} />)}</div>
      ) : items.length ? (
        <div className="mt-5 space-y-5">{items.map((item) => <FeedCard key={item.id} item={item} onUpdate={update} onRemove={() => setItems((current) => current.filter((entry) => entry.id !== item.id))} />)}</div>
      ) : (
        <div className="mt-5 grid min-h-64 place-items-center border-y border-line text-center" role="status"><div><MessageCircle className="mx-auto text-olive" /><h2 className="mt-4 font-display text-2xl">The conversation starts here</h2><p className="mt-2 text-sm text-muted">Share an update, a photo, or a prayer with your community.</p></div></div>
      )}
      {cursor && <button className="secondary-button mx-auto mt-6 flex" disabled={loadingMore} onClick={() => void load(true)}>{loadingMore ? "Loading…" : "Load more"}</button>}
      <p className="mt-5 flex items-center justify-center gap-2 text-xs text-muted"><Heart size={13} /> Visible only to signed-in members with the selected audience.</p>
      {prayerOpen && (
        <Modal title="Share a prayer request" onClose={() => setPrayerOpen(false)}>
          <PrayerForm onDone={() => { setPrayerOpen(false); void load(false); }} />
        </Modal>
      )}
    </section>
  );
}
