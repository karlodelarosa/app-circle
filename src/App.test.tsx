import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import type { Session } from "@supabase/supabase-js";
import App from "./App";
import { AppProvider } from "./AppContext";
import { demoData } from "./data/demo";

vi.mock("./lib/supabase", () => ({
  isSupabaseConfigured: false,
  supabase: null,
}));
const testSession = {
  access_token: "test-token",
  refresh_token: "test-refresh-token",
  expires_in: 3600,
  token_type: "bearer",
  user: {
    id: "demo-user",
    email: "karlo@example.com",
  },
} as Session;

const renderApp = (path: string, authenticated = true) =>
  render(
    <MemoryRouter initialEntries={[path]}>
      <AppProvider
        initialData={authenticated ? structuredClone(demoData) : null}
        initialSession={authenticated ? testSession : null}
      >
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
    screen.getAllByRole("link", { name: "Join a Circle" }).forEach((link) =>
      expect(link).toHaveAttribute("href", "/ministry-lens-church/circles"),
    );
  });
  it("lets visitors learn about a Circle before opening the interest form", async () => {
    renderApp("/ministry-lens-church/circles/grace-and-ground");
    expect(await screen.findByRole("heading", { name: "Grace & Ground" })).toBeInTheDocument();
    expect(screen.queryByLabelText("Name")).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "I’m interested in joining" }));
    await waitFor(() => expect(screen.getByLabelText("Name")).toHaveFocus());
    expect(screen.getByText(/does not create an account/i)).toBeInTheDocument();
  });
  it("wraps routed content in the shared fade and resets scrolling", () => {
    const { container } = renderApp("/gatherings");
    expect(container.querySelector(".route-reveal")).toBeInTheDocument();
    expect(window.scrollTo).toHaveBeenCalledWith({ top: 0, left: 0, behavior: "auto" });
  });
  it("provides Back and Dashboard controls on nested standalone PWA screens", () => {
    const original = window.matchMedia;
    Object.defineProperty(window, "matchMedia", {
      configurable: true,
      value: vi.fn().mockReturnValue({
        matches: true,
        addEventListener: vi.fn(),
        removeEventListener: vi.fn(),
      }),
    });
    renderApp("/gatherings/meeting-1");
    expect(screen.getByRole("navigation", { name: "App navigation" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Back" })).toBeInTheDocument();
    expect(screen.getByRole("navigation", { name: "App navigation" }).querySelector('a[href="/"]')).toHaveTextContent("Dashboard");
    Object.defineProperty(window, "matchMedia", { configurable: true, value: original });
  });
  it("shows a user-controlled notice when a PWA update is ready", () => {
    renderApp("/");
    act(() => window.dispatchEvent(new Event("circles:pwa-update")));
    expect(screen.getByText("A new version of Circles is ready.")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Later" }));
    expect(screen.queryByText("A new version of Circles is ready.")).not.toBeInTheDocument();
  });
  it("does not lose an update notice raised before the app mounts", () => {
    window.__circlesUpdatePending = true;
    renderApp("/");
    expect(screen.getByText("A new version of Circles is ready.")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Later" }));
    window.__circlesUpdatePending = false;
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
    renderApp("/gatherings/meeting-1");
    const maybe = screen.getByRole("button", { name: "Maybe" });
    const going = screen.getByRole("button", { name: "I’m going" });
    expect(going).toHaveAttribute("aria-pressed", "true");
    fireEvent.click(maybe);
    await waitFor(() => expect(maybe).toHaveAttribute("aria-pressed", "true"));
    expect(going).toHaveAttribute("aria-pressed", "false");
  });
  it("redirects an unauthenticated dashboard visit to SheepCount sign-in", async () => {
    renderApp("/", false);
    expect(
      await screen.findByRole("heading", { name: "Return to your circle." }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("link", { name: "Continue in demo mode" }),
    ).not.toBeInTheDocument();
  });
  it("shows leader gathering controls and prayer navigation", () => {
    renderApp("/gatherings");
    expect(
      screen.getByRole("button", { name: /plan a gathering/i }),
    ).toBeInTheDocument();
    expect(screen.getAllByRole("link", { name: "Prayer" }).length).toBeGreaterThan(0);
    expect(
      screen.getAllByRole("button", { name: "Copy link" }).length,
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
    renderApp("/circles/demo-group");
    expect(
      screen.queryByRole("link", { name: "People" }),
    ).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Add people" }));
    expect(
      screen.getByRole("heading", { name: "Add people to Grace & Ground" }),
    ).toBeInTheDocument();
    expect(screen.getByLabelText("Search People")).toBeInTheDocument();
  });
  it("keeps member login, discipleship, and leadership in one access record", () => {
    renderApp("/circles/demo-group");
    fireEvent.click(screen.getAllByRole("button", { name: "Manage access" })[0]);
    expect(screen.getByRole("heading", { name: "Manage access" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Login" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Discipleship" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Leadership" })).toBeInTheDocument();
    expect(screen.getByText("mara.santos-k7p4")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Award Discipleship badge" })).not.toBeInTheDocument();
  });
  it("lets admins create Circles only with approved SheepCount leaders", () => {
    const adminData = structuredClone(demoData);
    adminData.currentUser.role = "admin";
    adminData.group = { ...adminData.group!, role: "admin" };
    adminData.groups = adminData.groups.map((group) => ({ ...group, role: "admin" }));
    render(
      <MemoryRouter initialEntries={["/circles"]}>
        <AppProvider initialData={adminData} initialSession={testSession}>
          <App />
        </AppProvider>
      </MemoryRouter>,
    );
    fireEvent.click(screen.getByRole("button", { name: "Create a Circle" }));
    expect(screen.getByRole("heading", { name: "Create a Circle" })).toBeInTheDocument();
    expect(screen.getByRole("option", { name: /Karlo de la Rosa/ })).toHaveValue("demo-user");
    expect(screen.queryByRole("option", { name: /Mara Santos/ })).not.toBeInTheDocument();
  });
  it("lets an admin replace a mistaken SheepCount link with a Member ID", () => {
    const adminData = structuredClone(demoData);
    adminData.currentUser.role = "admin";
    adminData.group = { ...adminData.group!, role: "admin" };
    adminData.groups = adminData.groups.map((group) => ({ ...group, role: "admin" }));
    render(
      <MemoryRouter initialEntries={["/circles/demo-group"]}>
        <AppProvider initialData={adminData} initialSession={testSession}>
          <App />
        </AppProvider>
      </MemoryRouter>,
    );
    fireEvent.click(screen.getAllByRole("button", { name: "Manage access" })[0]);
    expect(screen.getByText("SheepCount linked")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Create new Member ID" })).toBeInTheDocument();
    expect(screen.getByText(/original SheepCount account will not be deleted/i)).toBeInTheDocument();
  });
  it("shows an overview before opening a Circle", () => {
    renderApp("/circles");
    expect(
      screen.getByRole("heading", { name: "All Circles" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: /Grace & Ground/ }),
    ).toHaveAttribute("href", "/circles/demo-group");
  });
  it("uses the gathering cover on the dashboard", () => {
    const { container } = renderApp("/");
    expect(
      container.querySelector('a[href="/gatherings/meeting-1"] img[src="/assets/devotional-table.webp"]'),
    ).toBeInTheDocument();
  });
  it("orders the dashboard as hero, following gathering, prayer, announcement, and gallery", () => {
    renderApp("/");
    const hero = screen.getByRole("heading", { name: "Make room for the next gathering." });
    const following = screen.getByRole("heading", { name: "Following gathering" });
    const prayer = screen.getByRole("heading", { name: "Prayer requests" });
    const announcement = screen.getByRole("heading", { name: "Bring a story from your week" });
    const gallery = screen.getByRole("heading", { name: "Life around the table" });
    expect(hero.compareDocumentPosition(following) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(following.compareDocumentPosition(prayer) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(prayer.compareDocumentPosition(announcement) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(announcement.compareDocumentPosition(gallery) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });
  it("keeps the nearest gathering detailed beneath the jumbotron", () => {
    renderApp("/");
    expect(screen.getByRole("heading", { name: "Rooted in grace" })).toBeInTheDocument();
    expect(screen.getByText("Colossians 2:6–7")).toBeInTheDocument();
    expect(screen.getByText("3 going")).toBeInTheDocument();
    expect(screen.getByLabelText(/Karlo de la Rosa, Mara Santos, Ana Lopez going/)).toBeInTheDocument();
  });
  it("summarizes extra attendees and explains when no one is confirmed", () => {
    const fullData = structuredClone(demoData);
    fullData.meetings[0].rsvps = Object.fromEntries(
      fullData.members.map((member) => [member.id, "attending"]),
    );
    const populated = render(
      <MemoryRouter initialEntries={["/"]}>
        <AppProvider initialData={fullData} initialSession={testSession}>
          <App />
        </AppProvider>
      </MemoryRouter>,
    );
    expect(screen.getByText("+1")).toBeInTheDocument();
    expect(screen.getByText("5 going")).toBeInTheDocument();
    populated.unmount();

    const emptyData = structuredClone(demoData);
    emptyData.meetings[0].rsvps = {};
    render(
      <MemoryRouter initialEntries={["/"]}>
        <AppProvider initialData={emptyData} initialSession={testSession}>
          <App />
        </AppProvider>
      </MemoryRouter>,
    );
    expect(screen.getByText("No one confirmed yet")).toBeInTheDocument();
    expect(screen.getByText("0 going")).toBeInTheDocument();
  });
  it("limits the jumbotron to the next three upcoming gatherings", () => {
    const carouselData = structuredClone(demoData);
    const later = new Date();
    later.setDate(later.getDate() + 20);
    carouselData.meetings.push(
      { ...carouselData.meetings[1], id: "meeting-4", title: "Third upcoming", meetingDate: later.toISOString() },
      { ...carouselData.meetings[1], id: "meeting-5", title: "Fourth upcoming", meetingDate: new Date(later.getTime() + 86400000).toISOString() },
    );
    render(
      <MemoryRouter initialEntries={["/"]}>
        <AppProvider initialData={carouselData} initialSession={testSession}>
          <App />
        </AppProvider>
      </MemoryRouter>,
    );
    expect(screen.getAllByRole("button", { name: /Show slide/ })).toHaveLength(4);
    expect(screen.queryByText("Fourth upcoming")).not.toBeInTheDocument();
  });
  it("hides empty editorial sections from a Circle detail", async () => {
    const emptyCircle = structuredClone(demoData);
    emptyCircle.announcements = [];
    emptyCircle.galleries = [];
    emptyCircle.testimonies = [];
    render(
      <MemoryRouter initialEntries={["/circles/demo-group"]}>
        <AppProvider initialData={emptyCircle} initialSession={testSession}>
          <App />
        </AppProvider>
      </MemoryRouter>,
    );
    expect(await screen.findByRole("heading", { name: "Grace & Ground" })).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Grace & Ground updates" })).not.toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Life in Grace & Ground" })).not.toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Stories from Grace & Ground" })).not.toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Our people" })).toBeInTheDocument();
  });
  it("routes ordinary members to My Circle without a Dashboard destination", async () => {
    const memberData = structuredClone(demoData);
    memberData.currentUser = {
      id: "member-auth",
      personId: "member-2",
      fullName: "Mara Santos",
      email: "mara@example.com",
      role: "member",
    };
    memberData.group = { ...memberData.group!, role: "member" };
    memberData.groups = memberData.groups.map((group) => ({ ...group, role: "member" }));
    render(
      <MemoryRouter initialEntries={["/"]}>
        <AppProvider initialData={memberData} initialSession={testSession}>
          <App />
        </AppProvider>
      </MemoryRouter>,
    );
    expect(await screen.findByRole("heading", { name: "Grace & Ground" })).toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "Dashboard" })).not.toBeInTheDocument();
    expect(screen.getAllByRole("link", { name: "Share testimony" }).length).toBeGreaterThan(0);
    expect(screen.getByRole("heading", { name: "Grace & Ground updates" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Life in Grace & Ground" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Stories from Grace & Ground" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Life around the table" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Grace in the ordinary" })).toBeInTheDocument();
  });
  it("forces a generated member to change their temporary password", async () => {
    const memberData = structuredClone(demoData);
    memberData.account = { kind: "generated", loginId: "mara.santos-k7p4", mustChangePassword: true, status: "active" };
    render(
      <MemoryRouter initialEntries={["/gatherings"]}>
        <AppProvider initialData={memberData} initialSession={testSession}>
          <App />
        </AppProvider>
      </MemoryRouter>,
    );
    expect(await screen.findByRole("heading", { name: "Choose your own password." })).toBeInTheDocument();
  });
  it("shows the persistent dashboard return while browsing public pages", async () => {
    renderApp("/ministry-lens-church?browse=1");
    expect(await screen.findByText("Public preview")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Back to dashboard" })).toHaveAttribute("href", "/");
  });
  it("keeps past gatherings out of public lists but preserves their direct link", async () => {
    const list = renderApp("/ministry-lens-church/gatherings");
    expect(await screen.findByRole("heading", { name: "Gatherings" })).toBeInTheDocument();
    expect(screen.queryByText("Carrying one another")).not.toBeInTheDocument();
    list.unmount();
    renderApp("/ministry-lens-church/gatherings/carrying-one-another");
    expect(await screen.findByText("This gathering has ended.")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Save my RSVP" })).not.toBeInTheDocument();
  });
  it("explains announcement audiences and keeps galleries discoverable in Publish", () => {
    renderApp("/content");
    expect(screen.getByRole("heading", { name: "Publish" })).toBeInTheDocument();
    expect(screen.getByText("Life around the table")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Add Announcements" }));
    expect(screen.getByLabelText("Members only")).toBeChecked();
    expect(screen.getByLabelText("Members and public")).not.toBeChecked();
  });
  it("keeps organization announcements out of a Circle detail", () => {
    const scopedData = structuredClone(demoData);
    scopedData.announcements.push({
      id: "organization-update",
      organizationId: "demo-org",
      groupId: undefined,
      title: "Organization-wide update",
      body: "This belongs on the organization dashboard, not a Circle detail.",
      publishedAt: new Date().toISOString(),
      isPublic: true,
    });
    render(
      <MemoryRouter initialEntries={["/circles/demo-group"]}>
        <AppProvider initialData={scopedData} initialSession={testSession}>
          <App />
        </AppProvider>
      </MemoryRouter>,
    );
    expect(screen.getByText("Bring a story from your week")).toBeInTheDocument();
    expect(screen.queryByText("Organization-wide update")).not.toBeInTheDocument();
  });
  it("shows admins an assignment review queue and explicit publishing destination", () => {
    const adminData = structuredClone(demoData);
    adminData.currentUser.role = "admin";
    adminData.group = { ...adminData.group!, role: "admin" };
    adminData.groups = [
      { ...adminData.groups[0], role: "admin" },
      {
        ...adminData.groups[0],
        id: "second-group",
        name: "Second Circle",
        role: "admin",
      },
    ];
    adminData.contentAssignments = [{
      id: "gallery-review",
      type: "gallery",
      title: "Needs a real Circle",
      groupId: "demo-group",
      groupName: "Grace & Ground",
      confirmedAt: undefined,
      publishedAt: new Date().toISOString(),
      hasParticipation: false,
    }];
    render(
      <MemoryRouter initialEntries={["/content"]}>
        <AppProvider initialData={adminData} initialSession={testSession}>
          <App />
        </AppProvider>
      </MemoryRouter>,
    );
    expect(screen.getByRole("heading", { name: "Content assignments" })).toBeInTheDocument();
    expect(screen.getByText("Needs a real Circle")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Review assignment" }));
    expect(screen.getByRole("heading", { name: "Review assignment" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Close" }));
    fireEvent.click(screen.getByRole("button", { name: "Add Galleries" }));
    expect(screen.getByLabelText("Destination")).toHaveValue("");
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
