import {
  ChevronRight,
  MapPin,
  ShieldCheck,
  KeyRound,
  Copy,
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
import { PeoplePage } from "./PeoplePage";

export function CirclePage() {
  const { data, error, selectGroup } = useCircles();
  const { circleId } = useParams();
  const [managingPeople, setManagingPeople] = useState(false);
  const [accountBusy,setAccountBusy]=useState<string|null>(null);
  const [credentials,setCredentials]=useState<{name:string;loginId?:string;temporaryPassword?:string;message?:string}|null>(null);
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
  const canManagePeople =
    data.currentUser.role === "admin" || data.group.role === "leader";
  const manageAccount=async(member:typeof data.members[number],action:"provision"|"reset")=>{if(!supabase)return;setAccountBusy(member.id);const result=await supabase.functions.invoke("circle-member-access",{body:{action,groupId:data.group!.id,personId:member.id}});if(result.error||result.data?.error)setCredentials({name:member.fullName,message:result.data?.error||result.error?.message||"Account access could not be updated."});else{setCredentials({name:member.fullName,loginId:result.data.loginId,temporaryPassword:result.data.temporaryPassword,message:result.data.existingAccount?"Their existing SheepCount account is now linked to Circles.":result.data.alreadyExists?"This member already has Circles access.":undefined});await selectGroup(data.group!.id)}setAccountBusy(null)};
  const nextGathering = data.meetings
    .filter(
      (meeting) =>
        meeting.groupId === data.group?.id &&
        meeting.status === "scheduled" &&
        new Date(meeting.meetingDate) >= new Date(),
    )
    .sort((a, b) => a.meetingDate.localeCompare(b.meetingDate))[0];
  const latestAnnouncement = data.announcements[0];
  const latestGallery = data.galleries[0];
  const latestTestimony = data.testimonies.find((item) => item.status !== "draft");
  return (
    <div>
      <div className="page-heading">
        <div>
          <p className="page-kicker">My Circles</p>
          <h1>{data.group.name}</h1>
          <p>{data.group.description}</p>
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
      <section className="mt-10">
        <div className="section-heading">
          <div>
            <h2>Life in our Circle</h2>
            <p>Recent updates, photographs, and stories shared with this community.</p>
          </div>
        </div>
        <div className="grid gap-5 md:grid-cols-3">
          <article className="paper-panel p-6">
            <Megaphone size={19} className="text-olive" />
            <p className="mt-5 text-xs text-olive">Latest announcement</p>
            <h3 className="mt-2 font-display text-2xl">{latestAnnouncement?.title || "No current update"}</h3>
            <p className="mt-3 line-clamp-4 text-sm leading-6 text-muted">{latestAnnouncement?.body || "Circle announcements will appear here."}</p>
          </article>
          {latestGallery ? (
            <a href={`/${data.organization.slug}/galleries/${latestGallery.slug}`} target="_blank" rel="noreferrer" className="group relative min-h-64 overflow-hidden rounded-3xl text-paper">
              <img src={latestGallery.coverUrl || "/assets/devotional-table.webp"} alt="" className="absolute inset-0 h-full w-full object-cover" />
              <div className="absolute inset-0 bg-gradient-to-t from-ink/90 via-ink/15 to-transparent" />
              <div className="relative flex h-full min-h-64 flex-col justify-end p-6">
                <Images size={19} />
                <h3 className="mt-3 font-display text-2xl">{latestGallery.title}</h3>
                <p className="mt-2 text-xs text-paper/75">View gallery</p>
              </div>
            </a>
          ) : (
            <article className="paper-panel p-6"><Images className="text-olive" size={19} /><h3 className="mt-5 font-display text-2xl">No gallery yet</h3><p className="mt-3 text-sm leading-6 text-muted">Community photographs will appear here after they are published.</p></article>
          )}
          {latestTestimony ? (
            <a href={`/${data.organization.slug}/testimonies/${latestTestimony.slug}`} target="_blank" rel="noreferrer" className="paper-panel p-6">
              <Quote size={19} className="text-olive" />
              <p className="mt-5 text-xs text-olive">Latest testimony</p>
              <h3 className="mt-2 font-display text-2xl">{latestTestimony.title}</h3>
              <p className="mt-3 line-clamp-3 text-sm leading-6 text-muted">{latestTestimony.body}</p>
            </a>
          ) : (
            <article className="paper-panel p-6"><Quote className="text-olive" size={19} /><h3 className="mt-5 font-display text-2xl">Stories will gather here</h3><p className="mt-3 text-sm leading-6 text-muted">Published testimonies from your community will appear here.</p></article>
          )}
        </div>
      </section>
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
                {canManagePeople&&m.role==="member"&&(
                  m.account?.status==="active"?<button className="secondary-button ml-12 w-full sm:ml-0 sm:w-auto" disabled={accountBusy===m.id||m.account.kind!=="generated"} onClick={()=>m.account?.kind==="generated"&&window.confirm(`Issue a new temporary password for ${m.fullName}?`)?void manageAccount(m,"reset"):undefined}>{m.account.kind==="generated"?<><KeyRound size={15}/>Reset password</>:"SheepCount linked"}</button>:<button className="secondary-button ml-12 w-full sm:ml-0 sm:w-auto" disabled={accountBusy===m.id} onClick={()=>void manageAccount(m,"provision")}>{accountBusy===m.id?"Creating…":"Create app account"}</button>
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
      {credentials&&<Modal title="Member app access" onClose={()=>setCredentials(null)}><div><h3 className="font-display text-3xl">{credentials.name}</h3>{credentials.message&&<p className="mt-4 leading-6 text-muted">{credentials.message}</p>}{credentials.loginId&&credentials.temporaryPassword&&<><p className="mt-4 text-sm leading-6 text-muted">Copy these credentials now. The temporary password is shown only once and must be changed at first sign-in.</p><div className="mt-5 space-y-3 rounded-2xl bg-parchment p-5"><div><span className="text-xs text-muted">Member ID</span><strong className="mt-1 block font-mono">{credentials.loginId}</strong></div><div><span className="text-xs text-muted">Temporary password</span><strong className="mt-1 block break-all font-mono">{credentials.temporaryPassword}</strong></div></div><button className="primary-button mt-5 w-full" onClick={()=>void copyText(`Circles Member ID: ${credentials.loginId}\nTemporary password: ${credentials.temporaryPassword}\nSign in: ${window.location.origin}/sign-in`)}><Copy size={16}/>Copy credentials</button></>}</div></Modal>}
    </div>
  );
}
