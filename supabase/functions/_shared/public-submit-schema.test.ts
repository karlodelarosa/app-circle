import { validatePublicSubmission } from "./public-submit-schema.ts";

describe("validatePublicSubmission", () => {
  it("normalizes a valid guest RSVP", () => {
    expect(validatePublicSubmission({
      action: "guest_rsvp",
      botToken: "verified-token",
      payload: {
        gatheringId: "6d4d7a8e-48ac-4b1b-8b15-1fcbdf0ca77b",
        name: "  Mara Santos  ",
        email: "MARA@example.com",
        phone: "+63 917 555 0101",
        status: "attending",
      },
    })).toEqual({
      ok: true,
      value: {
        action: "guest_rsvp",
        botToken: "verified-token",
        payload: {
          gatheringId: "6d4d7a8e-48ac-4b1b-8b15-1fcbdf0ca77b",
          name: "Mara Santos",
          email: "mara@example.com",
          phone: "+63 917 555 0101",
          status: "attending",
        },
      },
    });
  });

  it("rejects malformed contact information and forged identifiers", () => {
    const result = validatePublicSubmission({
      action: "circle_connection",
      botToken: "verified-token",
      payload: {
        groupId: "not-a-uuid",
        name: "Mara",
        email: "not-an-email",
        phone: "123",
        preferredContact: "email",
        message: "Hello",
        consent: true,
      },
    });

    expect(result).toEqual({ ok: false, error: "Invalid submission" });
  });

  it("requires consent for connection and signup submissions", () => {
    const result = validatePublicSubmission({
      action: "group_signup",
      botToken: "verified-token",
      payload: {
        organizationSlug: "ministry-lens-church",
        firstName: "Mara",
        lastName: "Santos",
        birthdate: "1995-04-18",
        phone: "+639175550101",
        facebookContact: "",
        consent: false,
      },
    });

    expect(result).toEqual({ ok: false, error: "Invalid submission" });
  });

  it("rejects oversized free text", () => {
    const result = validatePublicSubmission({
      action: "circle_interest",
      botToken: "verified-token",
      payload: {
        listingId: "6d4d7a8e-48ac-4b1b-8b15-1fcbdf0ca77b",
        name: "Mara",
        contact: "mara@example.com",
        message: "x".repeat(1001),
      },
    });

    expect(result).toEqual({ ok: false, error: "Invalid submission" });
  });
});
