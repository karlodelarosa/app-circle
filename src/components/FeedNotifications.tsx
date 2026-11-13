import { Bell, Heart, MessageCircle, ShieldCheck, Sparkles } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { useCircles } from "../AppContext";
import { relativeDate } from "../lib/format";
import { supabase } from "../lib/supabase";
import { loadFeedNotifications, markFeedNotificationsRead } from "../services/feed";
import type { FeedNotification } from "../types";

const activityLabel = (notice: FeedNotification) => {
  const others = notice.actorCount > 1 ? ` and ${notice.actorCount - 1} ${notice.actorCount === 2 ? "other" : "others"}` : "";
  if (notice.kind === "comment") return `${notice.actorName}${others} commented on your post`;
  if (notice.kind === "pray") return `${notice.actorName}${others} prayed for your request`;
  if (notice.kind === "prayer_update") return `${notice.actorName}${others} updated a prayer you follow`;
  if (notice.kind === "report_resolved") return `${notice.actorName} reviewed your community report`;
  if (notice.kind === "reaction") return `${notice.actorName}${others} reacted to your post`;
  return `${notice.actorName}${others} liked your post`;
};

const noticeHref = (notice: FeedNotification) => `/feed/${notice.feedItemId}${notice.targetCommentId ? `#comment-${notice.targetCommentId}` : notice.prayerUpdateId ? `#prayer-update-${notice.prayerUpdateId}` : ""}`;

export function FeedNotifications() {
  const { demoMode } = useCircles();
  const [notices, setNotices] = useState<FeedNotification[]>([]);
  const [open, setOpen] = useState(false);
  const panelRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!supabase || demoMode) return;
    let active = true;
    loadFeedNotifications(supabase).then((items) => active && setNotices(items)).catch(() => undefined);
    return () => { active = false; };
  }, [demoMode]);

  useEffect(() => {
    if (!open) return;
    const close = (event: PointerEvent) => {
      if (!panelRef.current?.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener("pointerdown", close);
    return () => document.removeEventListener("pointerdown", close);
  }, [open]);

  const unread = notices.filter((notice) => !notice.readAt).length;
  const toggle = async () => {
    const next = !open;
    setOpen(next);
    if (next && supabase && !demoMode) {
      const latest = await loadFeedNotifications(supabase).catch(() => notices);
      const hasUnread = latest.some((notice) => !notice.readAt);
      setNotices(latest.map((notice) => ({ ...notice, readAt: hasUnread ? notice.readAt ?? new Date().toISOString() : notice.readAt })));
      if (hasUnread) await markFeedNotificationsRead(supabase).catch(() => undefined);
    }
  };

  return (
    <div className="relative" ref={panelRef}>
      <button type="button" className="icon-button relative" aria-label={unread ? `Notifications, ${unread} unread` : "Notifications"} aria-haspopup="menu" aria-expanded={open} onClick={() => void toggle()}>
        <Bell size={18} />
        {unread > 0 && <span className="absolute -right-1 -top-1 min-w-4 rounded-full bg-olive px-1 text-center text-[10px] leading-4 text-paper" aria-hidden="true">{unread > 9 ? "9+" : unread}</span>}
      </button>
      {open && (
        <div role="menu" className="absolute right-0 top-[calc(100%+.5rem)] z-50 w-[min(22rem,calc(100vw-2rem))] overflow-hidden rounded-2xl border border-line bg-paper shadow-quiet">
          <div className="border-b border-line px-4 py-3"><h2 className="font-display text-2xl">Activity</h2></div>
          {notices.length ? <div className="max-h-96 divide-y divide-line overflow-y-auto">
            {notices.map((notice) => <Link key={notice.id} to={noticeHref(notice)} role="menuitem" onClick={() => setOpen(false)} className="flex min-h-14 gap-3 px-4 py-3 hover:bg-parchment focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-olive">
              {notice.kind === "comment" ? <MessageCircle size={16} className="mt-1 shrink-0 text-olive" /> : notice.kind === "prayer_update" ? <Sparkles size={16} className="mt-1 shrink-0 text-olive" /> : notice.kind === "report_resolved" ? <ShieldCheck size={16} className="mt-1 shrink-0 text-olive" /> : <Heart size={16} className="mt-1 shrink-0 text-olive" />}
              <div><p className="text-sm leading-5">{activityLabel(notice)}</p><p className="mt-1 text-xs text-muted">{relativeDate(notice.createdAt)}</p></div>
            </Link>)}
          </div> : <p className="px-4 py-8 text-center text-sm text-muted">No activity yet.</p>}
        </div>
      )}
    </div>
  );
}
