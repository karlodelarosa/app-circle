import type { SupabaseClient } from "@supabase/supabase-js";
import {
  answerPrayer,
  createPrayer,
  convertGuestConnectionToSignup,
  loadGatheringAttendance,
  loadCellGroupSignups,
  loadGuestRsvpCounts,
  loadPrayerRequests,
  loadGatheringReflections,
  loadGatheringReflectionActivity,
  createGatheringReflection,
  updateGatheringReflection,
  deleteGatheringReflection,
  deleteMeeting,
  placeCellGroupSignup,
  saveMeeting,
  saveGatheringCloseout,
  resolveCurrentUserRole,
  searchGatheringAttendancePeople,
  updateGroupDetails,
} from "./circles";

describe("answerPrayer", () => {
  it("records an answered timeline update so followers are notified", async () => {
    const rpc = vi.fn().mockResolvedValue({ data: "update-1", error: null });
    await answerPrayer({ rpc } as unknown as SupabaseClient, "prayer-1", "  God opened a way.  ");
    expect(rpc).toHaveBeenCalledWith("add_circle_prayer_update", {
      p_prayer_id: "prayer-1", p_update_type: "answered", p_body: "God opened a way.",
    });
  });
});

describe("deleteMeeting", () => {
  it("returns the stable deletion result from the guarded RPC", async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: { deleted: false, reason: "has_activity" },
      error: null,
    });

    const result = await deleteMeeting(
      { rpc } as unknown as SupabaseClient,
      "gathering-1",
    );

    expect(rpc).toHaveBeenCalledWith("delete_empty_circle_gathering", {
      p_gathering_id: "gathering-1",
    });
    expect(result).toEqual({ deleted: false, reason: "has_activity" });
  });

  it("rejects an invalid RPC response instead of assuming deletion", async () => {
    const rpc = vi.fn().mockResolvedValue({ data: null, error: null });

    await expect(
      deleteMeeting(
        { rpc } as unknown as SupabaseClient,
        "gathering-1",
      ),
    ).rejects.toThrow("unexpected response");
  });
});

describe("resolveCurrentUserRole", () => {
  it("recognizes an approved leader before they have a Circle", () => {
    expect(
      resolveCurrentUserRole({
        isAdmin: false,
        isApprovedLeader: true,
        groups: [],
      }),
    ).toBe("leader");
  });

  it("does not treat approval as leadership of an unrelated Circle", () => {
    expect(
      resolveCurrentUserRole({
        isAdmin: false,
        isApprovedLeader: false,
        groups: [{ role: "member" }],
      }),
    ).toBe("member");
  });
});

describe("saveMeeting", () => {
  it("persists explicit start and end timestamps", async () => {
    const insert = vi.fn().mockResolvedValue({ error: null });
    const from = vi.fn().mockReturnValue({ insert });

    await saveMeeting(
      { from } as unknown as SupabaseClient,
      "organization-1",
      "user-1",
      "leader-1",
      {
        scope: "circle",
        groupId: "circle-1",
        title: "Dinner and study",
        meetingDate: "2026-11-05T10:00:00.000Z",
        endsAt: "2026-11-05T12:00:00.000Z",
        location: "Santos home",
        studyTopic: "John 15",
        notes: "Bring a Bible.",
      },
    );

    expect(insert).toHaveBeenCalledWith(
      expect.objectContaining({
        starts_at: "2026-11-05T10:00:00.000Z",
        ends_at: "2026-11-05T12:00:00.000Z",
      }),
    );
  });
});

describe("saveGatheringCloseout", () => {
  it("saves newcomers, private notes, and finalization in one request", async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: {
        saved: true,
        status: "completed",
        personIds: ["person-1", "prospect-1"],
        guestRsvpIds: ["guest-1"],
        attendees: [],
        notes: "  Follow up next week.  ",
        finalizedAt: "2026-11-07T00:00:00.000Z",
        editableUntil: "2026-11-14T00:00:00.000Z",
        canEdit: true,
      },
      error: null,
    });

    const result = await saveGatheringCloseout(
      { rpc } as unknown as SupabaseClient,
      "gathering-1",
      {
        personIds: ["person-1"],
        guestRsvpIds: ["guest-1"],
        newcomers: [
          {
            firstName: " Jamie ",
            lastName: " Rivera ",
            birthdate: "1998-06-14",
          },
        ],
        notes: "  Follow up next week.  ",
        complete: true,
      },
    );

    expect(rpc).toHaveBeenCalledWith("save_circle_gathering_closeout", {
      p_gathering_id: "gathering-1",
      p_person_ids: ["person-1"],
      p_guest_rsvp_ids: ["guest-1"],
      p_newcomers: [
        {
          firstName: "Jamie",
          lastName: "Rivera",
          birthdate: "1998-06-14",
        },
      ],
      p_notes: "Follow up next week.",
      p_complete: true,
    });
    expect(result.status).toBe("completed");
  });
});

describe("updateGroupDetails", () => {
  it("updates only the editable Circle details with trimmed values", async () => {
    const eq = vi.fn().mockResolvedValue({ error: null });
    const update = vi.fn().mockReturnValue({ eq });
    const from = vi.fn().mockReturnValue({ update });

    await updateGroupDetails(
      { from } as unknown as SupabaseClient,
      "circle-1",
      {
        name: "  Grace & Ground  ",
        description: "  Learning to follow Jesus together.  ",
        location: "  Santos home  ",
      },
    );

    expect(from).toHaveBeenCalledWith("cell_groups");
    expect(update).toHaveBeenCalledWith({
      name: "Grace & Ground",
      description: "Learning to follow Jesus together.",
      location: "Santos home",
      updated_at: expect.any(String),
    });
    expect(eq).toHaveBeenCalledWith("id", "circle-1");
  });

  it("rejects a blank Circle name before writing", async () => {
    const from = vi.fn();

    await expect(
      updateGroupDetails(
        { from } as unknown as SupabaseClient,
        "circle-1",
        { name: "   ", description: "", location: "" },
      ),
    ).rejects.toThrow("Circle name is required");
    expect(from).not.toHaveBeenCalled();
  });
});

describe("searchGatheringAttendancePeople", () => {
  it("searches active organization People through the gathering-scoped RPC", async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: [
        {
          id: "person-2",
          fullName: "Mara Santos",
          email: "mara@example.com",
        },
      ],
      error: null,
    });

    const results = await searchGatheringAttendancePeople(
      { rpc } as unknown as SupabaseClient,
      "gathering-1",
      "  mara  ",
    );

    expect(rpc).toHaveBeenCalledWith("search_circle_attendance_people", {
      p_gathering_id: "gathering-1",
      p_query: "mara",
    });
    expect(results).toEqual([
      {
        id: "person-2",
        fullName: "Mara Santos",
        email: "mara@example.com",
      },
    ]);
  });

  it("does not search until at least two characters are provided", async () => {
    const rpc = vi.fn();

    const results = await searchGatheringAttendancePeople(
      { rpc } as unknown as SupabaseClient,
      "gathering-1",
      "m",
    );

    expect(results).toEqual([]);
    expect(rpc).not.toHaveBeenCalled();
  });
});

describe("Gathering reflections", () => {
  it("loads a bounded reflection summary for a Circle page", async () => {
    const limit = vi.fn().mockResolvedValue({
      data: [{ people: { first_name: "Mara", last_name: "Santos" } }],
      count: 7,
      error: null,
    });
    const order = vi.fn().mockReturnValue({ limit });
    const eq = vi.fn().mockReturnValue({ order });
    const select = vi.fn().mockReturnValue({ eq });
    const from = vi.fn().mockReturnValue({ select });

    const activity = await loadGatheringReflectionActivity(
      { from } as unknown as SupabaseClient,
      "gathering-1",
    );

    expect(select).toHaveBeenCalledWith(
      "people!circle_gathering_reflections_author_person_id_fkey(first_name,last_name)",
      { count: "exact" },
    );
    expect(order).toHaveBeenCalledWith("created_at", { ascending: false });
    expect(limit).toHaveBeenCalledWith(1);
    expect(activity).toEqual({ count: 7, authorName: "Mara Santos" });
  });

  it("loads reflections in chronological order and maps author names", async () => {
    const limit = vi.fn().mockResolvedValue({
      data: [{
        id: "reflection-1",
        gathering_id: "gathering-1",
        organization_id: "organization-1",
        author_person_id: "person-1",
        body: "Grace meets us in ordinary moments.",
        created_at: "2026-10-28T09:00:00.000Z",
        updated_at: "2026-10-28T09:00:00.000Z",
        people: { first_name: "Mara", last_name: "Santos" },
      }],
      error: null,
    });
    const order = vi.fn().mockReturnValue({ limit });
    const eq = vi.fn().mockReturnValue({ order });
    const select = vi.fn().mockReturnValue({ eq });
    const from = vi.fn().mockReturnValue({ select });

    const reflections = await loadGatheringReflections(
      { from } as unknown as SupabaseClient,
      "gathering-1",
    );

    expect(from).toHaveBeenCalledWith("circle_gathering_reflections");
    expect(eq).toHaveBeenCalledWith("gathering_id", "gathering-1");
    expect(order).toHaveBeenCalledWith("created_at", { ascending: false });
    expect(limit).toHaveBeenCalledWith(200);
    expect(reflections[0]).toEqual(expect.objectContaining({
      id: "reflection-1",
      authorName: "Mara Santos",
      body: "Grace meets us in ordinary moments.",
    }));
  });

  it("trims a reflection before creating it", async () => {
    const insert = vi.fn().mockResolvedValue({ error: null });
    const from = vi.fn().mockReturnValue({ insert });

    await createGatheringReflection(
      { from } as unknown as SupabaseClient,
      { id: "gathering-1", organizationId: "gathering-organization" },
      "person-1",
      "  What stayed with me.  ",
    );

    expect(insert).toHaveBeenCalledWith(expect.objectContaining({
      organization_id: "gathering-organization",
      gathering_id: "gathering-1",
      body: "What stayed with me.",
      author_person_id: "person-1",
      scope: "organization",
      cell_group_id: null,
    }));
  });

  it("can keep a reflection inside its gathering Circle", async () => {
    const insert = vi.fn().mockResolvedValue({ error: null });
    const from = vi.fn().mockReturnValue({ insert });

    await createGatheringReflection(
      { from } as unknown as SupabaseClient,
      { id: "gathering-1", organizationId: "organization-1", groupId: "circle-1" },
      "person-1",
      "Held among this Circle.",
      "circle",
    );

    expect(insert).toHaveBeenCalledWith(expect.objectContaining({
      scope: "circle",
      cell_group_id: "circle-1",
    }));
  });

  it("rejects a live reflection when its gathering has no organization identity", async () => {
    const from = vi.fn();

    await expect(createGatheringReflection(
      { from } as unknown as SupabaseClient,
      { id: "gathering-1" },
      "person-1",
      "What stayed with me.",
    )).rejects.toThrow(/organization identity/i);
    expect(from).not.toHaveBeenCalled();
  });

  it.each(["   ", "x".repeat(2001)])("rejects an invalid reflection body", async (body) => {
    const from = vi.fn();
    await expect(createGatheringReflection(
      { from } as unknown as SupabaseClient,
      { id: "gathering-1", organizationId: "organization-1" },
      "person-1",
      body,
    )).rejects.toThrow(/between 1 and 2,000 characters/i);
    expect(from).not.toHaveBeenCalled();
  });

  it("updates only the requested reflection with trimmed text", async () => {
    const eq = vi.fn().mockResolvedValue({ error: null });
    const update = vi.fn().mockReturnValue({ eq });
    const from = vi.fn().mockReturnValue({ update });

    await updateGatheringReflection(
      { from } as unknown as SupabaseClient,
      "reflection-1",
      "  A clearer reflection.  ",
    );

    expect(update).toHaveBeenCalledWith(expect.objectContaining({ body: "A clearer reflection." }));
    expect(eq).toHaveBeenCalledWith("id", "reflection-1");
  });

  it("deletes only the requested reflection", async () => {
    const eq = vi.fn().mockResolvedValue({ error: null });
    const remove = vi.fn().mockReturnValue({ eq });
    const from = vi.fn().mockReturnValue({ delete: remove });

    await deleteGatheringReflection(
      { from } as unknown as SupabaseClient,
      "reflection-1",
    );

    expect(eq).toHaveBeenCalledWith("id", "reflection-1");
  });
});

describe("loadGuestRsvpCounts", () => {
  it("groups guest responses by gathering and RSVP status", async () => {
    const inFilter = vi.fn().mockResolvedValue({
      data: [
        { gathering_id: "gathering-1", status: "attending" },
        { gathering_id: "gathering-1", status: "attending" },
        { gathering_id: "gathering-1", status: "tentative" },
        { gathering_id: "gathering-2", status: "declined" },
      ],
      error: null,
    });
    const select = vi.fn().mockReturnValue({ in: inFilter });
    const from = vi.fn().mockReturnValue({ select });

    const counts = await loadGuestRsvpCounts(
      { from } as unknown as SupabaseClient,
      ["gathering-1", "gathering-2"],
    );

    expect(from).toHaveBeenCalledWith("circle_guest_rsvps");
    expect(inFilter).toHaveBeenCalledWith("gathering_id", ["gathering-1", "gathering-2"]);
    expect(counts).toEqual({
      "gathering-1": { attending: 2, tentative: 1 },
      "gathering-2": { declined: 1 },
    });
  });
});

describe("Cell Group signups", () => {
  it("loads the organization's unassigned official signups", async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: [{ id: "signup-1", status: "unassigned" }],
      error: null,
    });

    const signups = await loadCellGroupSignups(
      { rpc } as unknown as SupabaseClient,
      "organization-1",
    );

    expect(rpc).toHaveBeenCalledWith("get_circle_group_signups", {
      p_organization_id: "organization-1",
      p_status: "unassigned",
    });
    expect(signups).toHaveLength(1);
  });

  it("places a signup through the guarded RPC", async () => {
    const rpc = vi.fn().mockResolvedValue({ error: null });

    await placeCellGroupSignup(
      { rpc } as unknown as SupabaseClient,
      "signup-1",
      "group-1",
    );

    expect(rpc).toHaveBeenCalledWith("place_circle_group_signup", {
      p_signup_id: "signup-1",
      p_cell_group_id: "group-1",
    });
  });

  it("converts a guest only after a leader attests consent", async () => {
    const rpc = vi.fn().mockResolvedValue({ data: { ok: true }, error: null });

    await convertGuestConnectionToSignup(
      { rpc } as unknown as SupabaseClient,
      "connection-1",
      {
        firstName: " Jamie ", lastName: " Rivera ", birthdate: "1998-06-14",
        phone: " +63 917 555 0198 ", facebookContact: " jamie.rivera ",
        consentConfirmed: true,
      },
    );

    expect(rpc).toHaveBeenCalledWith("convert_guest_connection_to_group_signup", {
      p_connection_id: "connection-1",
      p_first_name: "Jamie",
      p_last_name: "Rivera",
      p_birthdate: "1998-06-14",
      p_phone: "+63 917 555 0198",
      p_facebook_contact: "jamie.rivera",
      p_consent_confirmed: true,
    });
  });
});

describe("loadPrayerRequests", () => {
  it("maps Circle and organization prayers from the secured RPC", async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: [
        {
          id: "circle-prayer",
          groupId: "group-1",
          scope: "circle",
          destinationName: "Grace & Ground",
          userId: "person-2",
          authorName: "Mara Santos",
          title: "Circle prayer",
          description: "For this Circle",
          category: "Family",
          isAnswered: false,
          createdAt: "2026-10-24T00:00:00.000Z",
          prayerCount: 2,
          prayedByMe: true,
        },
        {
          id: "organization-prayer",
          groupId: null,
          scope: "organization",
          destinationName: "Entire organization",
          userId: "person-3",
          authorName: "Joaquin Reyes",
          title: "Organization prayer",
          description: "For everyone",
          category: "Spiritual Growth",
          isAnswered: false,
          createdAt: "2026-10-24T01:00:00.000Z",
          prayerCount: 4,
          prayedByMe: false,
        },
      ],
      error: null,
    });

    const prayers = await loadPrayerRequests(
      { rpc } as unknown as SupabaseClient,
      "group-1",
    );

    expect(rpc).toHaveBeenCalledWith("get_circle_prayers", {
      p_cell_group_id: "group-1",
    });
    expect(prayers).toEqual([
      expect.objectContaining({
        id: "circle-prayer",
        scope: "circle",
        groupId: "group-1",
        destinationName: "Grace & Ground",
      }),
      expect.objectContaining({
        id: "organization-prayer",
        scope: "organization",
        groupId: undefined,
        destinationName: "Entire organization",
      }),
    ]);
  });

  it("requests organization prayers only when no Circle is selected", async () => {
    const rpc = vi.fn().mockResolvedValue({ data: [], error: null });

    await loadPrayerRequests(
      { rpc } as unknown as SupabaseClient,
      undefined,
    );

    expect(rpc).toHaveBeenCalledWith("get_circle_prayers", {
      p_cell_group_id: null,
    });
  });
});

describe("createPrayer", () => {
  it("stores organization prayers without a Circle destination", async () => {
    const insert = vi.fn().mockResolvedValue({ error: null });
    const from = vi.fn().mockReturnValue({ insert });

    await createPrayer(
      { from } as unknown as SupabaseClient,
      "organization-1",
      "group-that-must-be-ignored",
      "person-1",
      {
        title: "Prayer for everyone",
        description: "Please pray together.",
        category: "Spiritual Growth",
        scope: "organization",
        groupId: "group-that-must-be-ignored",
      },
    );

    expect(insert).toHaveBeenCalledWith(
      expect.objectContaining({
        organization_id: "organization-1",
        cell_group_id: null,
        person_id: "person-1",
        scope: "organization",
      }),
    );
  });

  it("stores Circle prayers with the selected Circle destination", async () => {
    const insert = vi.fn().mockResolvedValue({ error: null });
    const from = vi.fn().mockReturnValue({ insert });

    await createPrayer(
      { from } as unknown as SupabaseClient,
      "organization-1",
      "group-1",
      "person-1",
      {
        title: "Prayer for our Circle",
        description: "Please pray together.",
        category: "Family",
        scope: "circle",
      },
    );

    expect(insert).toHaveBeenCalledWith(
      expect.objectContaining({
        cell_group_id: "group-1",
        scope: "circle",
      }),
    );
  });
});

describe("loadGatheringAttendance", () => {
  it("loads the persisted leader roster", async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: {
        saved: true,
        personIds: ["person-1"],
        guestRsvpIds: ["guest-1"],
        attendees: [],
        notes: "Follow up next week.",
        finalizedAt: "2026-11-07T00:00:00.000Z",
        editableUntil: "2026-11-14T00:00:00.000Z",
        canEdit: true,
      },
      error: null,
    });

    const attendance = await loadGatheringAttendance(
      { rpc } as unknown as SupabaseClient,
      "gathering-1",
    );

    expect(rpc).toHaveBeenCalledWith("get_circle_gathering_attendance", {
      p_gathering_id: "gathering-1",
    });
    expect(attendance.saved).toBe(true);
    expect(attendance.personIds).toEqual(["person-1"]);
    expect(attendance.notes).toBe("Follow up next week.");
  });
});
