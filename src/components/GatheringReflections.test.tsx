import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { AppProvider } from "../AppContext";
import { demoData } from "../data/demo";
import type { GatheringReflection } from "../types";
import { GatheringReflections } from "./GatheringReflections";

vi.mock("../lib/supabase", () => ({
  isSupabaseConfigured: false,
  supabase: null,
}));

const reflection: GatheringReflection = {
  id: "reflection-1",
  gatheringId: "meeting-3",
  organizationId: "demo-org",
  authorPersonId: "member-2",
  authorName: "Mara Santos",
  body: "I want to carry this practice into the week.",
  createdAt: "2026-10-28T09:00:00.000Z",
  updatedAt: "2026-10-28T09:00:00.000Z",
};

const renderReflections = (initialReflections: GatheringReflection[] = []) =>
  render(
    <MemoryRouter>
      <AppProvider initialData={structuredClone(demoData)}>
        <GatheringReflections
          meeting={{ ...demoData.meetings[2], status: "completed" }}
          canModerate
          initialReflections={initialReflections}
        />
      </AppProvider>
    </MemoryRouter>,
  );

describe("GatheringReflections", () => {
  it("invites members to continue a completed gathering", () => {
    renderReflections();

    expect(screen.getByRole("heading", { name: "After the gathering" })).toBeInTheDocument();
    expect(screen.getByLabelText("What stayed with you?")).toHaveAttribute("maxlength", "2000");
    expect(screen.getByRole("button", { name: "Share reflection" })).toBeDisabled();
  });

  it("adds a trimmed reflection and offers private next steps", async () => {
    renderReflections();

    fireEvent.change(screen.getByLabelText("What stayed with you?"), {
      target: { value: "  Grace changes how I listen.  " },
    });
    fireEvent.click(screen.getByRole("button", { name: "Share reflection" }));

    expect(await screen.findByText("Grace changes how I listen.")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /turn this into a prayer request/i })).toHaveAttribute("href", "/prayer");
    expect(screen.getByRole("link", { name: /submit it as a testimony/i })).toHaveAttribute("href", "/share-testimony");
  });

  it("lets a gathering leader remove another member's reflection", async () => {
    vi.spyOn(window, "confirm").mockReturnValue(true);
    renderReflections([reflection]);

    expect(screen.queryByRole("button", { name: /edit mara santos's reflection/i })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: /remove mara santos's reflection/i }));

    await waitFor(() => expect(screen.queryByText(reflection.body)).not.toBeInTheDocument());
  });

  it("lets an author edit their own reflection", async () => {
    renderReflections([{
      ...reflection,
      id: "own-reflection",
      authorPersonId: "demo-user",
      authorName: "Karlo de la Rosa",
    }]);

    fireEvent.click(screen.getByRole("button", { name: /edit karlo de la rosa's reflection/i }));
    fireEvent.change(screen.getByLabelText("Edit your reflection"), {
      target: { value: "  A renewed commitment to listen.  " },
    });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => {
      expect(screen.getByText("A renewed commitment to listen.")).toBeInTheDocument();
      expect(screen.getByText(/Edited/)).toBeInTheDocument();
    });
  });
});
