import type { Meeting } from "../types";

const escapeIcs = (value: string) => value
  .replaceAll("\\", "\\\\")
  .replaceAll(";", "\\;")
  .replaceAll(",", "\\,")
  .replaceAll(/\r?\n/g, "\\n");
const stamp = (value: string | Date) => new Date(value).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");

export function gatheringIcs(meeting: Meeting, url: string) {
  const description = [meeting.summary, meeting.notes, url].filter(Boolean).join("\n\n");
  return [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//SheepCount//Circles//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "BEGIN:VEVENT",
    `UID:${escapeIcs(meeting.id)}@circles.elgchurch.com`,
    `DTSTAMP:${stamp(new Date())}`,
    `DTSTART:${stamp(meeting.meetingDate)}`,
    `DTEND:${stamp(meeting.endsAt)}`,
    `SUMMARY:${escapeIcs(meeting.title)}`,
    `LOCATION:${escapeIcs(meeting.location)}`,
    `DESCRIPTION:${escapeIcs(description)}`,
    `URL:${escapeIcs(url)}`,
    "END:VEVENT",
    "END:VCALENDAR",
    "",
  ].join("\r\n");
}

export function downloadGatheringIcs(meeting: Meeting, url: string) {
  const blob = new Blob([gatheringIcs(meeting, url)], { type: "text/calendar;charset=utf-8" });
  const objectUrl = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = objectUrl;
  anchor.download = `${meeting.slug || "gathering"}.ics`;
  anchor.click();
  URL.revokeObjectURL(objectUrl);
}
