import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import App from "./App";
import { AppProvider } from "./AppContext";

vi.mock("./lib/supabase", () => ({
  isSupabaseConfigured: false,
  supabase: null,
}));
const renderApp = (path: string) =>
  render(
    <MemoryRouter initialEntries={[path]}>
      <AppProvider>
        <App />
      </AppProvider>
    </MemoryRouter>,
  );

describe("Circles MVP", () => {
  it("renders an organization-specific public homepage", async () => {
    renderApp("/ministry-lens-church");
    expect(
      await screen.findByRole("heading", {
        name: "There is room for you here.",
      }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: "Find a gathering" }),
    ).toHaveAttribute("href", "/ministry-lens-church/gatherings");
  });
  it("stages a public guest RSVP without creating an account", async () => {
    renderApp("/ministry-lens-church/gatherings/rooted-in-grace");
    fireEvent.change(await screen.findByLabelText("Your name"), {
      target: { value: "Jamie Guest" },
    });
    fireEvent.change(screen.getByLabelText("Email"), {
      target: { value: "jamie@example.com" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Save my RSVP" }));
    await waitFor(() =>
      expect(screen.getByText("You’re on the list.")).toBeInTheDocument(),
    );
    expect(
      screen.getByRole("button", { name: "Explore this Circle" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("link", {
        name: "See all gatherings and community activities",
      }),
    ).toHaveAttribute("href", "/ministry-lens-church?browse=1");
    expect(
      screen.getByRole("heading", { name: "Life in Grace & Ground" }),
    ).toBeInTheDocument();
    fireEvent.click(
      screen.getByRole("button", {
        name: "I’d like to connect with this Circle",
      }),
    );
    fireEvent.click(
      screen.getByLabelText(
        "I agree that a Circle leader may contact me about this community.",
      ),
    );
    fireEvent.click(
      screen.getByRole("button", { name: "Ask a leader to contact me" }),
    );
    expect(
      await screen.findByText("A leader will be in touch."),
    ).toBeInTheDocument();
  });
  it("updates one member RSVP choice at a time", async () => {
    renderApp("/");
    const maybe = screen.getByRole("button", { name: "Maybe" });
    const going = screen.getByRole("button", { name: "I’m going" });
    expect(going).toHaveAttribute("aria-pressed", "true");
    fireEvent.click(maybe);
    await waitFor(() => expect(maybe).toHaveAttribute("aria-pressed", "true"));
    expect(going).toHaveAttribute("aria-pressed", "false");
  });
  it("lets a demo visitor open the SheepCount sign-in screen", async () => {
    renderApp("/");
    fireEvent.click(screen.getByRole("button", { name: /Karlo de la Rosa/i }));
    fireEvent.click(
      screen.getByRole("menuitem", { name: "Sign in with SheepCount" }),
    );
    expect(
      await screen.findByRole("heading", { name: "Return to your circle." }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: "Continue in demo mode" }),
    ).toHaveAttribute("href", "/");
  });
  it("shows leader gathering controls and no prayer navigation", () => {
    renderApp("/gatherings");
    expect(
      screen.getByRole("button", { name: /plan a gathering/i }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("link", { name: "Prayer" }),
    ).not.toBeInTheDocument();
    expect(
      screen.getAllByRole("button", { name: "Copy guest link" }).length,
    ).toBeGreaterThan(0);
    expect(
      screen.queryByRole("button", { name: /guest check-in/i }),
    ).not.toBeInTheDocument();
  });
  it("uses clean authenticated URLs and opens content forms in a modal", () => {
    renderApp("/content");
    screen
      .getAllByRole("link", { name: "Gatherings" })
      .forEach((link) => expect(link).toHaveAttribute("href", "/gatherings"));
    expect(screen.getAllByText("Karlo de la Rosa")).toHaveLength(1);
    fireEvent.click(screen.getByRole("button", { name: "Add Testimonies" }));
    expect(screen.getByRole("dialog")).toBeInTheDocument();
    expect(
      screen.getByRole("heading", { name: "New testimony" }),
    ).toBeInTheDocument();
  });
  it("manages participants from the selected Circle", async () => {
    renderApp("/circles");
    expect(
      screen.queryByRole("link", { name: "People" }),
    ).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Add people" }));
    expect(
      screen.getByRole("heading", { name: "Add people to Grace & Ground" }),
    ).toBeInTheDocument();
    expect(screen.getByLabelText("Search People")).toBeInTheDocument();
  });
  it("registers a new walk-in from gathering attendance", async () => {
    renderApp("/gatherings/meeting-1");
    fireEvent.click(await screen.findByRole("button", { name: "Add walk-in" }));
    fireEvent.change(screen.getByLabelText("First name"), {
      target: { value: "Jamie" },
    });
    fireEvent.change(screen.getByLabelText("Last name"), {
      target: { value: "Walkin" },
    });
    fireEvent.change(screen.getByLabelText("Email"), {
      target: { value: "jamie.walkin@example.com" },
    });
    fireEvent.click(
      screen.getByRole("button", { name: "Stage guest and select" }),
    );
    expect(
      await screen.findByText(
        "Jamie Walkin was staged as a guest and selected for attendance. No SheepCount People record was created.",
      ),
    ).toBeInTheDocument();
    expect(screen.getByText("Jamie Walkin")).toBeInTheDocument();
  });
  it("keeps the post-RSVP public journey read-only", async () => {
    renderApp("/ministry-lens-church/gatherings/rooted-in-grace?browse=1");
    expect(
      await screen.findByText("You’re viewing this gathering."),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: "Save my RSVP" }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("button", {
        name: "I’d like to connect with this Circle",
      }),
    ).not.toBeInTheDocument();
    expect(
      screen.getByRole("heading", { name: "Life in Grace & Ground" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: /View this Circle/ }),
    ).toHaveAttribute(
      "href",
      "/ministry-lens-church/circles/grace-and-ground?browse=1",
    );
  });
  it("offers an optional validated cover when planning a gathering", () => {
    renderApp("/gatherings");
    fireEvent.click(screen.getByRole("button", { name: /plan a gathering/i }));
    const input = screen.getByLabelText("Choose cover photo");
    fireEvent.change(input, {
      target: {
        files: [new File(["not-an-image"], "cover.gif", { type: "image/gif" })],
      },
    });
    expect(screen.getByRole("alert")).toHaveTextContent(
      "Choose a JPG, PNG, or WebP image.",
    );
  });
  it("gives leaders a shared guest connection queue and detail actions", async () => {
    renderApp("/connections");
    expect(
      await screen.findByRole("heading", { name: "Guest connections" }),
    ).toBeInTheDocument();
    fireEvent.click(screen.getByRole("link", { name: /Elena Ramos/ }));
    expect(
      await screen.findByRole("heading", { name: "Elena Ramos" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Claim follow-up" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Mark contacted" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Connect to SheepCount" }),
    ).toBeInTheDocument();
  });
});
