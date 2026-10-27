import type { SupabaseClient } from "@supabase/supabase-js";
import { submitCellGroupSignup } from "./public";

describe("submitCellGroupSignup", () => {
  it("submits the official organization-level signup contract", async () => {
    const rpc = vi.fn().mockResolvedValue({ data: { ok: true }, error: null });

    await submitCellGroupSignup(
      { rpc } as unknown as SupabaseClient,
      "ministry-lens-church",
      {
        firstName: "  Mara ",
        lastName: " Santos ",
        birthdate: "1995-04-18",
        phone: "+63 917 555 0101",
        facebookContact: "facebook.com/mara.santos",
        consent: true,
      },
    );

    expect(rpc).toHaveBeenCalledWith("submit_circle_group_signup", {
      p_org_slug: "ministry-lens-church",
      p_first_name: "Mara",
      p_last_name: "Santos",
      p_birthdate: "1995-04-18",
      p_phone: "+63 917 555 0101",
      p_facebook_contact: "facebook.com/mara.santos",
      p_consent: true,
      p_guest_rsvp_id: null,
    });
  });

  it("can link a guest-driven signup to its RSVP", async () => {
    const rpc = vi.fn().mockResolvedValue({ data: { ok: true }, error: null });

    await submitCellGroupSignup(
      { rpc } as unknown as SupabaseClient,
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
    );

    expect(rpc).toHaveBeenCalledWith(
      "submit_circle_group_signup",
      expect.objectContaining({ p_guest_rsvp_id: "rsvp-1" }),
    );
  });
});
