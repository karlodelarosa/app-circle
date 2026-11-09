import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { AppProvider, useCircles } from "./AppContext";
import { demoData } from "./data/demo";

vi.mock("./lib/supabase", () => ({
  isSupabaseConfigured: false,
  supabase: null,
}));

const testSession = {
  user: { id: "demo-user", email: "member@example.com" },
} as Session;

function ViewOnlyRsvpHarness() {
  const { data, setRsvp } = useCircles();
  const [error, setError] = useState("");
  const meeting = data?.accessibleMeetings?.[0];
  return (
    <div>
      <output>{meeting?.rsvps["demo-user"] ?? "no RSVP"}</output>
      <button
        onClick={() => {
          void setRsvp(meeting!.id, "attending").catch((cause: Error) =>
            setError(cause.message),
          );
        }}
      >
        Force RSVP
      </button>
      {error && <p role="alert">{error}</p>}
    </div>
  );
}

describe("AppProvider gathering access", () => {
  it("rejects RSVP mutations for view-only gatherings before optimistic state changes", async () => {
    const data = structuredClone(demoData);
    data.accessibleMeetings = [
      {
        ...data.meetings[0],
        id: "other-circle-gathering",
        accessLevel: "view",
        rsvps: {},
      },
    ];

    render(
      <AppProvider initialData={data} initialSession={testSession}>
        <ViewOnlyRsvpHarness />
      </AppProvider>,
    );

    fireEvent.click(screen.getByRole("button", { name: "Force RSVP" }));

    expect(
      await screen.findByRole("alert"),
    ).toHaveTextContent("Only members of this gathering’s Circle");
    await waitFor(() => expect(screen.getByText("no RSVP")).toBeInTheDocument());
  });
});
