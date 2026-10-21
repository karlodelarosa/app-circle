import { MapPin, ShieldCheck, UserPlus, UsersRound } from "lucide-react";
import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useCircles } from "../AppContext";
import { Avatar } from "../components/Avatar";
import { Modal } from "../components/Modal";
import { PeoplePage } from "./PeoplePage";

export function CirclePage() {
  const { data, selectGroup } = useCircles();
  const { circleId } = useParams();
  const [managingPeople, setManagingPeople] = useState(false);
  useEffect(() => {
    if (circleId && data?.group?.id !== circleId) {
      const found = data?.groups.find((group) => group.id === circleId);
      if (found) void selectGroup(found.id);
    }
  }, [circleId, data?.group?.id]);
  if (!data) return null;
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
        {data.groups.length > 1 && (
          <select
            className="field max-w-xs"
            aria-label="Choose Circle"
            value={data.group.id}
            onChange={(e) => void selectGroup(e.target.value)}
          >
            {data.groups.map((g) => (
              <option key={g.id} value={g.id}>
                {g.name}
                {g.role === "leader" ? " — Leader" : ""}
              </option>
            ))}
          </select>
        )}
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
