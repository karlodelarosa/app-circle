import { useEffect, useRef, useState, type FormEvent } from "react";
import { CalendarDays, ChevronRight, Images, Megaphone, Plus, Quote, UsersRound, X } from "lucide-react";
import { useCircles } from "../AppContext";
import { supabase } from "../lib/supabase";
import { getErrorMessage } from "../lib/errors";
import { saveCirclePublicListing, unpublishCirclePublicListing } from "../services/circles";
import type { ContentAssignment, ContentAssignmentType, Group, Testimony } from "../types";
import { Modal } from "../components/Modal";

type Composer = "testimony" | "gallery" | "announcement" | null;
const slugify = (value: string) =>
  value
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
export function ContentPage() {
  const { data, demoMode, refresh } = useCircles();
  const [composer, setComposer] = useState<Composer>(null);
  const [form, setForm] = useState({
    title: "",
    body: "",
    author: "",
    description: "",
    audience: "members" as "members" | "public",
  });
  const [file, setFile] = useState<File | null>(null);
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const [circleEditor, setCircleEditor] = useState<Group | null>(null);
  const [circleDescription, setCircleDescription] = useState("");
  const [circleCover, setCircleCover] = useState<File | null>(null);
  const [reviewing,setReviewing]=useState<Testimony | null>(null);
  const [reviewName,setReviewName]=useState("");
  const [targetGroupId,setTargetGroupId]=useState("");
  const [assignmentType,setAssignmentType]=useState<"all"|ContentAssignmentType>("all");
  const [assignmentGroup,setAssignmentGroup]=useState("all");
  const [assignmentReview,setAssignmentReview]=useState<ContentAssignment|null>(null);
  const [assignmentTarget,setAssignmentTarget]=useState("");
  const [assignmentError,setAssignmentError]=useState("");
  const dialogRef = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    if (composer && !dialogRef.current?.open) dialogRef.current?.showModal();
  }, [composer]);
  if (!data) return null;
  const manageableGroups=data.groups.filter((group)=>data.currentUser.role==="admin"||group.role==="leader");
  const hasSingleLeaderDestination=data.currentUser.role!=="admin"&&manageableGroups.length===1;
  const beginComposer=(kind:Exclude<Composer,null>)=>{
    setMessage("");
    setTargetGroupId(hasSingleLeaderDestination?manageableGroups[0].id:"");
    setComposer(kind);
  };
  const assignmentItems=data.contentAssignments.filter((item)=>{
    const matchesType=assignmentType==="all"||item.type===assignmentType;
    const matchesGroup=assignmentGroup==="all"||
      (assignmentGroup==="unreviewed"&&!item.confirmedAt)||
      (assignmentGroup==="organization"&&!item.groupId)||
      item.groupId===assignmentGroup;
    return matchesType&&matchesGroup;
  });
  const openAssignment=(item:ContentAssignment)=>{setAssignmentReview(item);setAssignmentTarget(item.groupId||"organization");setAssignmentError("")};
  const saveAssignment=async()=>{if(!supabase||!assignmentReview)return;setBusy(true);setAssignmentError("");const target=assignmentTarget==="organization"?null:assignmentTarget;const result=await supabase.rpc("review_circle_content_assignment",{p_content_type:assignmentReview.type,p_content_id:assignmentReview.id,p_target_cell_group_id:target});if(result.error)setAssignmentError(result.error.message);else{setAssignmentReview(null);setMessage(`${assignmentReview.title} assignment saved.`);await refresh()}setBusy(false)};
  const pendingTestimonies=data.testimonies.filter((item)=>item.status==="draft");
  const publishTestimony=async(event:FormEvent)=>{event.preventDefault();if(!reviewing||!supabase)return;setBusy(true);const result=await supabase.from("circle_testimonies").update({author_display_name:reviewName.trim(),status:"published",published_at:new Date().toISOString(),updated_at:new Date().toISOString()}).eq("id",reviewing.id);setBusy(false);if(result.error)setMessage(result.error.message);else{setReviewing(null);setMessage("Testimony published to the public community page.");await refresh()}};
  const editCircleProfile = (group: Group) => {
    const listing = data.publicCircleListings.find((item) => item.groupId === group.id);
    setCircleDescription(listing?.description || group.description || "");
    setCircleCover(null);
    setMessage("");
    setCircleEditor(group);
  };
  const publishCircleProfile = async (event: FormEvent) => {
    event.preventDefault();
    if (!circleEditor) return;
    setBusy(true);
    setMessage("");
    try {
      if (!demoMode && supabase) {
        await saveCirclePublicListing(supabase, data.organization.id, circleEditor, {
          description: circleDescription,
          coverFile: circleCover || undefined,
          current: data.publicCircleListings.find((item) => item.groupId === circleEditor.id),
        });
        await refresh();
      }
      setCircleEditor(null);
      setMessage(`${circleEditor.name} is published in Join a Circle.`);
    } catch (cause) {
      setMessage(getErrorMessage(cause, "The Circle profile could not be published."));
    } finally {
      setBusy(false);
    }
  };
  const unpublishCircleProfile = async (group: Group) => {
    const listing = data.publicCircleListings.find((item) => item.groupId === group.id);
    if (!listing || !window.confirm(`Remove ${group.name} from Join a Circle? Existing interest records will be kept.`)) return;
    setBusy(true);
    try {
      if (!demoMode && supabase) {
        await unpublishCirclePublicListing(supabase, listing.id);
        await refresh();
      }
      setMessage(`${group.name} is no longer public.`);
    } catch (cause) {
      setMessage(getErrorMessage(cause, "The Circle profile could not be unpublished."));
    } finally {
      setBusy(false);
    }
  };
  const publishSpace = async () => {
    if (demoMode || !supabase) {
      setMessage("Public community page is published in demo mode.");
      return;
    }
    setBusy(true);
    const { error } = await supabase.from("circle_public_spaces").upsert({
      organization_id: data.organization.id,
      introduction:
        "A welcoming place to gather, share honest stories, and grow in faith together.",
      hero_title: "There is room for you here.",
      is_published: true,
    });
    setBusy(false);
    setMessage(error ? error.message : "Community page published.");
  };
  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setMessage("");
    try {
      if (!targetGroupId) throw new Error("Choose where this content belongs.");
      if (targetGroupId === "organization" && composer !== "announcement")
        throw new Error("Only announcements can be published to the entire organization.");
      if (!demoMode && supabase && data.group) {
        const common = {
          organization_id: data.organization.id,
          cell_group_id: targetGroupId === "organization" ? null : targetGroupId,
          created_by: data.currentUser.id,
        };
        if (composer === "testimony") {
          const { error } = await supabase.from("circle_testimonies").insert({
            ...common,
            public_slug: `${slugify(form.title)}-${Date.now().toString(36)}`,
            title: form.title,
            body: form.body,
            author_display_name: form.author,
            status: "published",
            published_at: new Date().toISOString(),
          });
          if (error) throw error;
        } else if (composer === "announcement") {
          const { error } = await supabase.from("circle_announcements").insert({
            ...common,
            title: form.title,
            body: form.body,
            published_at: new Date().toISOString(),
            is_public: form.audience === "public",
          });
          if (error) throw error;
        } else if (composer === "gallery") {
          let imageUrl = "";
          if (file) {
            const path = `${data.organization.id}/${crypto.randomUUID()}-${file.name.replace(/[^a-zA-Z0-9.-]/g, "-")}`;
            const upload = await supabase.storage
              .from("circle-public-media")
              .upload(path, file);
            if (upload.error) throw upload.error;
            imageUrl = supabase.storage
              .from("circle-public-media")
              .getPublicUrl(path).data.publicUrl;
          }
          const { data: gallery, error } = await supabase
            .from("circle_galleries")
            .insert({
              ...common,
              public_slug: `${slugify(form.title)}-${Date.now().toString(36)}`,
              title: form.title,
              description: form.description,
              cover_url: imageUrl || null,
              status: "published",
              published_at: new Date().toISOString(),
            })
            .select("id")
            .single();
          if (error) throw error;
          if (imageUrl) {
            const photo = await supabase.from("circle_gallery_photos").insert({
              organization_id: data.organization.id,
              gallery_id: gallery.id,
              image_url: imageUrl,
              alt_text: form.description || form.title,
              is_published: true,
            });
            if (photo.error) throw photo.error;
          }
        }
        await refresh();
      }
      setMessage(
        composer === "announcement"
          ? `Announcement published to ${form.audience === "public" ? "the member dashboard and public Updates" : "the member dashboard"}.`
          : `${composer === "gallery" ? "Gallery" : "Testimony"} published to the public community page.`,
      );
      setComposer(null);
      setForm({ title: "", body: "", author: "", description: "", audience: "members" });
      setFile(null);
      setTargetGroupId("");
    } catch (c) {
      setMessage(getErrorMessage(c, "Content could not be published."));
    } finally {
      setBusy(false);
    }
  };
  return (
    <div>
      <div className="page-heading">
        <div>
          <p className="page-kicker">Community publishing</p>
          <h1>Publish</h1>
          <p>
            Publish only what is meant for your organization’s public community
            space.
          </p>
        </div>
        <button
          className="secondary-button"
          disabled={busy}
          onClick={() => void publishSpace()}
        >
          {busy ? "Publishing…" : "Publish community page"}
        </button>
      </div>
      {message && !composer && (
        <p
          role="status"
          className="mt-5 rounded-xl bg-paper p-4 text-sm text-muted"
        >
          {message}
        </p>
      )}
      {data.currentUser.role === "admin" && (
        <section className="mt-10 border-t border-line pt-8">
          <div className="section-heading">
            <div>
              <h2>Circle profiles</h2>
              <p>Choose which Circles visitors may learn about and contact.</p>
            </div>
          </div>
          <div className="divide-y divide-line border-y border-line">
            {data.groups.map((group) => {
              const listing = data.publicCircleListings.find((item) => item.groupId === group.id);
              return (
                <div key={group.id} className="flex flex-col gap-4 py-5 sm:flex-row sm:items-center">
                  <span className="grid h-12 w-12 shrink-0 place-items-center rounded-full bg-sage text-olive"><UsersRound size={19} /></span>
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <h3 className="font-display text-2xl">{group.name}</h3>
                      <span className={`rounded-full px-2.5 py-1 text-[10px] ${listing?.isPublished ? "bg-sage text-olive" : "bg-paper text-muted"}`}>
                        {listing?.isPublished ? "Public" : "Private"}
                      </span>
                    </div>
                    <p className="mt-1 line-clamp-2 text-sm text-muted">{listing?.description || group.description || "Add a public description before publishing."}</p>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    {listing?.isPublished && (
                      <a className="secondary-button" target="_blank" rel="noreferrer" href={`/${data.organization.slug}/circles/${listing.slug}?browse=1`}>View</a>
                    )}
                    <button type="button" className="primary-button" onClick={() => editCircleProfile(group)} disabled={busy}>
                      {listing?.isPublished ? "Edit profile" : "Publish profile"}
                    </button>
                    {listing?.isPublished && (
                      <button type="button" className="secondary-button" onClick={() => void unpublishCircleProfile(group)} disabled={busy}>Unpublish</button>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </section>
      )}
      {data.currentUser.role === "admin" && (
        <section className="mt-10 border-t border-line pt-8">
          <div className="section-heading">
            <div>
              <h2>Content assignments</h2>
              <p>Confirm which Circle owns each item before it appears in that Circle’s private views.</p>
            </div>
            <span className="role-label">{data.contentAssignments.filter((item)=>!item.confirmedAt).length} need review</span>
          </div>
          <div className="mt-5 grid gap-3 sm:grid-cols-2">
            <label className="field-label">Content type<select className="field" value={assignmentType} onChange={(event)=>setAssignmentType(event.target.value as "all"|ContentAssignmentType)}><option value="all">All content</option><option value="gathering">Gatherings</option><option value="gallery">Galleries</option><option value="testimony">Testimonies</option><option value="announcement">Announcements</option></select></label>
            <label className="field-label">Assignment<select className="field" value={assignmentGroup} onChange={(event)=>setAssignmentGroup(event.target.value)}><option value="all">All assignments</option><option value="unreviewed">Needs review</option><option value="organization">Entire organization</option>{data.groups.map((group)=><option key={group.id} value={group.id}>{group.name}</option>)}</select></label>
          </div>
          <div className="mt-5 divide-y divide-line border-y border-line">
            {assignmentItems.map((item)=><div key={`${item.type}-${item.id}`} className="grid gap-3 py-4 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center"><div className="min-w-0"><div className="flex flex-wrap items-center gap-2"><span className="role-label capitalize">{item.type}</span>{!item.confirmedAt&&<span className="rounded-full bg-[#F4E5C7] px-2.5 py-1 text-[10px] text-[#72551E]">Needs review</span>}</div><h3 className="mt-2 truncate font-medium">{item.title}</h3><p className="mt-1 text-xs text-muted">Currently assigned to {item.groupName||"Entire organization"}{item.hasParticipation?" · Participation recorded":""}</p></div><button className={item.confirmedAt?"secondary-button":"primary-button"} onClick={()=>openAssignment(item)}>{item.confirmedAt?"Change assignment":"Review assignment"}</button></div>)}
            {!assignmentItems.length&&<p className="py-6 text-sm text-muted">No content matches these filters.</p>}
          </div>
        </section>
      )}
      <section className="mt-10 border-t border-line pt-8"><div className="section-heading"><div><h2>Pending testimonies</h2><p>Review stories submitted by members of {data.group?.name||"this Circle"}.</p></div></div>{pendingTestimonies.length?<div className="divide-y divide-line border-y border-line">{pendingTestimonies.map(item=><div key={item.id} className="flex flex-col gap-4 py-5 sm:flex-row sm:items-center"><div className="min-w-0 flex-1"><h3 className="font-display text-2xl">{item.title}</h3><p className="mt-1 text-sm text-muted">Submitted by {item.authorName}</p><p className="mt-2 line-clamp-2 text-sm leading-6 text-muted">{item.body}</p></div><button className="primary-button" onClick={()=>{setReviewing(item);setReviewName(item.authorName)}}>Review and publish</button></div>)}</div>:<p className="border-y border-line py-6 text-sm text-muted">No testimonies are waiting for review.</p>}</section>
      <div className="mt-9 grid gap-5 md:grid-cols-2">
        <ContentCard
          icon={Quote}
          title="Testimonies"
          description="Share approved stories with an intentional public author name."
          destination="Public homepage and Testimonies"
          count={data.testimonies.filter((item) => item.status === "published").length}
          onAdd={() => beginComposer("testimony")}
        />
        <ContentCard
          icon={Images}
          title="Galleries"
          description="Publish a standalone photo album that remains easy to find later."
          destination="Public homepage and Gallery"
          count={data.galleries.length}
          onAdd={() => beginComposer("gallery")}
        />
        <ContentCard
          icon={CalendarDays}
          title="Public gatherings"
          description="Visibility and guest RSVP are managed from each gathering."
          destination="Public Gatherings"
          count={data.meetings.filter((m) => m.visibility === "public").length}
        />
        <ContentCard
          icon={Megaphone}
          title="Announcements"
          description="Share a timely note with members, with optional public visibility."
          destination="Member dashboard; public Updates when enabled"
          count={data.announcements.length}
          onAdd={() => beginComposer("announcement")}
        />
      </div>
      {composer && (
        <dialog
          ref={dialogRef}
          aria-labelledby="content-composer-title"
          className="content-composer-dialog m-auto w-[min(42rem,calc(100%-2rem))] overflow-hidden rounded-[1.75rem] border border-line bg-paper p-0 text-ink shadow-quiet backdrop:bg-ink/55 backdrop:backdrop-blur-sm"
          onCancel={(event) => {
            event.preventDefault();
            if (!busy) setComposer(null);
          }}
          onMouseDown={(event) => {
            if (event.target === event.currentTarget && !busy)
              setComposer(null);
          }}
        >
          <form
            onSubmit={submit}
            className="content-composer-form flex flex-col"
          >
            <header className="shrink-0 flex items-start justify-between border-b border-line px-6 py-5 sm:px-8">
              <div>
                <p className="text-xs text-muted">Community publishing</p>
                <h2
                  id="content-composer-title"
                  className="mt-1 font-display text-3xl capitalize"
                >
                  New {composer}
                </h2>
              </div>
              <button
                type="button"
                onClick={() => setComposer(null)}
                className="icon-button"
                aria-label="Close"
                disabled={busy}
              >
                <X size={19} />
              </button>
            </header>
            <div className="min-h-0 flex-1 space-y-4 overflow-y-auto overscroll-contain px-6 py-6 sm:px-8">
              {message && (
                <p role="alert" className="form-error">
                  {message}
                </p>
              )}
              <div className="rounded-2xl border border-olive/20 bg-parchment p-4">
                <label className="field-label">
                  Destination
                  <select className="field" required value={targetGroupId} onChange={(event)=>setTargetGroupId(event.target.value)} disabled={hasSingleLeaderDestination}>
                    <option value="">Choose where this belongs</option>
                    {composer==="announcement"&&data.currentUser.role==="admin"&&<option value="organization">Entire organization</option>}
                    {manageableGroups.map((group)=><option key={group.id} value={group.id}>{group.name}</option>)}
                  </select>
                </label>
                <p className="mt-2 text-xs leading-5 text-muted">
                  {composer==="announcement"?"Circle announcements stay with that Circle. Organization announcements appear on the main dashboard and public Updates.":"This content will appear only in the selected Circle’s private detail view."}
                </p>
              </div>
              <label className="field-label">
                Title
                <input
                  className="field"
                  autoFocus
                  required
                  value={form.title}
                  onChange={(e) => setForm({ ...form, title: e.target.value })}
                />
              </label>
              {composer === "testimony" && (
                <>
                  <label className="field-label">
                    Public author name
                    <input
                      className="field"
                      required
                      value={form.author}
                      onChange={(e) =>
                        setForm({ ...form, author: e.target.value })
                      }
                    />
                  </label>
                  <label className="field-label">
                    Story
                    <textarea
                      className="field min-h-40"
                      required
                      value={form.body}
                      onChange={(e) =>
                        setForm({ ...form, body: e.target.value })
                      }
                    />
                  </label>
                </>
              )}
              {composer === "announcement" && (
                <>
                  <label className="field-label">
                    Announcement
                    <textarea
                      className="field min-h-32"
                      required
                      value={form.body}
                      onChange={(e) => setForm({ ...form, body: e.target.value })}
                    />
                  </label>
                  <fieldset>
                    <legend className="field-label">Audience</legend>
                    <div className="mt-2 grid gap-2 sm:grid-cols-2">
                      {[
                        ["members", "Members only", "Appears on the signed-in dashboard."],
                        ["public", "Members and public", "Also appears on public Updates."],
                      ].map(([value, label, help]) => (
                        <label key={value} className={`cursor-pointer rounded-2xl border p-4 ${form.audience === value ? "border-olive bg-parchment" : "border-line"}`}>
                          <span className="flex items-center gap-2 text-sm font-medium">
                            <input aria-label={label} type="radio" name="announcement-audience" value={value} checked={form.audience === value} onChange={() => setForm({ ...form, audience: value as "members" | "public" })} />
                            {label}
                          </span>
                          <span className="mt-2 block text-xs leading-5 text-muted">{help}</span>
                        </label>
                      ))}
                    </div>
                  </fieldset>
                </>
              )}
              {composer === "gallery" && (
                <>
                  <label className="field-label">
                    Description
                    <textarea
                      className="field min-h-24"
                      required
                      value={form.description}
                      onChange={(e) =>
                        setForm({ ...form, description: e.target.value })
                      }
                    />
                  </label>
                  <label className="field-label">
                    Cover photo
                    <input
                      className="field"
                      type="file"
                      accept="image/*"
                      onChange={(e) => setFile(e.target.files?.[0] || null)}
                    />
                  </label>
                </>
              )}
            </div>
            <footer className="content-composer-footer shrink-0 flex justify-end gap-3 border-t border-line bg-paper px-6 py-4 sm:px-8">
              <button
                type="button"
                className="secondary-button"
                onClick={() => setComposer(null)}
                disabled={busy}
              >
                Cancel
              </button>
              <button className="primary-button" disabled={busy}>
                {busy ? "Publishing…" : "Publish"}
              </button>
            </footer>
          </form>
        </dialog>
      )}
      {assignmentReview&&<Modal title="Review assignment" onClose={()=>setAssignmentReview(null)}><div><span className="role-label capitalize">{assignmentReview.type}</span><h3 className="mt-3 font-display text-3xl">{assignmentReview.title}</h3><p className="mt-3 text-sm leading-6 text-muted">Confirm the current destination or choose where this content truly belongs.</p><label className="field-label mt-6">Destination<select className="field" value={assignmentTarget} onChange={(event)=>setAssignmentTarget(event.target.value)}>{(assignmentReview.type==="announcement"||assignmentReview.type==="gathering")&&<option value="organization">Entire organization</option>}{data.groups.map((group)=><option key={group.id} value={group.id}>{group.name}</option>)}</select></label>{assignmentReview.type==="gathering"&&assignmentReview.hasParticipation&&assignmentTarget!==(assignmentReview.groupId||"organization")&&<p className="mt-3 rounded-xl bg-[#F4E5C7] p-4 text-sm leading-6 text-[#72551E]">This gathering already has RSVPs or attendance and cannot be moved. You can confirm its current destination.</p>}{assignmentError&&<p className="form-error mt-4" role="alert">{assignmentError}</p>}<button className="primary-button mt-6 w-full" disabled={busy||!assignmentTarget||(assignmentReview.type==="gathering"&&assignmentReview.hasParticipation&&assignmentTarget!==(assignmentReview.groupId||"organization"))} onClick={()=>void saveAssignment()}>{busy?"Saving…":assignmentTarget===assignmentReview.groupId||(!assignmentReview.groupId&&assignmentTarget==="organization")?"Confirm assignment":"Move and confirm"}</button></div></Modal>}
      {reviewing&&<dialog open className="fixed inset-0 z-50 m-auto w-[min(36rem,calc(100%-2rem))] rounded-[1.75rem] border border-line bg-paper p-0 text-ink shadow-quiet backdrop:bg-ink/55"><form onSubmit={publishTestimony} className="p-6 sm:p-8"><p className="text-xs text-olive">Testimony review</p><h2 className="mt-2 font-display text-3xl">{reviewing.title}</h2><p className="mt-4 whitespace-pre-line leading-7 text-muted">{reviewing.body}</p><label className="field-label mt-6">Public author name<input className="field" required value={reviewName} onChange={(e)=>setReviewName(e.target.value)}/></label><div className="mt-6 flex justify-end gap-3"><button type="button" className="secondary-button" onClick={()=>setReviewing(null)}>Keep pending</button><button className="primary-button" disabled={busy}>{busy?"Publishing…":"Publish testimony"}</button></div></form></dialog>}
      {circleEditor && (
        <div className="fixed inset-0 z-50 grid place-items-center bg-ink/55 p-4 backdrop-blur-sm" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !busy) setCircleEditor(null); }}>
          <form role="dialog" aria-modal="true" aria-labelledby="circle-profile-title" onSubmit={publishCircleProfile} className="max-h-[calc(100dvh-2rem)] w-full max-w-xl overflow-y-auto rounded-[1.75rem] border border-line bg-paper text-ink shadow-quiet">
            <header className="flex items-start justify-between border-b border-line px-6 py-5 sm:px-8">
              <div>
                <p className="text-xs text-muted">Join a Circle</p>
                <h2 id="circle-profile-title" className="mt-1 font-display text-3xl">{circleEditor.name}</h2>
              </div>
              <button type="button" className="icon-button" aria-label="Close" onClick={() => setCircleEditor(null)}><X size={19} /></button>
            </header>
            <div className="space-y-5 px-6 py-6 sm:px-8">
              <p className="text-sm leading-6 text-muted">Only this public description, cover, Circle name, and location will be shown. Member details remain private.</p>
              <label className="field-label">Public description
                <textarea className="field min-h-32" required maxLength={1200} value={circleDescription} onChange={(event) => setCircleDescription(event.target.value)} />
              </label>
              <label className="field-label">Cover photo (optional)
                <input className="field" type="file" accept="image/jpeg,image/png,image/webp" onChange={(event) => setCircleCover(event.target.files?.[0] || null)} />
              </label>
            </div>
            <footer className="flex justify-end gap-3 border-t border-line px-6 py-4 sm:px-8">
              <button type="button" className="secondary-button" onClick={() => setCircleEditor(null)} disabled={busy}>Cancel</button>
              <button className="primary-button" disabled={busy}>{busy ? "Publishing…" : "Publish profile"}</button>
            </footer>
          </form>
        </div>
      )}
      <section className="mt-12 border-t border-line pt-8">
        <div className="section-heading">
          <div>
            <h2>Recently published</h2>
            <p>Open the destination to confirm exactly where each item appears.</p>
          </div>
        </div>
        <div className="grid gap-8 lg:grid-cols-2">
          <div>
            <h3 className="font-display text-2xl">Announcements</h3>
            <div className="mt-3 divide-y divide-line border-y border-line">
              {data.announcements.slice(0, 3).map((item) => (
                <div key={item.id} className="py-4">
                  <div className="flex items-start justify-between gap-4">
                    <div>
                      <p className="font-medium">{item.title}</p>
                      <p className="mt-1 text-xs text-muted">{item.isPublic ? "Member dashboard · Public Updates" : "Member dashboard"}</p>
                    </div>
                    {item.isPublic && <a className="text-link shrink-0" target="_blank" rel="noreferrer" href={`/${data.organization.slug}/updates?browse=1`}>View <ChevronRight size={14} /></a>}
                  </div>
                </div>
              ))}
              {!data.announcements.length && <p className="py-5 text-sm text-muted">Published announcements will appear here.</p>}
            </div>
          </div>
          <div>
            <h3 className="font-display text-2xl">Galleries</h3>
            <div className="mt-3 divide-y divide-line border-y border-line">
              {data.galleries.slice(0, 3).map((gallery) => (
                <div key={gallery.id} className="flex items-center gap-4 py-4">
                  <img src={gallery.coverUrl || "/assets/devotional-table.webp"} alt="" className="h-14 w-16 rounded-xl object-cover" />
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-medium">{gallery.title}</p>
                    <p className="mt-1 text-xs text-muted">{gallery.photos.length} {gallery.photos.length === 1 ? "photo" : "photos"} · Public Gallery</p>
                  </div>
                  <a className="text-link shrink-0" target="_blank" rel="noreferrer" href={`/${data.organization.slug}/galleries/${gallery.slug}?browse=1`}>View <ChevronRight size={14} /></a>
                </div>
              ))}
              {!data.galleries.length && <p className="py-5 text-sm text-muted">Published galleries will appear here and on the public Gallery page.</p>}
            </div>
          </div>
        </div>
      </section>
      <section className="mt-10 border-t border-line pt-8">
        <h2 className="font-display text-3xl">Publishing boundary</h2>
        <p className="mt-3 max-w-2xl leading-7 text-muted">
          People details are private by default. Content appears publicly only
          after a leader or administrator publishes that specific record.
        </p>
      </section>
    </div>
  );
}
function ContentCard({
  icon: Icon,
  title,
  description,
  count,
  destination,
  onAdd,
}: {
  icon: typeof Quote;
  title: string;
  description: string;
  count?: number;
  destination: string;
  onAdd?: () => void;
}) {
  return (
    <article className="border-t border-line py-6">
      <div className="flex justify-between">
        <Icon className="text-olive" />
        {onAdd && (
          <button
            className="icon-button"
            onClick={onAdd}
            aria-label={`Add ${title}`}
          >
            <Plus />
          </button>
        )}
      </div>
      <div className="mt-8 flex items-end justify-between gap-5">
        <div>
          <h2 className="font-display text-3xl">{title}</h2>
          <p className="mt-2 text-sm leading-6 text-muted">{description}</p>
          <p className="mt-3 text-xs font-medium text-olive">Appears in: {destination}</p>
        </div>
        {count !== undefined && (
          <span className="font-display text-4xl text-olive">{count}</span>
        )}
      </div>
    </article>
  );
}
