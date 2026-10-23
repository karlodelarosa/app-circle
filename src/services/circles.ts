import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  AppData,
  Group,
  Meeting,
  MeetingInput,
  Member,
  PrayerInput,
  PrayerRequest,
  Role,
  RsvpStatus,
  PersonSearchResult,
  GuestConnection,
  Gallery,
  ContactPreference,
  CirclePublicListing,
  ApprovedLeader,
  ContentAssignment,
} from "../types";
import { optimizeGatheringCover, publicStoragePath } from "../lib/images";

const one = (value: any) => (Array.isArray(value) ? value[0] : value);
const fullName = (person: any) =>
  [person?.first_name, person?.last_name].filter(Boolean).join(" ") ||
  "Circle member";

export async function loadAppData(
  client: SupabaseClient,
  userId: string,
  preferredGroupId?: string,
): Promise<AppData> {
  const [{ data: rawContext, error: contextError }, accountResult] = await Promise.all([
    client.rpc("get_my_circle_context"),
    client.rpc("get_my_circle_account_state"),
  ]);
  if (contextError) throw contextError;
  if (accountResult.error) throw accountResult.error;
  const context = rawContext as any;
  if (!context?.organization)
    throw new Error("No Circles organization is linked to this account.");

  const groups: Group[] = (context.groups ?? []).map((row: any) => ({
    id: row.id,
    organizationId: context.organization.id,
    name: row.name,
    description: row.description ?? "",
    regularSchedule: "",
    location: row.location ?? "",
    leaderId: row.leaderPersonId ?? undefined,
    role: row.role as Role,
  }));
  const group =
    groups.find((item) => item.id === preferredGroupId) ??
    groups.find((item) => item.role === "admin" || item.role === "leader") ??
    groups[0] ??
    null;
  const profile = context.profile ?? {};
  const currentUser = {
    id: userId,
    personId: context.personId ?? undefined,
    fullName:
      [profile.firstName, profile.lastName].filter(Boolean).join(" ") ||
      "Circle member",
    email: "",
    avatarUrl: profile.avatarUrl ?? undefined,
    role: (context.isAdmin
      ? "admin"
      : groups.some((item) => item.role === "leader")
        ? "leader"
        : "member") as Role,
  };

  const base: AppData = {
    organization: {
      id: context.organization.id,
      name: context.organization.name,
      imageUrl: context.organization.image ?? undefined,
      subscriptionStatus: context.organization.status ?? "inactive",
      circlesEnabled: true,
      slug: context.organization.slug ?? context.organization.id,
    },
    groups,
    group,
    members: [],
    meetings: [],
    prayers: [],
    announcements: [],
    testimonies: [],
    galleries: [],
    publicCircleListings: [],
    approvedLeaders: [],
    contentAssignments: [],
    currentUser,
    connectionAttentionCount: 0,
    account: {
      kind: accountResult.data?.kind,
      loginId: accountResult.data?.loginId ?? undefined,
      mustChangePassword: Boolean(accountResult.data?.mustChangePassword),
      status: accountResult.data?.status,
    },
  };
  const [attentionResult, listingsResult, approvedLeadersResult, assignmentsResult, dashboardResult] = await Promise.all([
    client.rpc("get_circle_connection_attention_count"),
    client
      .from("circle_public_listings")
      .select("id,organization_id,cell_group_id,public_slug,description,cover_url,is_published")
      .eq("organization_id", context.organization.id),
    context.isAdmin
      ? client.rpc("get_circle_approved_leaders")
      : Promise.resolve({ data: [], error: null }),
    context.isAdmin
      ? client.rpc("get_circle_content_assignments")
      : Promise.resolve({ data: [], error: null }),
    client.rpc("get_circle_dashboard"),
  ]);
  if (!attentionResult.error)
    base.connectionAttentionCount = Number(attentionResult.data ?? 0);
  if (listingsResult.error) throw listingsResult.error;
  if (approvedLeadersResult.error) throw approvedLeadersResult.error;
  if (assignmentsResult.error) throw assignmentsResult.error;
  if (dashboardResult.error) throw dashboardResult.error;
  base.approvedLeaders = (approvedLeadersResult.data ?? []) as ApprovedLeader[];
  base.contentAssignments = (assignmentsResult.data ?? []) as ContentAssignment[];
  base.publicCircleListings = (listingsResult.data ?? []).map((row: any) => ({
    id: row.id,
    organizationId: row.organization_id,
    groupId: row.cell_group_id,
    slug: row.public_slug,
    description: row.description ?? "",
    coverUrl: row.cover_url ?? undefined,
    isPublished: Boolean(row.is_published),
  }));
  const dashboard = (dashboardResult.data ?? {}) as any;
  base.accessibleMeetings = (dashboard.meetings ?? []) as Meeting[];
  base.organizationMembers = (dashboard.members ?? []).map((member: any) => ({
    ...member,
    membershipId: member.membershipId ?? `organization-${member.id}`,
    role: member.role ?? "member",
    discipleshipBadge: false,
  })) as Member[];
  base.dashboard = {
    meetings: base.accessibleMeetings,
    prayers: dashboard.prayers ?? [],
    announcements: dashboard.announcements ?? [],
    galleries: dashboard.galleries ?? [],
  };
  if (!group) return base;

  const [membersResult, gatheringsResult, prayersResult, accountStatusesResult, badgesResult] = await Promise.all([
    client
      .from("cell_group_members")
      .select(
        "id, person_id, role, people!cell_group_members_person_id_fkey(id, first_name, last_name, email)",
      )
      .eq("cell_group_id", group.id),
    client
      .from("circle_gatherings")
      .select("*")
      .eq("cell_group_id", group.id)
      .not("assignment_confirmed_at", "is", null)
      .order("starts_at"),
    client
      .from("circle_prayer_requests")
      .select(
        "*, people!circle_prayer_requests_person_id_fkey(first_name, last_name)",
      )
      .eq("cell_group_id", group.id)
      .order("created_at", { ascending: false }),
    currentUser.role === "admin" || group.role === "leader"
      ? client.rpc("get_circle_member_account_statuses", { p_cell_group_id: group.id })
      : Promise.resolve({ data: [], error: null }),
    client.rpc("get_circle_member_badges", { p_cell_group_id: group.id }),
  ]);
  for (const result of [membersResult, gatheringsResult, prayersResult, accountStatusesResult, badgesResult])
    if (result.error) throw result.error;

  const gatheringIds = (gatheringsResult.data ?? []).map((row: any) => row.id);
  const prayerIds = (prayersResult.data ?? []).map((row: any) => row.id);
  const [rsvpsResult, clicksResult] = await Promise.all([
    gatheringIds.length
      ? client
          .from("circle_gathering_rsvps")
          .select("gathering_id, person_id, status")
          .in("gathering_id", gatheringIds)
      : Promise.resolve({ data: [], error: null }),
    prayerIds.length
      ? client
          .from("circle_prayer_clicks")
          .select("prayer_id, person_id")
          .in("prayer_id", prayerIds)
      : Promise.resolve({ data: [], error: null }),
  ]);
  if (rsvpsResult.error) throw rsvpsResult.error;
  if (clicksResult.error) throw clicksResult.error;

  const accountStatuses = new Map((accountStatusesResult.data ?? []).map((item: any) => [item.personId, item]));
  const badges = new Map((badgesResult.data ?? []).map((item: any) => [item.personId, item]));
  const members: Member[] = (membersResult.data ?? []).map((row: any) => {
    const person = one(row.people);
    const badge = badges.get(row.person_id) as any;
    return {
      id: row.person_id,
      personId: row.person_id,
      membershipId: row.id,
      role: row.role === "Leader" ? "leader" : "member",
      fullName: fullName(person),
      email: person?.email ?? "",
      avatarUrl: undefined,
      account: accountStatuses.get(row.person_id) as any,
      discipleshipBadge: Boolean(badge?.discipleshipBadge),
      badgeSource: badge?.badgeSource ?? undefined,
      badgeAwardedAt: badge?.badgeAwardedAt ?? undefined,
      leadershipStatus: badge?.leadershipStatus ?? undefined,
    };
  });
  const rsvps = rsvpsResult.data ?? [];
  const meetings: Meeting[] = (gatheringsResult.data ?? []).map((row: any) => ({
    id: row.id,
    groupId: row.cell_group_id ?? undefined,
    scope: row.scope ?? "circle",
    destinationName: group.name,
    canManage: currentUser.role === "admin" || group.role === "leader",
    title: row.title,
    meetingDate: row.starts_at,
    location: row.location ?? "",
    studyTopic: row.study_topic ?? "",
    notes: row.notes ?? "",
    status: row.status === "cancelled" ? "cancelled" : "scheduled",
    createdBy: row.created_by,
    assignedLeaderId: row.leader_person_id ?? undefined,
    checkinCode: row.checkin_code ?? undefined,
    checkinClosesAt: row.checkin_closes_at ?? undefined,
    rsvps: Object.fromEntries(
      rsvps
        .filter((r: any) => r.gathering_id === row.id)
        .map((r: any) => [r.person_id, r.status]),
    ),
    organizationId: row.organization_id,
    slug: row.public_slug ?? undefined,
    summary: row.summary ?? "",
    coverUrl: row.cover_url ?? undefined,
    visibility: row.visibility ?? "private",
    publishedAt: row.published_at ?? undefined,
    guestRsvpEnabled: Boolean(row.guest_rsvp_enabled),
    assignmentConfirmedAt: row.assignment_confirmed_at ?? undefined,
  }));
  const clicks = clicksResult.data ?? [];
  const prayers: PrayerRequest[] = (prayersResult.data ?? []).map(
    (row: any) => {
      const prayerClicks = clicks.filter(
        (click: any) => click.prayer_id === row.id,
      );
      return {
        id: row.id,
        groupId: row.cell_group_id,
        userId: row.person_id,
        authorName: fullName(one(row.people)),
        title: row.title,
        description: row.description ?? "",
        category: row.category,
        isAnswered: row.is_answered,
        answeredNotes: row.answered_notes ?? undefined,
        createdAt: row.created_at,
        prayerCount: prayerClicks.length,
        prayedByMe: Boolean(
          context.personId &&
          prayerClicks.some(
            (click: any) => click.person_id === context.personId,
          ),
        ),
      };
    },
  );
  const [announcementsResult, testimoniesResult, galleriesResult] = await Promise.all([
    client
      .from("circle_announcements")
      .select("*")
      .eq("organization_id", context.organization.id)
      .or(`cell_group_id.is.null,cell_group_id.eq.${group.id}`)
      .not("assignment_confirmed_at", "is", null)
      .order("published_at", { ascending: false })
      .limit(12),
    client
      .from("circle_testimonies")
      .select("*")
      .eq("organization_id", context.organization.id)
      .eq("cell_group_id", group.id)
      .not("assignment_confirmed_at", "is", null)
      .in("status", ["draft", "published"])
      .order("created_at", { ascending: false })
      .limit(6),
    client
      .from("circle_galleries")
      .select("id,organization_id,cell_group_id,public_slug,title,description,cover_url,published_at,assignment_confirmed_at,circle_gallery_photos(id,image_url,caption,alt_text)")
      .eq("organization_id", context.organization.id)
      .eq("cell_group_id", group.id)
      .not("assignment_confirmed_at", "is", null)
      .eq("status", "published")
      .order("published_at", { ascending: false })
      .limit(6),
  ]);
  const now = Date.now();
  const announcements = (announcementsResult.data ?? [])
    .filter((row: any) => !row.expires_at || new Date(row.expires_at).getTime() > now)
    .map((row: any) => ({
      id: row.id,
      organizationId: row.organization_id,
      groupId: row.cell_group_id ?? undefined,
      title: row.title,
      body: row.body,
      publishedAt: row.published_at,
      expiresAt: row.expires_at ?? undefined,
      isPublic: Boolean(row.is_public),
      assignmentConfirmedAt: row.assignment_confirmed_at ?? undefined,
    }));
  const testimonies = (testimoniesResult.data ?? []).map((row: any) => ({
    id: row.id,
    organizationId: row.organization_id,
    groupId: row.cell_group_id ?? undefined,
    slug: row.public_slug,
    title: row.title,
    body: row.body,
    authorName: row.author_display_name,
    authorPersonId: row.author_person_id ?? undefined,
    imageUrl: row.image_url ?? undefined,
    publishedAt: row.published_at ?? row.created_at,
    status: row.status,
    assignmentConfirmedAt: row.assignment_confirmed_at ?? undefined,
  }));
  const galleries: Gallery[] = (galleriesResult.data ?? []).map((row: any) => ({
    id: row.id,
    organizationId: row.organization_id,
    groupId: row.cell_group_id ?? undefined,
    slug: row.public_slug,
    title: row.title,
    description: row.description ?? "",
    coverUrl: row.cover_url ?? undefined,
    publishedAt: row.published_at,
    photos: (row.circle_gallery_photos ?? []).map((photo: any) => ({
      id: photo.id,
      imageUrl: photo.image_url,
      caption: photo.caption ?? undefined,
      altText: photo.alt_text ?? "",
    })),
    assignmentConfirmedAt: row.assignment_confirmed_at ?? undefined,
  }));
  return { ...base, members, meetings, prayers, announcements, testimonies, galleries };
}

export async function acceptAccess(client: SupabaseClient) {
  const { error } = await client.rpc("accept_circle_access");
  if (error && !error.message.toLowerCase().includes("no approved"))
    throw error;
}

export async function saveRsvp(
  client: SupabaseClient,
  organizationId: string,
  gatheringId: string,
  personId: string,
  status: RsvpStatus,
) {
  const { error } = await client
    .from("circle_gathering_rsvps")
    .upsert(
      {
        organization_id: organizationId,
        gathering_id: gatheringId,
        person_id: personId,
        status,
      },
      { onConflict: "gathering_id,person_id" },
    );
  if (error) throw error;
}

export async function createPrayer(
  client: SupabaseClient,
  organizationId: string,
  groupId: string,
  personId: string,
  input: PrayerInput,
) {
  const { error } = await client.from("circle_prayer_requests").insert({
    organization_id: organizationId,
    cell_group_id: groupId,
    person_id: personId,
    title: input.title,
    description: input.description,
    category: input.category,
  });
  if (error) throw error;
}

export async function setPrayerClick(
  client: SupabaseClient,
  organizationId: string,
  prayerId: string,
  personId: string,
  prayed: boolean,
) {
  const query = prayed
    ? client
        .from("circle_prayer_clicks")
        .upsert(
          {
            organization_id: organizationId,
            prayer_id: prayerId,
            person_id: personId,
          },
          { onConflict: "prayer_id,person_id" },
        )
    : client
        .from("circle_prayer_clicks")
        .delete()
        .eq("prayer_id", prayerId)
        .eq("person_id", personId);
  const { error } = await query;
  if (error) throw error;
}

export async function answerPrayer(
  client: SupabaseClient,
  prayerId: string,
  answeredNotes: string,
) {
  const { error } = await client
    .from("circle_prayer_requests")
    .update({ is_answered: true, answered_notes: answeredNotes })
    .eq("id", prayerId);
  if (error) throw error;
}

export async function saveMeeting(
  client: SupabaseClient,
  organizationId: string,
  userId: string,
  leaderPersonId: string | undefined,
  input: MeetingInput,
  id?: string,
) {
  const meetingId = id ?? crypto.randomUUID();
  let uploadedPath: string | null = null;
  let nextCoverUrl = input.removeCover ? null : input.coverUrl;
  if (input.coverFile) {
    const cover = await optimizeGatheringCover(input.coverFile);
    uploadedPath = `${organizationId}/gatherings/${meetingId}/cover-${crypto.randomUUID()}.webp`;
    const upload = await client.storage
      .from("circle-public-media")
      .upload(uploadedPath, cover, { contentType: "image/webp" });
    if (upload.error) throw upload.error;
    nextCoverUrl = client.storage
      .from("circle-public-media")
      .getPublicUrl(uploadedPath).data.publicUrl;
  }
  const payload = {
    organization_id: organizationId,
    cell_group_id: input.scope === "organization" ? null : input.groupId,
    scope: input.scope,
    leader_person_id: leaderPersonId ?? null,
    title: input.title,
    starts_at: input.meetingDate,
    location: input.location,
    study_topic: input.studyTopic,
    notes: input.notes,
    summary: input.summary ?? "",
    visibility: input.visibility ?? "private",
    guest_rsvp_enabled: Boolean(input.guestRsvpEnabled),
    published_at:
      input.visibility === "public" ? new Date().toISOString() : null,
    ...(nextCoverUrl !== undefined ? { cover_url: nextCoverUrl } : {}),
  };
  const query = id
    ? client.from("circle_gatherings").update(payload).eq("id", id)
    : client.from("circle_gatherings").insert({
        id: meetingId,
        ...payload,
        created_by: userId,
        public_slug: `${
          input.title
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, "-")
            .replace(/^-|-$/g, "") || "gathering"
        }-${meetingId.slice(0, 8)}`,
      });
  const { error } = await query;
  if (error) {
    if (uploadedPath)
      await client.storage.from("circle-public-media").remove([uploadedPath]);
    throw error;
  }
  if ((input.coverFile || input.removeCover) && input.coverUrl) {
    const oldPath = publicStoragePath(input.coverUrl);
    if (oldPath?.startsWith(`${organizationId}/gatherings/`))
      await client.storage.from("circle-public-media").remove([oldPath]);
  }
  return meetingId;
}

export async function cancelMeeting(client: SupabaseClient, id: string) {
  const { error } = await client
    .from("circle_gatherings")
    .update({ status: "cancelled" })
    .eq("id", id);
  if (error) throw error;
}

export async function saveCirclePublicListing(
  client: SupabaseClient,
  organizationId: string,
  group: Group,
  input: {
    description: string;
    coverFile?: File;
    current?: CirclePublicListing;
  },
) {
  let coverUrl = input.current?.coverUrl ?? null;
  let uploadedPath: string | null = null;
  if (input.coverFile) {
    const cover = await optimizeGatheringCover(input.coverFile);
    uploadedPath = `${organizationId}/circles/${group.id}/cover-${crypto.randomUUID()}.webp`;
    const upload = await client.storage
      .from("circle-public-media")
      .upload(uploadedPath, cover, { contentType: "image/webp" });
    if (upload.error) throw upload.error;
    coverUrl = client.storage
      .from("circle-public-media")
      .getPublicUrl(uploadedPath).data.publicUrl;
  }
  const slug =
    input.current?.slug ||
    `${group.name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "circle"}-${group.id.slice(0, 8)}`;
  const { error } = await client.from("circle_public_listings").upsert(
    {
      organization_id: organizationId,
      cell_group_id: group.id,
      public_slug: slug,
      description: input.description.trim(),
      cover_url: coverUrl,
      is_published: true,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "cell_group_id" },
  );
  if (error) {
    if (uploadedPath)
      await client.storage.from("circle-public-media").remove([uploadedPath]);
    throw error;
  }
  if (uploadedPath && input.current?.coverUrl) {
    const oldPath = publicStoragePath(input.current.coverUrl);
    if (oldPath?.startsWith(`${organizationId}/circles/`))
      await client.storage.from("circle-public-media").remove([oldPath]);
  }
}

export async function unpublishCirclePublicListing(
  client: SupabaseClient,
  listingId: string,
) {
  const { error } = await client
    .from("circle_public_listings")
    .update({ is_published: false, updated_at: new Date().toISOString() })
    .eq("id", listingId);
  if (error) throw error;
}

export async function createGroup(
  client: SupabaseClient,
  input: {
    name: string;
    description: string;
    location: string;
    leaderPersonId?: string;
  },
) {
  const { data, error } = await client.rpc("create_circle_group", {
    p_name: input.name,
    p_description: input.description,
    p_location: input.location,
    p_leader_person_id: input.leaderPersonId ?? null,
  });
  if (error) throw error;
  return data as string;
}

export async function requestMemberAccess(
  client: SupabaseClient,
  groupId: string,
  personId: string,
) {
  const { error } = await client.rpc("request_circle_access", {
    p_cell_group_id: groupId,
    p_person_id: personId,
  });
  if (error) throw error;
}

export async function removeMember(
  client: SupabaseClient,
  membershipId: string,
) {
  const { error } = await client
    .from("cell_group_members")
    .delete()
    .eq("id", membershipId);
  if (error) throw error;
}

export async function openCheckin(client: SupabaseClient, gatheringId: string) {
  const { data, error } = await client.rpc("open_circle_checkin", {
    p_gathering_id: gatheringId,
  });
  if (error) throw error;
  return data as string;
}

export async function closeCheckin(
  client: SupabaseClient,
  gatheringId: string,
) {
  const { error } = await client.rpc("close_circle_checkin", {
    p_gathering_id: gatheringId,
  });
  if (error) throw error;
}

export async function getCheckinContext(client: SupabaseClient, code: string) {
  const { data, error } = await client.rpc("get_circle_checkin_context", {
    p_code: code,
  });
  if (error) throw error;
  if (!data) throw new Error("This check-in code is invalid or has expired.");
  return data as {
    organizationName: string;
    organizationImage?: string;
    groupName: string;
    gatheringTitle: string;
    startsAt: string;
  };
}

export async function guestCheckin(
  client: SupabaseClient,
  input: {
    code: string;
    firstName: string;
    lastName: string;
    phone: string;
    socialContact: string;
  },
) {
  const { data, error } = await client.rpc("guest_circle_checkin", {
    p_code: input.code,
    p_first_name: input.firstName,
    p_last_name: input.lastName,
    p_phone: input.phone,
    p_social_contact: input.socialContact,
  });
  if (error) throw error;
  return data as { ok: boolean; alreadyRecorded: boolean };
}

export async function searchPeople(
  client: SupabaseClient,
  organizationId: string,
  groupId: string,
  query: string,
): Promise<PersonSearchResult[]> {
  const { data, error } = await client.rpc("search_circle_people", {
    p_organization_id: organizationId,
    p_cell_group_id: groupId,
    p_query: query,
  });
  if (error) throw error;
  return (data ?? []) as PersonSearchResult[];
}

export async function addPersonToGroup(
  client: SupabaseClient,
  groupId: string,
  personId: string,
) {
  const { error } = await client.rpc("add_person_to_cell_group", {
    p_cell_group_id: groupId,
    p_person_id: personId,
  });
  if (error) throw error;
}

export async function registerVisitor(
  client: SupabaseClient,
  groupId: string,
  input: {
    firstName: string;
    lastName: string;
    email: string;
    phone: string;
    guestRsvpId?: string;
  },
) {
  const { data, error } = await client.rpc("register_circle_visitor", {
    p_cell_group_id: groupId,
    p_first_name: input.firstName,
    p_last_name: input.lastName,
    p_email: input.email,
    p_phone: input.phone,
    p_guest_rsvp_id: input.guestRsvpId ?? null,
  });
  if (error) throw error;
  return data as { personId: string; matchedExisting: boolean };
}

export async function recordAttendance(
  client: SupabaseClient,
  gatheringId: string,
  personIds: string[],
  guestRsvpIds: string[],
) {
  const { data, error } = await client.rpc("record_circle_attendance", {
    p_gathering_id: gatheringId,
    p_person_ids: personIds,
    p_guest_rsvp_ids: guestRsvpIds,
  });
  if (error) throw error;
  return data as string;
}

export async function loadGuestConnections(
  client: SupabaseClient,
  groupId?: string,
  filter = "active",
): Promise<GuestConnection[]> {
  const { data, error } = await client.rpc("get_circle_connections", {
    p_cell_group_id: groupId ?? null,
    p_filter: filter,
  });
  if (error) throw error;
  return (data ?? []) as GuestConnection[];
}

export async function loadGuestConnection(
  client: SupabaseClient,
  connectionId: string,
): Promise<GuestConnection> {
  const { data, error } = await client.rpc("get_circle_connection", {
    p_connection_id: connectionId,
  });
  if (error) throw error;
  return data as GuestConnection;
}

export async function updateGuestConnection(
  client: SupabaseClient,
  connectionId: string,
  action: "claim" | "unclaim" | "contacted" | "close" | "reopen" | "note",
  note = "",
  groupId?: string,
) {
  const { data, error } = await client.rpc("update_circle_connection", {
    p_connection_id: connectionId,
    p_action: action,
    p_note: note,
    p_cell_group_id: groupId ?? null,
  });
  if (error) throw error;
  return data as GuestConnection;
}

export async function stageWalkIn(
  client: SupabaseClient,
  gatheringId: string,
  input: {
    name: string;
    email: string;
    phone: string;
    preferredContact: ContactPreference;
    consent: boolean;
  },
) {
  const { data, error } = await client.rpc("stage_circle_walk_in", {
    p_gathering_id: gatheringId,
    p_name: input.name,
    p_email: input.email,
    p_phone: input.phone,
    p_preferred_contact: input.preferredContact,
    p_consent: input.consent,
  });
  if (error) throw error;
  return data as { ok: boolean; guestRsvpId: string; connectionId: string };
}

export async function resolveGuestConnection(
  client: SupabaseClient,
  connectionId: string,
  input: {
    personId?: string;
    firstName?: string;
    lastName?: string;
    email?: string;
    phone?: string;
  },
) {
  const { data, error } = await client.rpc("resolve_circle_connection", {
    p_connection_id: connectionId,
    p_person_id: input.personId ?? null,
    p_first_name: input.firstName ?? "",
    p_last_name: input.lastName ?? "",
    p_email: input.email ?? "",
    p_phone: input.phone ?? "",
  });
  if (error) throw error;
  return data as {
    personId: string;
    created: boolean;
    alreadyConnected: boolean;
  };
}
