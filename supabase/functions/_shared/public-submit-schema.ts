export type PublicSubmissionAction =
  | "guest_rsvp"
  | "circle_connection"
  | "circle_interest"
  | "group_signup";

export type ValidPublicSubmission = {
  action: PublicSubmissionAction;
  botToken: string;
  payload: Record<string, string | boolean | null>;
};

export type ValidationResult =
  | { ok: true; value: ValidPublicSubmission }
  | { ok: false; error: "Invalid submission" };

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const email = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const phone = /^\+?[0-9][0-9 ()-]{6,38}$/;
const slug = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const date = /^\d{4}-\d{2}-\d{2}$/;
const invalid = (): ValidationResult => ({ ok: false, error: "Invalid submission" });
const record = (value: unknown): value is Record<string, unknown> =>
  Boolean(value) && typeof value === "object" && !Array.isArray(value);
const text = (value: unknown, max: number) => {
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  return normalized.length <= max ? normalized : null;
};
const requiredText = (value: unknown, max: number) => {
  const normalized = text(value, max);
  return normalized ? normalized : null;
};
const optionalUuid = (value: unknown) =>
  value === undefined || value === null || value === "" ? null : uuid.test(String(value)) ? String(value) : undefined;

export function validatePublicSubmission(input: unknown): ValidationResult {
  if (!record(input) || !record(input.payload)) return invalid();
  const action = input.action;
  const botToken = text(input.botToken, 4096);
  if (
    !["guest_rsvp", "circle_connection", "circle_interest", "group_signup"].includes(String(action)) ||
    botToken === null
  ) return invalid();
  const payload = input.payload;

  if (action === "guest_rsvp") {
    const gatheringId = requiredText(payload.gatheringId, 36);
    const name = requiredText(payload.name, 120);
    const emailValue = text(payload.email, 254);
    const phoneValue = text(payload.phone, 40);
    const status = requiredText(payload.status, 16);
    if (!gatheringId || !uuid.test(gatheringId) || !name || emailValue === null || phoneValue === null ||
      (!emailValue && !phoneValue) || (emailValue && !email.test(emailValue)) ||
      (phoneValue && !phone.test(phoneValue)) || !["attending", "tentative", "declined"].includes(status || "")) return invalid();
    return { ok: true, value: { action, botToken, payload: {
      gatheringId, name, email: emailValue.toLowerCase(), phone: phoneValue, status,
    } } };
  }

  if (action === "circle_connection") {
    const groupId = requiredText(payload.groupId, 36);
    const guestRsvpId = optionalUuid(payload.guestRsvpId);
    const name = requiredText(payload.name, 120);
    const emailValue = text(payload.email, 254);
    const phoneValue = text(payload.phone, 40);
    const preferredContact = requiredText(payload.preferredContact, 16);
    const message = text(payload.message, 1000);
    if (!groupId || !uuid.test(groupId) || guestRsvpId === undefined || !name || emailValue === null || phoneValue === null ||
      (!emailValue && !phoneValue) || (emailValue && !email.test(emailValue)) ||
      (phoneValue && !phone.test(phoneValue)) || !["email", "phone", "either"].includes(preferredContact || "") ||
      (preferredContact === "email" && !emailValue) || (preferredContact === "phone" && !phoneValue) ||
      message === null || payload.consent !== true) return invalid();
    return { ok: true, value: { action, botToken, payload: {
      groupId, guestRsvpId, name, email: emailValue.toLowerCase(), phone: phoneValue,
      preferredContact, message, consent: true,
    } } };
  }

  if (action === "circle_interest") {
    const listingId = requiredText(payload.listingId, 36);
    const name = requiredText(payload.name, 120);
    const contact = requiredText(payload.contact, 254);
    const message = text(payload.message, 1000);
    if (!listingId || !uuid.test(listingId) || !name || !contact ||
      (!email.test(contact) && !phone.test(contact)) || message === null) return invalid();
    return { ok: true, value: { action, botToken, payload: { listingId, name, contact, message } } };
  }

  const organizationSlug = requiredText(payload.organizationSlug, 120);
  const firstName = requiredText(payload.firstName, 80);
  const lastName = requiredText(payload.lastName, 80);
  const birthdate = requiredText(payload.birthdate, 10);
  const phoneValue = text(payload.phone, 40);
  const facebookContact = text(payload.facebookContact, 300);
  const guestRsvpId = optionalUuid(payload.guestRsvpId);
  if (!organizationSlug || !slug.test(organizationSlug) || !firstName || !lastName || !birthdate || !date.test(birthdate) ||
    phoneValue === null || facebookContact === null || (!phoneValue && !facebookContact) ||
    (phoneValue && !phone.test(phoneValue)) || guestRsvpId === undefined || payload.consent !== true) return invalid();
  const parsedDate = new Date(`${birthdate}T00:00:00Z`);
  if (Number.isNaN(parsedDate.getTime()) || parsedDate.toISOString().slice(0, 10) !== birthdate ||
    birthdate < "1900-01-01" || birthdate > new Date().toISOString().slice(0, 10)) return invalid();
  return { ok: true, value: { action: "group_signup", botToken, payload: {
    organizationSlug, firstName, lastName, birthdate, phone: phoneValue,
    facebookContact, consent: true, guestRsvpId,
  } } };
}
