import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  CellGroupSignupInput,
  CellGroupSignupResult,
  ContactPreference,
  Gallery,
  GuestRsvpInput,
  PublicSpace,
} from "../types";
import { demoData } from "../data/demo";
import { gatheringLifecycle } from "../lib/gatheringLifecycle";

export function demoPublicSpace(): PublicSpace {
  return {
    organization: demoData.organization,
    introduction:
      "A welcoming place to gather around the table, share honest stories, and grow in faith together.",
    heroTitle: "There is room for you here.",
    heroImageUrl: "/assets/devotional-table.webp",
    gatherings: demoData.meetings.filter(
      (item) =>
        item.visibility === "public" &&
        ["upcoming", "live"].includes(gatheringLifecycle(item)),
    ),
    testimonies: demoData.testimonies,
    galleries: [
      {
        id: "gallery-1",
        organizationId: "demo-org",
        gatheringId: "meeting-1",
        groupId: "demo-group",
        slug: "life-around-the-table",
        title: "Life around the table",
        description:
          "Ordinary evenings made sacred by presence, prayer, and a shared meal.",
        coverUrl: "/assets/devotional-table.webp",
        publishedAt: new Date().toISOString(),
        photos: [
          {
            id: "photo-1",
            imageUrl: "/assets/devotional-table.webp",
            altText: "An open Bible and a warm drink on a wooden table",
            caption: "Making room to listen.",
          },
          {
            id: "photo-2",
            imageUrl: "/assets/devotional-table.webp",
            altText: "A quiet table prepared for a gathering",
            caption: "Thursday evenings together.",
          },
        ],
      },
    ],
    announcements: demoData.announcements.filter((item) => item.isPublic),
    circles: demoData.groups.filter((item) => item.isPublic),
  };
}

export async function loadPublicSpace(
  client: SupabaseClient | null,
  slug: string,
): Promise<PublicSpace> {
  if (
    !client ||
    (import.meta.env.DEV &&
      new URLSearchParams(window.location.search).get("demo") === "1")
  )
    return demoPublicSpace();
  const { data, error } = await client.rpc("get_circle_public_space", {
    p_org_slug: slug,
  });
  if (error) throw error;
  if (!data) throw new Error("This community page is not available.");
  const space = data as PublicSpace;
  return {
    ...space,
    announcements: space.announcements ?? [],
    gatherings: (space.gatherings ?? []).map((meeting) => ({
      ...meeting,
      scope: meeting.scope ?? (meeting.groupId ? "circle" : "organization"),
      destinationName: meeting.groupId ? meeting.destinationName : "Everyone",
    })),
    testimonies: space.testimonies ?? [],
    galleries: space.galleries ?? [],
    circles: space.circles ?? [],
  };
}

export async function loadPublicGathering(
  client: SupabaseClient | null,
  organizationSlug: string,
  gatheringSlug: string,
) {
  if (!client) {
    return (
      demoData.meetings.find((item) => item.slug === gatheringSlug) ?? null
    );
  }
  const { data, error } = await client.rpc("get_circle_public_gathering", {
    p_org_slug: organizationSlug,
    p_gathering_slug: gatheringSlug,
  });
  if (error) throw error;
  const gathering = (data as { gathering?: PublicSpace["gatherings"][number] } | null)
    ?.gathering || null;
  return gathering
    ? {
        ...gathering,
        scope: gathering.scope ?? (gathering.groupId ? "circle" : "organization"),
        destinationName: gathering.groupId ? gathering.destinationName : "Everyone",
      }
    : null;
}

export async function submitGuestRsvp(
  client: SupabaseClient | null,
  gatheringId: string,
  input: GuestRsvpInput,
) {
  if (!client) return { ok: true, id: "demo-rsvp", connectionId: "demo-connection" };
  const { data, error } = await client.rpc("submit_circle_guest_rsvp", {
    p_gathering_id: gatheringId,
    p_name: input.name,
    p_email: input.email,
    p_phone: input.phone,
    p_status: input.status,
  });
  if (error) throw error;
  return data as { ok: boolean; id: string; connectionId: string };
}

export async function submitCellGroupSignup(
  client: SupabaseClient | null,
  organizationSlug: string,
  input: CellGroupSignupInput,
): Promise<CellGroupSignupResult> {
  if (
    !client ||
    (import.meta.env.DEV &&
      new URLSearchParams(window.location.search).get("demo") === "1")
  ) return { ok: true };
  const { data, error } = await client.rpc("submit_circle_group_signup", {
    p_org_slug: organizationSlug,
    p_first_name: input.firstName.trim(),
    p_last_name: input.lastName.trim(),
    p_birthdate: input.birthdate,
    p_phone: input.phone.trim(),
    p_facebook_contact: input.facebookContact.trim(),
    p_consent: input.consent,
    p_guest_rsvp_id: input.guestRsvpId ?? null,
  });
  if (error) throw error;
  return data as CellGroupSignupResult;
}

export async function requestCircleConnection(
  client: SupabaseClient | null,
  input: {
    groupId: string;
    guestRsvpId?: string;
    name: string;
    email: string;
    phone: string;
    preferredContact: ContactPreference;
    message: string;
    consent: boolean;
  },
) {
  if (!client) return { ok: true, connectionId: "demo-connection" };
  const { data, error } = await client.rpc("request_circle_connection", {
    p_cell_group_id: input.groupId,
    p_guest_rsvp_id: input.guestRsvpId ?? null,
    p_name: input.name,
    p_email: input.email,
    p_phone: input.phone,
    p_preferred_contact: input.preferredContact,
    p_message: input.message,
    p_consent: input.consent,
  });
  if (error) throw error;
  return data as { ok: boolean; connectionId: string; interestId?: string };
}

export async function submitCircleInterest(
  client: SupabaseClient | null,
  listingId: string,
  input: { name: string; contact: string; message: string },
) {
  if (!client) return { ok: true };
  const { data, error } = await client.rpc("submit_circle_interest", {
    p_listing_id: listingId,
    p_name: input.name,
    p_contact: input.contact,
    p_message: input.message,
  });
  if (error) throw error;
  return data;
}

export const galleryBySlug = (
  space: PublicSpace,
  slug: string,
): Gallery | undefined => space.galleries.find((item) => item.slug === slug);
