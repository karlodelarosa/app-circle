import type { SupabaseClient } from "@supabase/supabase-js";
import { createPrayer, loadPrayerRequests } from "./circles";

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
      undefined,
      "person-1",
      {
        title: "Prayer for everyone",
        description: "Please pray together.",
        category: "Spiritual Growth",
        scope: "organization",
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
