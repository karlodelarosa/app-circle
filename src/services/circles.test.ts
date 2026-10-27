import type { SupabaseClient } from "@supabase/supabase-js";
import {
  createPrayer,
  convertGuestConnectionToSignup,
  loadGatheringAttendance,
  loadCellGroupSignups,
  loadGuestRsvpCounts,
  loadPrayerRequests,
  placeCellGroupSignup,
  setGatheringCompletion,
} from "./circles";

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

describe("setGatheringCompletion", () => {
  it("uses the guarded gathering completion RPC", async () => {
    const rpc = vi.fn().mockResolvedValue({ error: null });

    await setGatheringCompletion(
      { rpc } as unknown as SupabaseClient,
      "gathering-1",
      true,
    );

    expect(rpc).toHaveBeenCalledWith("set_circle_gathering_completion", {
      p_gathering_id: "gathering-1",
      p_completed: true,
    });
  });
});

describe("loadGatheringAttendance", () => {
  it("loads the persisted leader roster", async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: {
        saved: true,
        personIds: ["person-1"],
        guestRsvpIds: ["guest-1"],
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
  });
});
