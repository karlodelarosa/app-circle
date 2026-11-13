import { Bookmark, Eye, Search, ShieldCheck } from "lucide-react";
import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useCircles } from "../AppContext";
import { Avatar } from "../components/Avatar";
import { FeedCard } from "../components/FeedCard";
import { getErrorMessage } from "../lib/errors";
import { getDemoFeedPreferenceIds, setDemoFeedPreference } from "../lib/demoFeedPreferences";
import { formatDate } from "../lib/format";
import { supabase } from "../lib/supabase";
import {
  getCommunityFeedItem,
  getCommunityMemberProfile,
  loadFeedModerationQueue,
  loadPersonallyHiddenFeedItems,
  resolveFeedReport,
  saveCommunityProfile,
  searchCommunityFeed,
  searchCommunityMembers,
  setFeedPersonallyHidden,
  setFeedSaved,
} from "../services/feed";
import type {
  CommunityFeedItem,
  CommunityMemberProfile,
  CommunityProfileVisibility,
  FeedModerationReport,
  PersonallyHiddenFeedItem,
} from "../types";

function PageState({ children }: { children: string }) {
  return <div className="paper-panel p-8 text-center text-sm text-muted" role="status">{children}</div>;
}

function demoProfile(personId: string, data: NonNullable<ReturnType<typeof useCircles>["data"]>): CommunityMemberProfile | undefined {
  const person = data.members.find((member) => member.id === personId);
  if (!person) return undefined;
  return {
    personId: person.id,
    fullName: person.fullName,
    avatarUrl: person.avatarUrl,
    bio: person.id === data.currentUser.personId ? "Helping people make room for honest faith and shared life." : undefined,
    bioVisibility: "organization",
    joinDateVisibility: "organization",
    circles: data.group && (person.id === data.currentUser.personId || person.id === "member-2")
      ? [{ id: data.group.id, name: data.group.name, role: person.role }]
      : [],
    recentItems: (data.communityFeed ?? []).filter((item) => item.authorPersonId === person.id),
    canEdit: person.id === data.currentUser.personId,
  };
}

export function MembersPage() {
  const { data, demoMode } = useCircles();
  const [query, setQuery] = useState("");
  const [members, setMembers] = useState<CommunityMemberProfile[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!data) return;
    let active = true;
    const timer = window.setTimeout(async () => {
      setLoading(true); setError("");
      try {
        const results = demoMode || !supabase
          ? data.members
              .filter((member) => member.fullName.toLowerCase().includes(query.trim().toLowerCase()))
              .map((member) => demoProfile(member.id, data)!)
          : await searchCommunityMembers(supabase, query);
        if (active) setMembers(results);
      } catch (cause) { if (active) setError(getErrorMessage(cause, "Members could not be loaded.")); }
      finally { if (active) setLoading(false); }
    }, query ? 250 : 0);
    return () => { active = false; window.clearTimeout(timer); };
  }, [data, demoMode, query]);

  return <section className="space-y-6">
    <header className="max-w-2xl"><p className="eyebrow">Your organization</p><h1 className="font-display text-4xl sm:text-5xl">Members</h1><p className="mt-2 text-muted">Find the people sharing life in your community. Private contact details are never shown here.</p></header>
    <label className="relative block max-w-xl"><span className="sr-only">Search members</span><Search className="pointer-events-none absolute left-4 top-1/2 -translate-y-1/2 text-muted" size={18} /><input className="field min-h-12 pl-11" type="search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search members" /></label>
    {error ? <p className="form-error" role="alert">{error}</p> : loading ? <PageState>Loading members…</PageState> : members.length === 0 ? <PageState>No members match your search.</PageState> :
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">{members.map((member) => <Link key={member.personId} to={`/members/${member.personId}`} className="paper-panel flex min-h-24 items-center gap-4 p-4 transition hover:-translate-y-0.5 hover:border-olive/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-olive"><Avatar person={{ id: member.personId, fullName: member.fullName, avatarUrl: member.avatarUrl }} /><span className="min-w-0"><strong className="block truncate font-medium">{member.fullName}</strong><span className="mt-1 block text-xs text-muted">{member.circles.map((circle) => circle.name).join(" · ") || "Organization member"}</span></span></Link>)}</div>}
  </section>;
}

export function MemberProfilePage() {
  const { personId = "" } = useParams();
  const { data, demoMode } = useCircles();
  const [profile, setProfile] = useState<CommunityMemberProfile>();
  const [editing, setEditing] = useState(false);
  const [bio, setBio] = useState("");
  const [bioVisibility, setBioVisibility] = useState<CommunityProfileVisibility>("organization");
  const [joinVisibility, setJoinVisibility] = useState<CommunityProfileVisibility>("organization");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!data || !personId) return;
    let active = true;
    void (async () => {
      setLoading(true); setError("");
      try {
        const value = demoMode || !supabase ? demoProfile(personId, data) : await getCommunityMemberProfile(supabase, personId);
        if (!value) throw new Error("This member profile is not available.");
        if (active) { setProfile(value); setBio(value.bio ?? ""); setBioVisibility(value.bioVisibility); setJoinVisibility(value.joinDateVisibility); }
      } catch (cause) { if (active) setError(getErrorMessage(cause, "This member profile is not available.")); }
      finally { if (active) setLoading(false); }
    })();
    return () => { active = false; };
  }, [data, demoMode, personId]);

  const save = async () => {
    if (!profile) return;
    setSaving(true); setError("");
    try {
      if (supabase && !demoMode) await saveCommunityProfile(supabase, { bio, bioVisibility, joinDateVisibility: joinVisibility });
      setProfile({ ...profile, bio: bio.trim() || undefined, bioVisibility, joinDateVisibility: joinVisibility }); setEditing(false);
    } catch (cause) { setError(getErrorMessage(cause, "Your community profile could not be saved.")); }
    finally { setSaving(false); }
  };

  if (loading) return <PageState>Loading profile…</PageState>;
  if (error && !profile) return <p className="form-error" role="alert">{error}</p>;
  if (!profile) return null;
  return <section className="space-y-7">
    <header className="paper-panel overflow-hidden"><div className="h-24 bg-gradient-to-r from-olive/20 via-sage/20 to-clay/20" /><div className="p-5 sm:p-7"><div className="flex flex-wrap items-start gap-4"><Avatar person={{ id: profile.personId, fullName: profile.fullName, avatarUrl: profile.avatarUrl }} /><div className="min-w-0 flex-1"><p className="eyebrow">Community profile</p><h1 className="font-display text-4xl">{profile.fullName}</h1><div className="mt-2 flex flex-wrap gap-2">{profile.circles.map((circle) => <span key={circle.id} className="role-label">{circle.name}{circle.role ? ` · ${circle.role}` : ""}</span>)}</div></div>{profile.canEdit && <button type="button" className="secondary-button" onClick={() => setEditing((value) => !value)}>{editing ? "Cancel" : "Edit profile"}</button>}</div>
      {editing ? <div className="mt-6 grid gap-4 border-t border-line pt-5"><label className="field-label">Community bio<textarea aria-label="Community bio" className="field min-h-28 resize-y" maxLength={500} value={bio} onChange={(event) => setBio(event.target.value)} /></label><div className="grid gap-4 sm:grid-cols-2"><label className="field-label">Who can see your bio<select className="field" value={bioVisibility} onChange={(event) => setBioVisibility(event.target.value as CommunityProfileVisibility)}><VisibilityOptions /></select></label><label className="field-label">Who can see your join date<select className="field" value={joinVisibility} onChange={(event) => setJoinVisibility(event.target.value as CommunityProfileVisibility)}><VisibilityOptions /></select></label></div><button type="button" className="primary-button justify-self-start" disabled={saving} onClick={() => void save()}>{saving ? "Saving…" : "Save profile"}</button></div> : <div className="mt-5 space-y-2">{profile.bio ? <p className="max-w-2xl whitespace-pre-line leading-7 text-[#45483F]">{profile.bio}</p> : <p className="text-sm text-muted">No community bio shared.</p>}{profile.joinDate && <p className="text-xs text-muted">Part of this community since {formatDate(profile.joinDate)}</p>}</div>}
      {error && <p className="form-error mt-4" role="alert">{error}</p>}</div></header>
    <div><h2 className="font-display text-3xl">Recent activity</h2>{profile.recentItems.length ? <div className="mt-4 space-y-4">{profile.recentItems.map((item) => <FeedCard key={item.id} item={item} onUpdate={(next) => setProfile({ ...profile, recentItems: profile.recentItems.map((current) => current.id === next.id ? next : current) })} onRemove={() => setProfile({ ...profile, recentItems: profile.recentItems.filter((current) => current.id !== item.id) })} />)}</div> : <div className="mt-4"><PageState>No recent activity is visible to you.</PageState></div>}</div>
  </section>;
}

function VisibilityOptions() { return <><option value="organization">Entire organization</option><option value="shared_circle">Shared Circles only</option><option value="hidden">Only me</option></>; }

export function FeedItemPage() {
  const { feedItemId = "" } = useParams();
  const { data, demoMode } = useCircles();
  const [item, setItem] = useState<CommunityFeedItem>();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  useEffect(() => { if (!data || !feedItemId) return; let active = true; void (async () => { try { const hiddenIds = new Set(getDemoFeedPreferenceIds("hidden")); const value = demoMode || !supabase ? (data.communityFeed ?? []).find((entry) => entry.id === feedItemId && !hiddenIds.has(entry.id)) : await getCommunityFeedItem(supabase, feedItemId); if (!value) throw new Error("This community post is not available."); if (active) setItem(value); } catch (cause) { if (active) setError(getErrorMessage(cause, "This community post is not available.")); } finally { if (active) setLoading(false); } })(); return () => { active = false; }; }, [data, demoMode, feedItemId]);
  if (loading) return <PageState>Loading community post…</PageState>;
  return <section className="mx-auto max-w-2xl space-y-5"><header><p className="eyebrow">Private community</p><h1 className="font-display text-4xl">Community post</h1></header>{error || !item ? <p className="form-error" role="alert">{error || "This community post was removed."}</p> : <FeedCard item={item} onUpdate={setItem} onRemove={() => { setItem(undefined); setError("This community post was removed."); }} />}</section>;
}

export function CommunitySettingsPage() {
  const { data, demoMode } = useCircles();
  const [saved, setSaved] = useState<CommunityFeedItem[]>([]);
  const [hidden, setHidden] = useState<PersonallyHiddenFeedItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  useEffect(() => { if (!data) return; let active = true; void (async () => { try { const feed = data.communityFeed ?? []; const savedIds = new Set(getDemoFeedPreferenceIds("saved")); const hiddenIds = new Set(getDemoFeedPreferenceIds("hidden")); const [savedItems, hiddenItems] = demoMode || !supabase ? [feed.filter((item) => item.savedByMe || savedIds.has(item.id)), feed.filter((item) => hiddenIds.has(item.id)).map((item) => ({ id: item.id, type: item.type, title: item.title, body: item.body, authorName: item.authorName, hiddenAt: new Date().toISOString() }))] : await Promise.all([searchCommunityFeed(supabase, { savedOnly: true }), loadPersonallyHiddenFeedItems(supabase)]); if (active) { setSaved(savedItems); setHidden(hiddenItems); } } catch (cause) { if (active) setError(getErrorMessage(cause, "Community preferences could not be loaded.")); } finally { if (active) setLoading(false); } })(); return () => { active = false; }; }, [data, demoMode]);
  const unhide = async (item: PersonallyHiddenFeedItem) => { try { if (supabase && !demoMode) await setFeedPersonallyHidden(supabase, item.id, false); else setDemoFeedPreference("hidden", item.id, false); setHidden((items) => items.filter((entry) => entry.id !== item.id)); } catch (cause) { setError(getErrorMessage(cause, "This post could not be restored.")); } };
  const unsave = async (item: CommunityFeedItem) => { try { if (supabase && !demoMode) await setFeedSaved(supabase, item.id, false); else setDemoFeedPreference("saved", item.id, false); setSaved((items) => items.filter((entry) => entry.id !== item.id)); } catch (cause) { setError(getErrorMessage(cause, "This saved post could not be removed.")); } };
  return <section className="space-y-7"><header><p className="eyebrow">Your feed</p><h1 className="font-display text-4xl sm:text-5xl">Community settings</h1><p className="mt-2 text-muted">Saved and hidden posts are private to you.</p></header>{error && <p className="form-error" role="alert">{error}</p>}{loading ? <PageState>Loading your preferences…</PageState> : <div className="grid gap-6 lg:grid-cols-2"><PreferencePanel icon={Bookmark} title="Saved posts" empty="You have no saved posts.">{saved.map((item) => <div key={item.id} className="flex items-center justify-between gap-3 border-t border-line py-3 first:border-0"><Link className="min-w-0 truncate text-sm hover:text-olive hover:underline" to={`/feed/${item.id}`}>{item.title || item.body || "Community post"}</Link><button className="text-button" onClick={() => void unsave(item)}>Remove</button></div>)}</PreferencePanel><PreferencePanel icon={Eye} title="Hidden posts" empty="You have no hidden posts.">{hidden.map((item) => <div key={item.id} className="flex items-center justify-between gap-3 border-t border-line py-3 first:border-0"><span className="min-w-0"><strong className="block truncate text-sm font-medium">{item.title || item.body || "Community post"}</strong><span className="text-xs text-muted">By {item.authorName}</span></span><button className="text-button" onClick={() => void unhide(item)}>Undo hide</button></div>)}</PreferencePanel></div>}</section>;
}

function PreferencePanel({ icon: Icon, title, empty, children }: { icon: typeof Bookmark; title: string; empty: string; children: React.ReactNode }) { const hasChildren = Array.isArray(children) ? children.length > 0 : Boolean(children); return <section className="paper-panel p-5"><h2 className="flex items-center gap-2 font-display text-2xl"><Icon size={19} className="text-olive" />{title}</h2><div className="mt-3">{hasChildren ? children : <p className="py-5 text-sm text-muted">{empty}</p>}</div></section>; }

export function ModerationPage() {
  const { demoMode } = useCircles();
  const [reports, setReports] = useState<FeedModerationReport[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  useEffect(() => { let active = true; void (async () => { try { const value = demoMode || !supabase ? [] : await loadFeedModerationQueue(supabase); if (active) setReports(value); } catch (cause) { if (active) setError(getErrorMessage(cause, "Reports could not be loaded.")); } finally { if (active) setLoading(false); } })(); return () => { active = false; }; }, [demoMode]);
  const resolve = async (report: FeedModerationReport, status: "resolved" | "dismissed") => { try { if (supabase && !demoMode) await resolveFeedReport(supabase, report.id, status); setReports((items) => items.filter((item) => item.id !== report.id)); } catch (cause) { setError(getErrorMessage(cause, "The report could not be updated.")); } };
  return <section className="space-y-6"><header><p className="eyebrow">Safety</p><h1 className="font-display text-4xl sm:text-5xl">Moderation queue</h1><p className="mt-2 text-muted">Review reports only for the organization or Circles you lead. Every resolution is recorded.</p></header>{error && <p className="form-error" role="alert">{error}</p>}{loading ? <PageState>Loading reports…</PageState> : reports.length === 0 ? <PageState>No open reports.</PageState> : <div className="space-y-4">{reports.map((report) => <article key={report.id} className="paper-panel p-5"><div className="flex items-start gap-3"><ShieldCheck className="text-olive" /><div className="min-w-0 flex-1"><h2 className="font-medium capitalize">{report.reason.replace("_", " ")}</h2><p className="mt-1 text-sm text-muted">Reported by {report.reporterName}</p>{report.note && <p className="mt-3 text-sm leading-6">{report.note}</p>}{report.item && <Link className="mt-3 inline-block text-sm text-olive underline" to={`/feed/${report.item.id}`}>Open reported post</Link>}<div className="mt-4 flex flex-wrap gap-2"><button className="primary-button" onClick={() => void resolve(report, "resolved")}>Mark resolved</button><button className="secondary-button" onClick={() => void resolve(report, "dismissed")}>Dismiss report</button></div></div></div></article>)}</div>}</section>;
}
