import {
  ChevronRight,
  MapPin,
  ShieldCheck,
  BadgeCheck,
  KeyRound,
  Copy,
  History,
  Plus,
  Images,
  Megaphone,
  Quote,
  UserPlus,
  UsersRound,
} from "lucide-react";
import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useCircles } from "../AppContext";
import { Avatar } from "../components/Avatar";
import { Modal } from "../components/Modal";
import { supabase } from "../lib/supabase";
import { copyText } from "../lib/share";
import { getErrorMessage } from "../lib/errors";
import type { Member } from "../types";
import { PeoplePage } from "./PeoplePage";

export function CirclePage() {
  const { data, error, selectGroup, createGroup } = useCircles();
  const { circleId } = useParams();
  const [managingPeople, setManagingPeople] = useState(false);
  const [accountBusy,setAccountBusy]=useState<string|null>(null);
  const [accessMemberId,setAccessMemberId]=useState<string|null>(null);
  const [accessMessage,setAccessMessage]=useState("");
  const [accessMessageKind,setAccessMessageKind]=useState<"success"|"error"|null>(null);
  const [accessNeedsRefresh,setAccessNeedsRefresh]=useState(false);
  const [badgeNote,setBadgeNote]=useState("");
  const [credentials,setCredentials]=useState<{login:string;temporaryPassword:string;kind:"member"|"leader"}|null>(null);
  const [creatingCircle,setCreatingCircle]=useState(false);
  const [circleBusy,setCircleBusy]=useState(false);
  const [circleError,setCircleError]=useState("");
  const [circleForm,setCircleForm]=useState({name:"",description:"",location:"",leaderPersonId:""});
  useEffect(() => {
    if (circleId && data?.group?.id !== circleId) {
      const found = data?.groups.find((group) => group.id === circleId);
      if (found) void selectGroup(found.id);
    }
  }, [circleId, data?.group?.id]);
  if (!data) return null;
  if (!circleId) {
    if (!data.groups.length)
      return (
        <div className="empty-state">
          <UsersRound />
          <h2>No Circle assigned</h2>
          <p>
            Ask your SheepCount administrator to add you to an active cell
            group.
          </p>
        </div>
      );
    return (
      <div>
        <div className="page-heading">
          <div>
            <p className="page-kicker">Your community</p>
            <h1>All Circles</h1>
            <p>Choose a Circle to see its people, place, and gatherings.</p>
          </div>
          {data.currentUser.role === "admin" && (
            <button className="primary-button" onClick={() => setCreatingCircle(true)}>
              <Plus size={17} /> Create a Circle
            </button>
          )}
        </div>
        <div className="mt-8 grid gap-5 md:grid-cols-2">
          {data.groups.map((group, index) => {
            const monogram = group.name
              .split(/\s+/)
              .filter(Boolean)
              .map((word) => word.match(/[\p{L}\p{N}]/u)?.[0] || "")
              .filter(Boolean)
              .slice(0, 2)
              .join("")
              .toUpperCase();
            return (
              <Link
                key={group.id}
                to={`/circles/${group.id}`}
                className="group grid min-h-72 overflow-hidden rounded-[1.75rem] border border-line bg-paper shadow-[0_1px_0_rgba(41,43,36,0.03)] transition-[border-color,box-shadow] hover:border-olive/40 hover:shadow-[0_18px_50px_rgba(41,43,36,0.08)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-olive sm:grid-cols-[10.5rem_1fr]"
              >
                <div
                  className={`relative flex min-h-40 flex-col justify-between overflow-hidden p-5 text-paper sm:min-h-full ${index % 2 === 0 ? "bg-olive" : "bg-[#3F4637]"}`}
                >
                  <div className="relative z-10 flex items-center justify-between gap-3 sm:items-start">
                    <span className="grid h-9 w-9 place-items-center rounded-full border border-paper/25 bg-paper/10">
                      <UsersRound size={17} />
                    </span>
                    <span className="rounded-full border border-paper/20 bg-paper/10 px-3 py-1 text-[10px] font-medium capitalize text-paper/85 backdrop-blur-sm">
                      {group.role}
                    </span>
                  </div>
                  <span
                    aria-hidden="true"
                    className="absolute -bottom-5 -left-1 font-display text-[8rem] leading-none text-paper/[0.10] sm:-bottom-3 sm:text-[7.5rem]"
                  >
                    {monogram}
                  </span>
                  <p className="relative z-10 hidden max-w-24 text-xs leading-5 text-paper/65 sm:block">
                    A Circle of {data.organization.name}
                  </p>
                </div>
                <div className="flex min-w-0 flex-col p-6 sm:p-7">
                  <h2 className="font-display text-[2rem] leading-[1.05] sm:text-4xl">
                    {group.name}
                  </h2>
                  <p className="mt-4 line-clamp-3 text-sm leading-6 text-muted">
                    {group.description ||
                      "A place to gather, belong, and grow together."}
                  </p>
                  <div className="mt-auto border-t border-line pt-5">
                    <div className="flex items-center gap-2 text-sm text-muted">
                      <MapPin size={15} className="shrink-0 text-olive" />
                      <span className="truncate">
                        {group.location || "Location shared with members"}
                      </span>
                    </div>
                    <span className="mt-4 flex items-center text-sm font-medium text-olive">
                      Open Circle
                      <ChevronRight
                        size={17}
                        className="ml-auto transition-transform group-hover:translate-x-1 motion-reduce:transition-none"
                      />
                    </span>
                  </div>
                </div>
              </Link>
            );
          })}
        </div>
        {creatingCircle && (
          <Modal title="Create a Circle" onClose={() => setCreatingCircle(false)}>
            <form className="space-y-5" onSubmit={(event) => {
              event.preventDefault();
              setCircleBusy(true);
              setCircleError("");
              void createGroup(circleForm)
                .then(() => setCreatingCircle(false))
                .catch((cause) => setCircleError(getErrorMessage(cause, "The Circle could not be created.")))
                .finally(() => setCircleBusy(false));
            }}>
              <p className="text-sm leading-6 text-muted">
                A new Circle begins with an approved leader who has completed the Discipleship step and uses SheepCount credentials.
              </p>
              <label className="field-label">Circle name<input className="field" required value={circleForm.name} onChange={(event) => setCircleForm({ ...circleForm, name: event.target.value })} /></label>
              <label className="field-label">Description<textarea className="field min-h-24" value={circleForm.description} onChange={(event) => setCircleForm({ ...circleForm, description: event.target.value })} /></label>
              <label className="field-label">Location<input className="field" value={circleForm.location} onChange={(event) => setCircleForm({ ...circleForm, location: event.target.value })} /></label>
              <label className="field-label">Primary leader
                <select className="field" required value={circleForm.leaderPersonId} onChange={(event) => setCircleForm({ ...circleForm, leaderPersonId: event.target.value })}>
                  <option value="">Choose an approved leader</option>
                  {data.approvedLeaders.map((leader) => <option key={leader.personId} value={leader.personId}>{leader.fullName} · {leader.email}</option>)}
                </select>
              </label>
              {!data.approvedLeaders.length && <p className="rounded-xl bg-parchment p-4 text-sm leading-6 text-muted">No one is ready to assign yet. Open a member’s Manage access record, award the Discipleship badge, then approve them for leadership.</p>}
              {circleError && <p className="form-error" role="alert">{circleError}</p>}
              <button className="primary-button w-full" disabled={circleBusy || !data.approvedLeaders.length}>{circleBusy ? "Creating…" : "Create Circle"}</button>
            </form>
          </Modal>
        )}
      </div>
    );
  }
  const requestedGroup = data.groups.find((group) => group.id === circleId);
  if (!requestedGroup)
    return (
      <div className="empty-state">
        <UsersRound />
        <h2>Circle not found</h2>
        <Link className="text-link" to="/circles">
          View all Circles
        </Link>
      </div>
    );
  if (data.group?.id !== requestedGroup.id)
    return (
      <div className="paper-panel p-8 text-center text-sm text-muted">
        {error ? (
          <>
            <p>{error}</p>
            <Link className="text-link mt-4" to="/circles">
              Return to all Circles
            </Link>
          </>
        ) : (
          <>Opening {requestedGroup.name}…</>
        )}
      </div>
    );
  if (!data.group)
    return (
      <div className="empty-state">
        <UsersRound />
        <h2>No Circle assigned</h2>
        <p>
          SheepCount administrators create Circles and assign leaders. Ask your
          administrator to add you to an active cell group.
        </p>
      </div>
    );
  const activeGroup = data.group;
  const canManagePeople =
    data.currentUser.role === "admin" || activeGroup.role === "leader";
  const accessMember = data.members.find((member) => member.id === accessMemberId);
  const closeAccess = () => {
    setAccessMemberId(null);
    setAccessMessage("");
    setAccessMessageKind(null);
    setCredentials(null);
    if (accessNeedsRefresh) {
      setAccessNeedsRefresh(false);
      void selectGroup(activeGroup.id);
    }
  };
  const manageAccount = async (member: Member, action: "provision" | "reset" | "promote") => {
    if (!supabase) return;
    setAccountBusy(member.id);
    setAccessMessage("");
    setAccessMessageKind(null);
    setCredentials(null);
    try {
      const result = await supabase.functions.invoke("circle-member-access", {
        body: { action, groupId: activeGroup.id, personId: member.id },
      });
      if (result.error || result.data?.error) {
        let message = result.data?.error || result.error?.message || "Account access could not be updated.";
        const response = (result.error as { context?: Response } | null)?.context;
        if (response instanceof Response) {
          try {
            const payload = await response.clone().json() as { error?: string };
            if (payload.error) message = payload.error;
          } catch {
            // Keep the SDK error when the function did not return JSON.
          }
        }
        setAccessMessage(message);
        setAccessMessageKind("error");
        return;
      }
      setAccessNeedsRefresh(true);
      setAccessMessageKind("success");
      if (action === "promote") {
        setAccessMessage(result.data.linkedExisting
          ? "Leadership approved. Their existing SheepCount account is now linked."
          : "Leadership approved. Copy the new SheepCount credentials now.");
        if (result.data.temporaryPassword)
          setCredentials({ login: result.data.email, temporaryPassword: result.data.temporaryPassword, kind: "leader" });
        if (result.data.warning) setAccessMessage((message) => `${message} ${result.data.warning}`);
      } else {
        setAccessMessage(result.data.existingAccount
          ? "Their existing SheepCount account is linked to Circles."
          : result.data.alreadyExists
            ? "This member already has Circles access. Use Reset temporary password if they no longer have the original password."
            : "Account created. Copy the Member ID and temporary password before closing this window.");
        if (result.data.loginId && result.data.temporaryPassword)
          setCredentials({ login: result.data.loginId, temporaryPassword: result.data.temporaryPassword, kind: "member" });
      }
    } catch (error) {
      setAccessMessage(getErrorMessage(error, "Account access could not be updated."));
      setAccessMessageKind("error");
    } finally {
      setAccountBusy(null);
    }
  };
  const setBadge = async (member: Member, active: boolean) => {
    if (!supabase) return;
    setAccountBusy(member.id);
    setAccessMessage("");
    const result = await supabase.rpc("set_circle_discipleship_badge", {
      p_person_id: member.id,
      p_active: active,
      p_note: badgeNote.trim(),
    });
    if (result.error) setAccessMessage(result.error.message);
    else {
      setAccessMessage(active ? "Discipleship badge awarded." : "Discipleship badge revoked.");
      setBadgeNote("");
      await selectGroup(activeGroup.id);
    }
    setAccountBusy(null);
  };
  const nextGathering = data.meetings
    .filter(
      (meeting) =>
        meeting.groupId === data.group?.id &&
        meeting.status === "scheduled" &&
        new Date(meeting.meetingDate) >= new Date(),
    )
    .sort((a, b) => a.meetingDate.localeCompare(b.meetingDate))[0];
  const circleLeader = data.members.find((member) => member.role === "leader" || member.id === activeGroup.leaderId);
  const circleAnnouncements = data.announcements.filter((item) => item.groupId === activeGroup.id);
  const latestAnnouncement = circleAnnouncements[0];
  const latestGallery = data.galleries[0];
  const latestTestimony = data.testimonies.find((item) => item.status !== "draft");
  return (
    <div>
      <div className="page-heading">
        <div>
          <p className="page-kicker">My Circles</p>
          <h1>{data.group.name}</h1>
          <p>{data.group.description}</p>
          <div className="mt-4 flex flex-wrap gap-x-6 gap-y-2 text-sm text-muted">
            <span className="inline-flex items-center gap-2"><MapPin size={15} className="text-olive" />{activeGroup.location||"Location shared with members"}</span>
            {circleLeader&&<span className="inline-flex items-center gap-2"><UsersRound size={15} className="text-olive" />Led by {circleLeader.fullName}</span>}
          </div>
        </div>
        <Link className="secondary-button" to="/circles">
          View all Circles
        </Link>
      </div>
      <section className="mt-8 flex flex-col gap-5 border-y border-line py-6 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <p className="text-xs text-olive">Next gathering</p>
          <h2 className="mt-1 font-display text-3xl">
            {nextGathering?.title || "Nothing scheduled yet"}
          </h2>
          <p className="mt-2 text-sm text-muted">
            {nextGathering
              ? `${new Date(nextGathering.meetingDate).toLocaleDateString(undefined, { month: "long", day: "numeric" })} · ${nextGathering.location}`
              : "The next date will appear here when it is planned."}
          </p>
        </div>
        <Link className="primary-button" to={nextGathering ? `/gatherings/${nextGathering.id}` : "/gatherings"}>
          {nextGathering ? "View gathering" : "View gatherings"} <ChevronRight size={16} />
        </Link>
      </section>
      {latestAnnouncement && (
        <section className="mt-12 border-t border-line pt-8">
          <div className="section-heading"><div><h2>{activeGroup.name} updates</h2><p>Notes shared specifically with this Circle.</p></div></div>
          <article className="max-w-4xl border-l-2 border-olive pl-5 sm:pl-7"><Megaphone size={18} className="text-olive"/><h3 className="mt-4 font-display text-3xl">{latestAnnouncement.title}</h3><p className="mt-3 whitespace-pre-line leading-7 text-muted">{latestAnnouncement.body}</p></article>
        </section>
      )}
      {latestGallery && (
        <section className="mt-12 border-t border-line pt-8">
          <div className="section-heading"><div><h2>Life in {activeGroup.name}</h2><p>Photographs published for this Circle.</p></div></div>
          <a href={`/${data.organization.slug}/galleries/${latestGallery.slug}`} target="_blank" rel="noreferrer" className="group relative block min-h-72 overflow-hidden rounded-[1.75rem] text-paper sm:min-h-96"><img src={latestGallery.coverUrl||"/assets/devotional-table.webp"} alt="" className="absolute inset-0 h-full w-full object-cover"/><div className="absolute inset-0 bg-gradient-to-t from-ink/90 via-ink/20 to-transparent"/><div className="relative flex min-h-72 flex-col justify-end p-6 sm:min-h-96 sm:p-8"><Images size={20}/><h3 className="mt-4 max-w-2xl font-display text-3xl sm:text-4xl">{latestGallery.title}</h3><p className="mt-2 max-w-xl text-sm text-paper/80">{latestGallery.description}</p><span className="mt-5 text-sm font-medium">View {latestGallery.photos.length} {latestGallery.photos.length===1?"photo":"photos"}</span></div></a>
        </section>
      )}
      {latestTestimony && (
        <section className="mt-12 border-t border-line pt-8">
          <div className="section-heading"><div><h2>Stories from {activeGroup.name}</h2><p>Testimonies rooted in this Circle’s life together.</p></div></div>
          <a href={`/${data.organization.slug}/testimonies/${latestTestimony.slug}`} target="_blank" rel="noreferrer" className="block max-w-4xl border-y border-line py-7"><Quote size={19} className="text-olive"/><h3 className="mt-4 font-display text-3xl">{latestTestimony.title}</h3><p className="mt-3 line-clamp-4 leading-7 text-muted">{latestTestimony.body}</p><p className="mt-4 text-sm text-olive">Shared by {latestTestimony.authorName}</p></a>
        </section>
      )}
      <div className="mt-8 grid gap-5 lg:grid-cols-[.7fr_1.3fr]">
        <aside className="paper-panel p-6">
          <MapPin className="text-olive" />
          <h2 className="mt-5 font-display text-3xl">Where we gather</h2>
          <p className="mt-3 leading-7 text-muted">
            {data.group.location ||
              "Location shared with members before each gathering."}
          </p>
          <p className="mt-5 text-sm text-olive">
            {data.group.regularSchedule}
          </p>
          <div className="mt-7 flex gap-2 border-t border-line pt-5 text-xs text-muted">
            <ShieldCheck size={16} />
            Member details remain private to this Circle.
          </div>
        </aside>
        <section className="paper-panel overflow-hidden">
          <div className="border-b border-line p-6">
            <h2 className="font-display text-3xl">Our people</h2>
            <p className="mt-1 text-sm text-muted">
              Membership is managed here using your organization’s SheepCount
              directory.
            </p>
          </div>
          <div className="divide-y divide-line">
            {data.members.map((m) => (
              <div key={m.id} className="member-row">
                <Avatar person={m} size="lg" />
                <div className="min-w-0 flex-1">
                  <p className="font-medium">{m.fullName}</p>
                  <p className="text-xs text-muted">
                    {m.email || "No email on record"}
                  </p>
                </div>
                <span
                  className={`role-label ${m.role === "leader" ? "role-label-leader" : ""}`}
                >
                  {m.role}
                </span>
                {m.discipleshipBadge && <span className="role-label flex items-center gap-1"><BadgeCheck size={13} /> Discipleship</span>}
                {(data.currentUser.role === "admin" || (activeGroup.role === "leader" && m.role === "member")) && (
                  <button className="secondary-button ml-12 w-full sm:ml-0 sm:w-auto" onClick={() => {
                    setAccessMemberId(m.id);
                    setAccessMessage("");
                    setCredentials(null);
                    setBadgeNote("");
                  }}>
                    Manage access
                  </button>
                )}
              </div>
            ))}
          </div>
        </section>
      </div>
      <div className="mt-8 flex flex-wrap gap-3">
        {canManagePeople && (
          <button
            className="primary-button"
            onClick={() => setManagingPeople(true)}
          >
            <UserPlus size={17} /> Add people
          </button>
        )}
      </div>
      {managingPeople && (
        <Modal
          title={`Add people to ${data.group.name}`}
          onClose={() => setManagingPeople(false)}
        >
          <PeoplePage compact />
        </Modal>
      )}
      {accessMember && (
        <Modal title="Manage access" onClose={closeAccess}>
          <div>
            <div className="border-b border-line pb-5">
              <p className="page-kicker">Member record</p>
              <h3 className="mt-2 font-display text-3xl">{accessMember.fullName}</h3>
              <p className="mt-1 text-sm text-muted">{accessMember.email || "No SheepCount email on record"}</p>
            </div>

            <section className="border-b border-line py-5">
              <div className="flex items-start gap-3">
                <KeyRound className="mt-0.5 shrink-0 text-olive" size={19} />
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <h4 className="font-medium">Login</h4>
                    <span className="role-label">{accessMember.account?.status === "active" ? (accessMember.account.kind === "generated" ? "Member ID" : "SheepCount linked") : "No account"}</span>
                  </div>
                  {accessMember.account?.loginId && <p className="mt-2 break-all font-mono text-sm text-muted">{accessMember.account.loginId}</p>}
                  <p className="mt-2 text-sm leading-6 text-muted">
                    {accessMember.account?.status === "active"
                      ? accessMember.account.kind === "generated"
                        ? "This temporary member login can be reset by their Circle leader."
                        : "This person signs in with their normal SheepCount email and password."
                      : "Create a Member ID so this person can participate in Circles."}
                  </p>
                  {accessMember.account?.status === "active" && accessMember.account.kind === "generated" ? (
                    <button className="secondary-button mt-4" disabled={accountBusy === accessMember.id} onClick={() => window.confirm(`Issue a new temporary password for ${accessMember.fullName}?`) && void manageAccount(accessMember, "reset")}><KeyRound size={15} /> Reset temporary password</button>
                  ) : accessMember.account?.status !== "active" ? (
                    <button className="secondary-button mt-4" disabled={accountBusy === accessMember.id} onClick={() => void manageAccount(accessMember, "provision")}>{accountBusy === accessMember.id ? "Creating…" : "Create Member ID"}</button>
                  ) : null}

                  {credentials && (
                    <div className="mt-5 rounded-2xl border border-olive/25 bg-sage/60 p-5" role="status">
                      <h4 className="font-medium">Copy these credentials now</h4>
                      <p className="mt-2 text-sm leading-6 text-muted">The temporary password is shown only once and must be changed at first sign-in.</p>
                      <div className="mt-4 space-y-3 rounded-xl bg-paper p-4">
                        <div><span className="text-xs text-muted">{credentials.kind === "leader" ? "SheepCount email" : "Member ID"}</span><strong className="mt-1 block break-all font-mono">{credentials.login}</strong></div>
                        <div><span className="text-xs text-muted">Temporary password</span><strong className="mt-1 block break-all font-mono">{credentials.temporaryPassword}</strong></div>
                      </div>
                      <button className="primary-button mt-4 w-full" onClick={() => void copyText(`${credentials.kind === "leader" ? "SheepCount email" : "Circles Member ID"}: ${credentials.login}\nTemporary password: ${credentials.temporaryPassword}\nSign in: ${window.location.origin}/sign-in`)}><Copy size={16} /> Copy credentials</button>
                    </div>
                  )}
                  {accessMessage && (
                    <p role={accessMessageKind === "error" ? "alert" : "status"} className={`mt-4 rounded-xl p-4 text-sm leading-6 ${accessMessageKind === "error" ? "bg-red-50 text-red-800" : "bg-parchment text-muted"}`}>
                      {accessMessage}
                    </p>
                  )}
                </div>
              </div>
            </section>

            <section className="border-b border-line py-5">
              <div className="flex items-start gap-3">
                <BadgeCheck className="mt-0.5 shrink-0 text-olive" size={19} />
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <h4 className="font-medium">Discipleship</h4>
                    <span className="role-label">{accessMember.discipleshipBadge ? "Badge awarded" : "Not yet awarded"}</span>
                  </div>
                  <p className="mt-2 text-sm leading-6 text-muted">
                    {accessMember.discipleshipBadge
                      ? accessMember.badgeSource === "system_grandfathered" ? "Recognized from their existing leadership service." : "Recognized by an organization administrator."
                      : "The badge records completed discipleship but does not grant leadership on its own."}
                  </p>
                  {data.currentUser.role === "admin" && (
                    <div className="mt-4 space-y-3">
                      <label className="field-label">Optional note<input className="field" value={badgeNote} onChange={(event) => setBadgeNote(event.target.value)} placeholder="Course, cohort, or reason" /></label>
                      <button className="secondary-button" disabled={accountBusy === accessMember.id} onClick={() => {
                        const active = !accessMember.discipleshipBadge;
                        if (active || window.confirm(`Revoke ${accessMember.fullName}’s Discipleship badge and leadership approval?`)) void setBadge(accessMember, active);
                      }}>{accessMember.discipleshipBadge ? "Revoke badge" : "Award Discipleship badge"}</button>
                    </div>
                  )}
                </div>
              </div>
            </section>

            <section className="border-b border-line py-5">
              <div className="flex items-start gap-3">
                <ShieldCheck className="mt-0.5 shrink-0 text-olive" size={19} />
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <h4 className="font-medium">Leadership</h4>
                    <span className="role-label">{accessMember.leadershipStatus === "approved" ? "Approved" : "Not approved"}</span>
                  </div>
                  <p className="mt-2 text-sm leading-6 text-muted">
                    Approval converts a generated Member ID to SheepCount email credentials. It does not remove this person from {data.group.name} or give access to another Circle until an admin assigns one.
                  </p>
                  {data.currentUser.role === "admin" && accessMember.leadershipStatus !== "approved" && (
                    <button className="primary-button mt-4" disabled={accountBusy === accessMember.id || !accessMember.discipleshipBadge || !accessMember.email} onClick={() => window.confirm(`Approve ${accessMember.fullName} for Circle leadership and convert their login to SheepCount credentials?`) && void manageAccount(accessMember, "promote")}>
                      {accountBusy === accessMember.id ? "Approving…" : "Approve for leadership"}
                    </button>
                  )}
                  {data.currentUser.role === "admin" && !accessMember.discipleshipBadge && <p className="mt-3 text-xs text-muted">Award the Discipleship badge first.</p>}
                  {data.currentUser.role === "admin" && accessMember.discipleshipBadge && !accessMember.email && <p className="mt-3 text-xs text-muted">Add an email to this person’s SheepCount record first.</p>}
                </div>
              </div>
            </section>

            {data.currentUser.role === "admin" && Boolean(accessMember.account?.transitions?.length) && (
              <section className="pt-5">
                <div className="flex items-center gap-2"><History size={17} className="text-olive" /><h4 className="font-medium">Account history</h4></div>
                <div className="mt-3 divide-y divide-line border-y border-line">
                  {accessMember.account!.transitions.map((transition, index) => (
                    <div className="py-3" key={`${transition.createdAt}-${index}`}>
                      <div className="flex items-baseline justify-between gap-3"><span className="text-sm font-medium">{transition.action.split("_").map((part) => part[0].toUpperCase() + part.slice(1)).join(" ")}</span><time className="shrink-0 text-xs text-muted">{new Date(transition.createdAt).toLocaleDateString()}</time></div>
                      {transition.note && <p className="mt-1 text-xs leading-5 text-muted">{transition.note}</p>}
                    </div>
                  ))}
                </div>
              </section>
            )}
          </div>
        </Modal>
      )}
    </div>
  );
}
