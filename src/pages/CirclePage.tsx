import {
  ChevronRight,
  MapPin,
  ShieldCheck,
  UserPlus,
  UsersRound,
} from "lucide-react";
import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useCircles } from "../AppContext";
import { Avatar } from "../components/Avatar";
import { Modal } from "../components/Modal";
import { PeoplePage } from "./PeoplePage";

export function CirclePage() {
  const { data, error, selectGroup } = useCircles();
  const { circleId } = useParams();
  const [managingPeople, setManagingPeople] = useState(false);
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
        <div className="mt-8 grid gap-5 sm:grid-cols-2">
          {data.groups.map((group) => (
            <Link
              key={group.id}
              to={`/circles/${group.id}`}
              className="group paper-panel flex min-h-56 flex-col p-6 transition-colors hover:border-sage focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-olive sm:p-7"
            >
              <div className="flex items-start justify-between gap-4">
                <span className="quick-icon">
                  <UsersRound />
                </span>
                <span className="role-label capitalize">{group.role}</span>
              </div>
              <h2 className="mt-6 font-display text-3xl leading-tight">
                {group.name}
              </h2>
              <p className="mt-2 line-clamp-2 text-sm leading-6 text-muted">
                {group.description || "A place to gather and grow together."}
              </p>
              <span className="mt-auto flex items-center gap-2 pt-6 text-sm text-olive">
                <MapPin size={15} />
                <span className="truncate">
                  {group.location || "Location shared with members"}
                </span>
                <ChevronRight
                  size={17}
                  className="ml-auto transition-transform group-hover:translate-x-0.5"
                />
              </span>
            </Link>
          ))}
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
  const base = "";
  const canManagePeople =
    data.currentUser.role === "admin" || data.group.role === "leader";
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
                <div className="flex-1">
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
              </div>
            ))}
          </div>
        </section>
      </div>
      <div className="mt-8 flex flex-wrap gap-3">
        <Link className="secondary-button" to={`${base}/gatherings`}>
          View gatherings
        </Link>
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
    </div>
  );
}
