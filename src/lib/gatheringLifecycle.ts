import type { MeetingStatus } from "../types";

export type GatheringLifecycle =
  | "upcoming"
  | "live"
  | "attendance_pending"
  | "completed"
  | "cancelled";

type LifecycleMeeting = {
  status: MeetingStatus;
  meetingDate: string;
  endsAt: string;
};

export function gatheringLifecycle(
  meeting: LifecycleMeeting,
  now = new Date(),
): GatheringLifecycle {
  if (meeting.status === "cancelled") return "cancelled";
  if (meeting.status === "completed") return "completed";
  if (now.getTime() < new Date(meeting.meetingDate).getTime()) return "upcoming";
  if (now.getTime() <= new Date(meeting.endsAt).getTime()) return "live";
  return "attendance_pending";
}

const datePart = (value: string) =>
  new Intl.DateTimeFormat("en", {
    weekday: "long",
    month: "long",
    day: "numeric",
    year: "numeric",
  }).format(new Date(value));

const timePart = (value: string) =>
  new Intl.DateTimeFormat("en", {
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(value));

export function formatGatheringDateTime(startsAt: string, endsAt: string) {
  const start = new Date(startsAt);
  const end = new Date(endsAt);
  const sameLocalDay =
    start.getFullYear() === end.getFullYear() &&
    start.getMonth() === end.getMonth() &&
    start.getDate() === end.getDate();
  return sameLocalDay
    ? `${datePart(startsAt)} · ${timePart(startsAt)}–${timePart(endsAt)}`
    : `${datePart(startsAt)}, ${timePart(startsAt)} – ${datePart(endsAt)}, ${timePart(endsAt)}`;
}

export function gatheringRelativeStatus(endsAt: string, now = new Date()) {
  const elapsed = Math.max(0, now.getTime() - new Date(endsAt).getTime());
  const days = Math.floor(elapsed / 86_400_000);
  if (days === 0) return "Ended today";
  if (days === 1) return "Ended yesterday";
  return `Ended ${days} days ago`;
}

export const rsvpLabel = (status?: string) => {
  if (status === "attending") return "Going";
  if (status === "tentative") return "Maybe";
  if (status === "declined") return "Can’t go";
  return "No RSVP";
};
