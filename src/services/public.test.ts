import type { SupabaseClient } from "@supabase/supabase-js";
import { demoData } from "../data/demo";
import {
  demoPublicSpace,
  requestCircleConnection,
  submitCellGroupSignup,
  submitGuestRsvp,
} from "./public";

describe("demoPublicSpace gathering lifecycle", () => {
  it("keeps a public gathering listed while it is happening", () => {
    vi.useFakeTimers();
    vi.setSystemTime(
      new Date(demoData.meetings[0].meetingDate).getTime() + 60 * 60 * 1000,
    );
    try {
      expect(demoPublicSpace().gatherings.map((item) => item.id)).toContain(
        demoData.meetings[0].id,
      );
    } finally {
      vi.useRealTimers();
    }
  });
});

describe("submitCellGroupSignup", () => {
  it("submits the official organization-level signup contract", async () => {
    const invoke = vi.fn().mockResolvedValue({
      data: { ok: true, data: { ok: true } },
      error: null,
    });

    await submitCellGroupSignup(
      { functions: { invoke } } as unknown as SupabaseClient,
      "ministry-lens-church",
      {
        firstName: "  Mara ",
        lastName: " Santos ",
        birthdate: "1995-04-18",
        phone: "+63 917 555 0101",
        facebookContact: "facebook.com/mara.santos",
        consent: true,
      },
      { botToken: "bot-token" },
    );

    expect(invoke).toHaveBeenCalledWith("circle-public-submit", { body: {
      action: "group_signup",
      botToken: "bot-token",
      payload: {
        organizationSlug: "ministry-lens-church",
        firstName: "Mara",
        lastName: "Santos",
        birthdate: "1995-04-18",
        phone: "+63 917 555 0101",
        facebookContact: "facebook.com/mara.santos",
        consent: true,
        guestRsvpId: null,
      },
    },
    });
  });

  it("can link a guest-driven signup to its RSVP", async () => {
    const invoke = vi.fn().mockResolvedValue({ data: { ok: true, data: { ok: true } }, error: null });

    await submitCellGroupSignup(
      { functions: { invoke } } as unknown as SupabaseClient,
      "ministry-lens-church",
      {
        firstName: "Mara",
        lastName: "Santos",
        birthdate: "1995-04-18",
        phone: "+639175550101",
        facebookContact: "",
        consent: true,
        guestRsvpId: "rsvp-1",
      },
      { botToken: "bot-token" },
    );

    expect(invoke).toHaveBeenCalledWith(
      "circle-public-submit",
      expect.objectContaining({ body: expect.objectContaining({
        payload: expect.objectContaining({ guestRsvpId: "rsvp-1" }),
      }) }),
    );
  });
});

describe("protected public submissions", () => {
  it("sends guest RSVPs through the protected function", async () => {
    const invoke = vi.fn().mockResolvedValue({
      data: { ok: true, data: { ok: true, id: "rsvp-1", connectionId: "connection-1" } },
      error: null,
    });
    const result = await submitGuestRsvp(
      { functions: { invoke } } as unknown as SupabaseClient,
      "6d4d7a8e-48ac-4b1b-8b15-1fcbdf0ca77b",
      { name: "Mara", email: "mara@example.com", phone: "", status: "attending" },
      { botToken: "bot-token" },
    );

    expect(result.id).toBe("rsvp-1");
    expect(invoke).toHaveBeenCalledWith("circle-public-submit", expect.objectContaining({
      body: expect.objectContaining({ action: "guest_rsvp", botToken: "bot-token" }),
    }));
  });

  it("does not expose function or database errors", async () => {
    const invoke = vi.fn().mockResolvedValue({
      data: { ok: false, error: "Submission could not be completed." },
      error: new Error("sensitive database detail"),
    });

    await expect(requestCircleConnection(
      { functions: { invoke } } as unknown as SupabaseClient,
      {
        groupId: "6d4d7a8e-48ac-4b1b-8b15-1fcbdf0ca77b",
        name: "Mara",
        email: "mara@example.com",
        phone: "",
        preferredContact: "email",
        message: "Hello",
        consent: true,
      },
      { botToken: "bot-token" },
    )).rejects.toThrow("Submission could not be completed.");
  });
});
