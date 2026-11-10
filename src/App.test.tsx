import {
  act,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import { MemoryRouter, useLocation } from "react-router-dom";
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

const renderWithData = (path: string, data: typeof demoData) =>
  render(
    <MemoryRouter initialEntries={[path]}>
      <AppProvider initialData={data} initialSession={testSession}>
        <App />
      </AppProvider>
    </MemoryRouter>,
  );

function LocationProbe() {
  const location = useLocation();
  return (
    <output data-testid="location">
      {location.pathname}
      {location.search}
    </output>
  );
}

describe("Circles MVP", () => {
  it("lets an approved leader without a group create their first Circle", async () => {
    const data = structuredClone(demoData) as typeof demoData & {
      currentUser: typeof demoData.currentUser & { isApprovedLeader: boolean };
    };
    data.groups = [];
    data.group = null;
    data.currentUser.role = "leader";
    data.currentUser.isApprovedLeader = true;

    renderWithData("/circles", data);

    expect(
      await screen.findByRole("heading", { name: "Start your Circle" }),
    ).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Create your Circle" }));
    expect(
      screen.getByRole("dialog", { name: "Create your Circle" }),
    ).toBeInTheDocument();
    expect(screen.queryByLabelText("Primary leader")).not.toBeInTheDocument();
  });
  it("lets an approved leader create another Circle", async () => {
    const data = structuredClone(demoData) as typeof demoData & {
      currentUser: typeof demoData.currentUser & { isApprovedLeader: boolean };
    };
    data.currentUser.role = "leader";
    data.currentUser.isApprovedLeader = true;

    renderWithData("/circles", data);

    fireEvent.click(
      await screen.findByRole("button", { name: "Create a Circle" }),
    );
    expect(
      screen.getByRole("dialog", { name: "Create your Circle" }),
    ).toBeInTheDocument();
    expect(screen.queryByLabelText("Primary leader")).not.toBeInTheDocument();
  });
  it("lets the current leader edit Circle details", async () => {
    renderApp("/circles/demo-group");

    fireEvent.click(
      await screen.findByRole("button", { name: "Circle actions" }),
    );
    fireEvent.click(
      screen.getByRole("menuitem", { name: "Edit Circle details" }),
    );
    const dialog = screen.getByRole("dialog", { name: "Edit Circle details" });
    expect(within(dialog).getByLabelText("Circle name")).toHaveValue(
      "Grace & Ground",
    );
    expect(within(dialog).getByLabelText("Description")).toHaveValue(
      demoData.group?.description,
    );
    expect(within(dialog).getByLabelText("Location")).toHaveValue(
      "18 Acacia Street",
    );

    fireEvent.change(within(dialog).getByLabelText("Circle name"), {
      target: { value: "Grace at Home" },
    });
    fireEvent.change(within(dialog).getByLabelText("Location"), {
      target: { value: "Santos home" },
    });
    fireEvent.click(within(dialog).getByRole("button", { name: "Save changes" }));

    expect(
      await screen.findByRole("heading", { name: "Grace at Home" }),
    ).toBeInTheDocument();
    expect(screen.getAllByText("Santos home").length).toBeGreaterThan(0);
    expect(
      screen.queryByRole("dialog", { name: "Edit Circle details" }),
    ).not.toBeInTheDocument();
  });

  it("does not let an ordinary member edit Circle details", async () => {
    const data = structuredClone(demoData);
    data.currentUser.role = "member";
    data.group = { ...data.group!, role: "member" };
    data.groups = data.groups.map((group) => ({ ...group, role: "member" }));

    renderWithData("/circles/demo-group", data);

    expect(
      await screen.findByRole("heading", { name: "Grace & Ground" }),
    ).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Circle actions" }));
    expect(screen.queryByRole("menuitem", { name: "Edit Circle details" })).not.toBeInTheDocument();
    expect(screen.getByRole("menuitem", { name: "View all Circles" })).toBeInTheDocument();
  });

  it("opens Circle scheduling with the destination fixed", async () => {
    const data = structuredClone(demoData);
    data.meetings = data.meetings.map((meeting) => ({
      ...meeting,
      meetingDate: "2026-01-01T18:00:00.000Z",
      endsAt: "2026-01-01T20:00:00.000Z",
      status: "completed" as const,
    }));

    renderWithData("/circles/demo-group", data);
    fireEvent.click(await screen.findByRole("button", { name: "Schedule gathering" }));

    expect(screen.getByRole("dialog", { name: "Schedule gathering" })).toBeInTheDocument();
    const dialog = screen.getByRole("dialog", { name: "Schedule gathering" });
    expect(within(dialog).getByText("Grace & Ground")).toBeInTheDocument();
    expect(screen.queryByLabelText("Entire organization")).not.toBeInTheDocument();
    expect(screen.queryByLabelText("Destination Circle")).not.toBeInTheDocument();
  });
  it("lets an admin create Circles access for an approved ungrouped leader", async () => {
    const data = structuredClone(demoData);
    data.groups = [];
    data.group = null;
    data.currentUser.role = "admin";
    data.currentUser.isApprovedLeader = false;
    data.approvedLeaders = [
      {
        personId: "approved-leader",
        fullName: "Jamie Leader",
        email: "jamie@example.com",
        accountStatus: "none",
        activeGroupCount: 0,
      },
    ];

    renderWithData("/circles", data);

    expect(
      await screen.findByRole("heading", { name: "Leaders without a Circle" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Create leader access" }),
    ).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Create a Circle" }));
    expect(screen.getByLabelText("Primary leader")).toHaveValue("");
  });
  it("exposes accurate state for the public mobile navigation", async () => {
    renderApp("/ministry-lens-church", false);
    const menu = await screen.findByRole("button", { name: "Open navigation" });
    expect(menu).toHaveAttribute("aria-expanded", "false");
    fireEvent.click(menu);
    expect(
      screen.getByRole("button", { name: "Close navigation" }),
    ).toHaveAttribute("aria-expanded", "true");
  });
  it("presents an organization-wide dashboard with destination labels", async () => {
    const data = structuredClone(demoData);
    const organizationMeeting = {
      ...data.meetings[0],
      id: "organization-gathering",
      title: "One church gathering",
      scope: "organization" as const,
      groupId: undefined,
      destinationName: "Everyone",
      canManage: true,
    };
    data.accessibleMeetings = [organizationMeeting];
    data.organizationMembers = data.members;
    data.dashboard = {
      meetings: [organizationMeeting],
      prayers: [],
      announcements: [],
      galleries: [],
    };
    renderWithData("/", data);
    expect(
      await screen.findByText(
        "Here’s what is happening across Ministry Lens Church.",
      ),
    ).toBeInTheDocument();
    expect(screen.getAllByText("Everyone").length).toBeGreaterThan(0);
    expect(
      screen.getByRole("link", { name: "View all Circles" }),
    ).toHaveAttribute("href", "/circles");
  });

  it("offers organization and Circle destinations when planning a gathering", async () => {
    renderApp("/gatherings");
    fireEvent.click(screen.getByRole("button", { name: "Plan a gathering" }));
    expect(
      await screen.findByLabelText("Entire organization"),
    ).toBeInTheDocument();
    expect(screen.getByLabelText("A specific Circle")).toBeInTheDocument();
  });

  it("defaults a new gathering to two hours and preserves a custom end time", async () => {
    renderApp("/gatherings");
    fireEvent.click(screen.getByRole("button", { name: "Plan a gathering" }));

    const startsAt = await screen.findByLabelText("Starts");
    const endsAt = screen.getByLabelText("Ends");
    fireEvent.change(startsAt, { target: { value: "2026-11-05T18:00" } });
    expect(endsAt).toHaveValue("2026-11-05T20:00");

    fireEvent.change(endsAt, { target: { value: "2026-11-05T21:30" } });
    fireEvent.change(startsAt, { target: { value: "2026-11-05T19:00" } });
    expect(endsAt).toHaveValue("2026-11-05T21:30");
  });

  it("explains where attendance is recorded for a historical gathering", async () => {
    renderApp("/gatherings");
    fireEvent.click(screen.getByRole("button", { name: "Plan a gathering" }));

    fireEvent.change(await screen.findByLabelText("Starts"), {
      target: { value: "2020-01-12T18:00" },
    });

    expect(
      screen.getByText(
        "This gathering has already ended. After creating it, review attendance from Needs attention.",
      ),
    ).toBeInTheDocument();
  });

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
    screen
      .getAllByRole("link", { name: "Join a Circle" })
      .forEach((link) =>
        expect(link).toHaveAttribute("href", "/ministry-lens-church/circles"),
      );
    expect(
      screen.getByRole("link", { name: "Sign up for a Cell Group" }),
    ).toHaveAttribute("href", "/ministry-lens-church/cell-group-signup");
  });
  it("lets visitors learn about a Circle before opening the interest form", async () => {
    renderApp("/ministry-lens-church/circles/grace-and-ground");
    expect(
      await screen.findByRole("heading", { name: "Grace & Ground" }),
    ).toBeInTheDocument();
    expect(screen.queryByLabelText("Name")).not.toBeInTheDocument();
    fireEvent.click(
      screen.getByRole("button", { name: "I’m interested in joining" }),
    );
    await waitFor(() => expect(screen.getByLabelText("Name")).toHaveFocus());
    expect(screen.getByText(/does not create an account/i)).toBeInTheDocument();
  });
  it("offers a separate official Cell Group signup form", async () => {
    renderApp("/ministry-lens-church/cell-group-signup");

    expect(
      await screen.findByRole("heading", { name: "Sign up for a Cell Group" }),
    ).toBeInTheDocument();
    expect(screen.getByLabelText("First name")).toBeRequired();
    expect(screen.getByLabelText("Last name")).toBeRequired();
    expect(screen.getByLabelText("Birthday")).toBeRequired();
    expect(screen.getByLabelText("Mobile number")).toBeInTheDocument();
    expect(
      screen.getByLabelText("Facebook link or username"),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("checkbox", { name: /store these details/i }),
    ).toBeRequired();
    expect(
      screen.getByText(/does not reserve a seat or limit who may attend/i),
    ).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText("First name"), {
      target: { value: "Jamie" },
    });
    fireEvent.change(screen.getByLabelText("Last name"), {
      target: { value: "Rivera" },
    });
    fireEvent.change(screen.getByLabelText("Birthday"), {
      target: { value: "1998-06-14" },
    });
    fireEvent.change(screen.getByLabelText("Facebook link or username"), {
      target: { value: "jamie.rivera" },
    });
    fireEvent.click(
      screen.getByRole("checkbox", { name: /store these details/i }),
    );
    fireEvent.click(screen.getByRole("button", { name: "Submit my signup" }));
    expect(
      await screen.findByRole("heading", { name: "Your signup was received." }),
    ).toBeInTheDocument();
  });
  it("gives leaders a separate official signup placement queue", async () => {
    renderApp("/signups");

    expect(
      await screen.findByRole("heading", { name: "Cell Group signups" }),
    ).toBeInTheDocument();
    expect(screen.getByText("Jamie Rivera")).toBeInTheDocument();
    expect(screen.getByLabelText("Place Jamie Rivera in")).toHaveValue(
      "demo-group",
    );
    expect(
      screen.getByRole("button", { name: "Place in Circle" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: /Cell Group signups/ }),
    ).toHaveAttribute("href", "/signups");

    fireEvent.click(screen.getByRole("button", { name: "Place in Circle" }));
    expect(
      await screen.findByText(/was placed in Grace & Ground/),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("heading", { name: "Jamie Rivera" }),
    ).not.toBeInTheDocument();
  });
  it("wraps routed content in the shared fade and resets scrolling", () => {
    const { container } = renderApp("/gatherings");
    expect(container.querySelector(".route-reveal")).toBeInTheDocument();
    expect(window.scrollTo).toHaveBeenCalledWith({
      top: 0,
      left: 0,
      behavior: "auto",
    });
  });
  it("provides contextual Back and Dashboard controls on nested standalone PWA screens", () => {
    const original = window.matchMedia;
    Object.defineProperty(window, "matchMedia", {
      configurable: true,
      value: vi.fn().mockReturnValue({
        matches: true,
        addEventListener: vi.fn(),
        removeEventListener: vi.fn(),
      }),
    });
    try {
      renderApp("/gatherings/meeting-1");
      expect(
        screen.getByRole("navigation", { name: "App navigation" }),
      ).toBeInTheDocument();
      expect(
        screen.getByRole("link", { name: "Back to Grace & Ground" }),
      ).toHaveAttribute("href", "/circles/demo-group");
      expect(
        screen
          .getByRole("navigation", { name: "App navigation" })
          .querySelector('a[href="/"]'),
      ).toHaveTextContent("Dashboard");
    } finally {
      Object.defineProperty(window, "matchMedia", {
        configurable: true,
        value: original,
      });
    }
  });
  it("shows a user-controlled notice when a PWA update is ready", () => {
    renderApp("/");
    act(() => window.dispatchEvent(new Event("circles:pwa-update")));
    expect(
      screen.getByText("A new version of Circles is ready."),
    ).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Later" }));
    expect(
      screen.queryByText("A new version of Circles is ready."),
    ).not.toBeInTheDocument();
  });
  it("does not lose an update notice raised before the app mounts", () => {
    window.__circlesUpdatePending = true;
    renderApp("/");
    expect(
      screen.getByText("A new version of Circles is ready."),
    ).toBeInTheDocument();
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
    expect(
      screen.getByRole("link", { name: "Sign up for a Cell Group" }),
    ).toHaveAttribute("href", "/ministry-lens-church/cell-group-signup");
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
  it("lets same-organization users view and share another Circle gathering without participating", () => {
    const data = structuredClone(demoData);
    const meeting = {
      ...data.meetings[0],
      id: "other-circle-gathering",
      groupId: "ahs-circle",
      scope: "circle" as const,
      destinationName: "AHS",
      accessLevel: "view" as const,
      canManage: false,
      rsvps: { "member-2": "attending" as const },
    };
    data.currentUser.role = "member";
    data.group = { ...data.group!, role: "member" };
    data.groups = [
      { ...data.group },
      {
        ...data.group,
        id: "ahs-circle",
        name: "AHS",
        role: "member",
      },
    ];
    data.accessibleMeetings = [meeting];
    data.organizationMembers = data.members;

    renderWithData("/gatherings/other-circle-gathering", data);

    expect(screen.getByRole("link", { name: "Back to AHS" })).toHaveAttribute(
      "href",
      "/circles/ahs-circle",
    );
    expect(screen.getByRole("link", { name: "AHS" })).toHaveAttribute(
      "href",
      "/circles/ahs-circle",
    );
    expect(screen.getByText("Mara Santos")).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Share invitation" }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: "I’m going" }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: "Delete gathering" }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("heading", { name: "RSVPs and attendance" }),
    ).not.toBeInTheDocument();
  });

  it("does not offer sharing for a private view-only gathering", () => {
    const data = structuredClone(demoData);
    data.accessibleMeetings = [
      {
        ...data.meetings[0],
        id: "private-other-circle-gathering",
        accessLevel: "view",
        canManage: false,
        destinationName: "AHS",
        visibility: "private",
      },
    ];
    data.organizationMembers = data.members;

    renderWithData("/gatherings/private-other-circle-gathering", data);

    expect(
      screen.queryByRole("button", { name: "Share invitation" }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: "Copy RSVP link" }),
    ).not.toBeInTheDocument();
  });
  it("explains who appears in Who’s coming when no member has confirmed", () => {
    const data = structuredClone(demoData);
    data.meetings[0].rsvps = {};

    renderWithData("/gatherings/meeting-1", data);

    expect(
      screen.getByText("No members have said they’re going yet."),
    ).toBeInTheDocument();
    expect(
      screen.getByText(
        /Guest RSVPs appear in the leader attendance list below/i,
      ),
    ).toBeInTheDocument();
  });
  it("shows confirmed RSVPs as suggestions without marking attendance", async () => {
    renderApp("/gatherings/meeting-1");
    const mara = screen.getByRole("checkbox", { name: /Mara Santos/ });
    expect(mara).not.toBeChecked();
    expect(screen.getAllByText("Going").length).toBeGreaterThan(0);
    fireEvent.click(mara);
    fireEvent.click(screen.getByRole("button", { name: "Maybe" }));

    await waitFor(() =>
      expect(screen.getByRole("button", { name: "Maybe" })).toHaveAttribute(
        "aria-pressed",
        "true",
      ),
    );
    expect(mara).toBeChecked();
  });

  it("closes RSVPs and opens attendance while a gathering is happening", () => {
    const data = structuredClone(demoData);
    data.meetings[0].meetingDate = new Date(
      Date.now() - 60 * 60 * 1000,
    ).toISOString();
    data.meetings[0].endsAt = new Date(
      Date.now() + 60 * 60 * 1000,
    ).toISOString();

    renderWithData("/gatherings/meeting-1", data);

    expect(screen.getAllByText("Happening now").length).toBeGreaterThan(0);
    expect(screen.getByText("RSVPs are closed.")).toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: "I’m going" }),
    ).not.toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Save draft" }),
    ).toBeEnabled();
  });

  it("surfaces ended gatherings that need attendance review", () => {
    renderApp("/gatherings");

    expect(
      screen.getByRole("heading", { name: "Needs attention" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("link", {
        name: /Review attendance.*Carrying one another/i,
      }),
    ).toBeInTheDocument();
    expect(
      within(
        screen.getByRole("link", {
          name: /Review attendance.*Carrying one another/i,
        }).closest("article")!,
      ).getByText("Grace & Ground"),
    ).toBeInTheDocument();
  });

  it("permanently deletes an empty gathering from the gathering list", async () => {
    renderApp("/gatherings");

    fireEvent.click(
      screen.getByRole("button", {
        name: "Actions for A life of prayer",
      }),
    );
    fireEvent.click(screen.getByRole("button", { name: "Delete gathering" }));

    const dialog = screen.getByRole("dialog", {
      name: "Delete A life of prayer?",
    });
    expect(within(dialog).getByText(/cannot be undone/i)).toBeInTheDocument();
    fireEvent.click(
      within(dialog).getByRole("button", { name: "Delete permanently" }),
    );

    await waitFor(() =>
      expect(
        screen.queryByRole("heading", { name: "A life of prayer" }),
      ).not.toBeInTheDocument(),
    );
  });

  it("keeps a gathering with activity and recommends cancellation", async () => {
    renderApp("/gatherings/meeting-3");

    fireEvent.click(screen.getByRole("button", { name: "Delete gathering" }));
    fireEvent.click(
      within(
        screen.getByRole("dialog", { name: "Delete Carrying one another?" }),
      ).getByRole("button", { name: "Delete permanently" }),
    );

    expect(
      await screen.findByText(
        /This gathering has activity and cannot be deleted\. Cancel it instead\./i,
      ),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("heading", { name: "Carrying one another" }),
    ).toBeInTheDocument();
  });

  it("completes an ended gathering atomically", async () => {
    renderApp("/gatherings/meeting-3");

    expect(screen.getByText("Attendance needs review")).toBeInTheDocument();
    const complete = screen.getByRole("button", { name: "Complete gathering" });
    expect(complete).toBeEnabled();
    fireEvent.click(complete);
    expect(
      screen.getByRole("dialog", { name: "Complete this gathering?" }),
    ).toBeInTheDocument();
  });

  it("keeps a completed gathering locked when no correction window is available", () => {
    const data = structuredClone(demoData);
    data.meetings[2].status = "completed";

    renderWithData("/gatherings/meeting-3", data);
    fireEvent.click(screen.getByRole("tab", { name: "Attendance" }));

    screen
      .getAllByRole("checkbox")
      .forEach((checkbox) => expect(checkbox).toBeDisabled());
    expect(
      screen.queryByRole("button", { name: "Save corrections" }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: "Reopen gathering" }),
    ).not.toBeInTheDocument();
  });
  it("keeps closeout controls unavailable before a gathering starts", () => {
    renderApp("/gatherings/meeting-1");

    expect(
      screen.queryByRole("button", { name: "Save draft" }),
    ).not.toBeInTheDocument();
    expect(
      screen.getByText(
        /Attendance becomes available when the gathering begins/i,
      ),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: "Complete gathering" }),
    ).not.toBeInTheDocument();
  });
  it("opens private reflections after a gathering is completed", () => {
    const data = structuredClone(demoData);
    data.meetings[2].status = "completed";

    renderWithData("/gatherings/meeting-3", data);

    const notesTab = screen.getByRole("tab", { name: "Notes" });
    const attendanceTab = screen.getByRole("tab", { name: "Attendance" });
    expect(notesTab).toHaveAttribute("aria-selected", "true");
    expect(notesTab).toHaveAttribute("aria-controls", "gathering-notes-panel");
    expect(attendanceTab).toHaveAttribute(
      "aria-controls",
      "gathering-attendance-panel",
    );
    fireEvent.keyDown(notesTab, { key: "ArrowRight" });
    expect(attendanceTab).toHaveFocus();
    expect(attendanceTab).toHaveAttribute("aria-selected", "true");
    fireEvent.keyDown(attendanceTab, { key: "Home" });
    expect(notesTab).toHaveFocus();
    expect(notesTab).toHaveAttribute("aria-selected", "true");
    expect(
      screen.getByRole("heading", { name: "After the gathering" }),
    ).toBeInTheDocument();
    const reflection = screen.getByLabelText("What stayed with you?");
    fireEvent.change(reflection, { target: { value: "Keep listening." } });

    fireEvent.click(attendanceTab);
    expect(attendanceTab).toHaveAttribute("aria-selected", "true");
    expect(screen.getByRole("heading", { name: "RSVPs and attendance" })).toBeVisible();
    expect(
      screen.getByRole("heading", { name: "After the gathering", hidden: true }),
    ).not.toBeVisible();

    fireEvent.click(notesTab);
    expect(screen.getByLabelText("What stayed with you?")).toHaveValue(
      "Keep listening.",
    );
  });
  it("keeps completed gathering tabs leader-only", () => {
    const data = structuredClone(demoData);
    data.currentUser.role = "member";
    data.group = { ...data.group!, role: "member" };
    data.groups = data.groups.map((group) => ({ ...group, role: "member" }));
    data.meetings[2] = {
      ...data.meetings[2],
      status: "completed",
      accessLevel: "participate",
      canManage: false,
    };

    renderWithData("/gatherings/meeting-3", data);

    expect(screen.queryByRole("tab", { name: "Notes" })).not.toBeInTheDocument();
    expect(screen.queryByRole("tab", { name: "Attendance" })).not.toBeInTheDocument();
    expect(
      screen.getByRole("heading", { name: "After the gathering" }),
    ).toBeVisible();
    expect(
      screen.queryByRole("heading", { name: "RSVPs and attendance" }),
    ).not.toBeInTheDocument();
  });
  it("does not expose reflections before a gathering is completed", () => {
    renderApp("/gatherings/meeting-1");

    expect(
      screen.queryByRole("heading", { name: "After the gathering" }),
    ).not.toBeInTheDocument();
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
  it("preserves a complete prayer link through sign-in", async () => {
    render(
      <MemoryRouter
        initialEntries={[
          "/prayer?circle=demo-group&tab=answered&prayer=prayer-2",
        ]}
      >
        <AppProvider initialData={null} initialSession={null}>
          <App />
          <LocationProbe />
        </AppProvider>
      </MemoryRouter>,
    );

    await waitFor(() =>
      expect(screen.getByTestId("location")).toHaveTextContent(
        "/sign-in?next=%2Fprayer%3Fcircle%3Ddemo-group%26tab%3Danswered%26prayer%3Dprayer-2",
      ),
    );
  });
  it("shows leader gathering controls and prayer navigation", () => {
    renderApp("/gatherings");
    expect(
      screen.getByRole("button", { name: /plan a gathering/i }),
    ).toBeInTheDocument();
    expect(
      screen.getAllByRole("link", { name: "Prayer" }).length,
    ).toBeGreaterThan(0);
    expect(
      screen.getAllByRole("button", { name: "Copy link" }).length,
    ).toBeGreaterThan(0);
    expect(
      screen.queryByRole("button", { name: /guest check-in/i }),
    ).not.toBeInTheDocument();
  });
  it("shares a prayer with the entire organization and labels its audience", async () => {
    renderApp("/prayer");
    fireEvent.click(screen.getByRole("button", { name: "Share a request" }));

    expect(screen.getByRole("button", { name: "Close" })).toHaveFocus();
    expect(screen.getByRole("radio", { name: "A Circle" })).toBeChecked();
    expect(screen.getByRole("combobox", { name: "Choose Circle" })).toHaveValue(
      "demo-group",
    );
    fireEvent.click(
      screen.getByRole("radio", {
        name: /entire organization.*ministry lens church/i,
      }),
    );
    fireEvent.change(screen.getByLabelText("What can we pray for?"), {
      target: { value: "Wisdom for our church" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Share request" }));

    const card = (
      await screen.findByRole("heading", {
        name: "Wisdom for our church",
      })
    ).closest("article");
    expect(card).not.toBeNull();
    expect(within(card!).getByText("Entire organization")).toBeInTheDocument();
  });
  it("does not let a Circle leader answer another member's organization prayer", () => {
    const data = structuredClone(demoData);
    data.prayers.unshift({
      id: "organization-prayer",
      scope: "organization",
      userId: "member-2",
      authorName: "Mara Santos",
      title: "Prayer for every Circle",
      description: "Please pray for our whole church family.",
      category: "Spiritual Growth",
      isAnswered: false,
      createdAt: new Date().toISOString(),
      prayerCount: 0,
      prayedByMe: false,
      destinationName: "Entire organization",
    });
    renderWithData("/prayer", data);

    const card = screen
      .getByRole("heading", { name: "Prayer for every Circle" })
      .closest("article");
    expect(card).not.toBeNull();
    expect(
      within(card!).queryByRole("button", { name: "Mark as answered" }),
    ).not.toBeInTheDocument();
  });
  it("lets a Circle leader answer another member's Circle prayer", () => {
    renderApp("/prayer");

    const card = screen
      .getByRole("heading", { name: "Wisdom for a new season" })
      .closest("article");
    expect(card).not.toBeNull();
    expect(
      within(card!).getByRole("button", { name: "Mark as answered" }),
    ).toBeInTheDocument();
  });
  it("restores a shared prayer board tab from the authenticated URL", () => {
    renderApp("/prayer?circle=demo-group&tab=answered");

    expect(
      screen.getByRole("heading", { name: "A gentle answer" }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("heading", { name: "Wisdom for a new season" }),
    ).not.toBeInTheDocument();
    expect(screen.getByRole("tab", { name: "Answered" })).toHaveAttribute(
      "aria-selected",
      "true",
    );
  });
  it("switches to an accessible Circle and focuses a shared prayer", async () => {
    const data = structuredClone(demoData);
    data.groups.push({
      ...data.groups[0],
      id: "second-circle",
      name: "Second Circle",
    });
    data.prayers.push({
      ...data.prayers[0],
      id: "second-circle-prayer",
      groupId: "second-circle",
      destinationName: "Second Circle",
      title: "Prayer in the second Circle",
    });

    renderWithData(
      "/prayer?circle=second-circle&tab=in-prayer&prayer=second-circle-prayer",
      data,
    );

    const heading = await screen.findByRole("heading", {
      name: "Prayer in the second Circle",
    });
    const card = heading.closest("article");
    expect(card).toHaveClass("ring-2", "ring-olive");
    await waitFor(() => expect(card).toHaveFocus());
    expect(
      screen.queryByRole("heading", { name: "Wisdom for a new season" }),
    ).not.toBeInTheDocument();
  });
  it("reveals no prayer details for an unavailable shared Circle", () => {
    renderApp("/prayer?circle=unknown-circle&tab=in-prayer&prayer=prayer-1");

    expect(
      screen.getByRole("heading", { name: "Prayer unavailable" }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("heading", { name: "Wisdom for a new season" }),
    ).not.toBeInTheDocument();
  });
  it("shares the current board and a specific prayer with private URLs", async () => {
    const share = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(window.navigator, "share", {
      value: share,
      configurable: true,
    });
    renderApp("/prayer");

    fireEvent.click(
      screen.getByRole("button", { name: "Share prayer board" }),
    );
    await waitFor(() =>
      expect(share).toHaveBeenCalledWith(
        expect.objectContaining({
          url: expect.stringContaining(
            "/prayer?circle=demo-group&tab=in-prayer",
          ),
        }),
      ),
    );

    fireEvent.click(
      screen.getByRole("button", {
        name: "Share Wisdom for a new season",
      }),
    );
    await waitFor(() =>
      expect(share).toHaveBeenLastCalledWith(
        expect.objectContaining({
          url: expect.stringContaining(
            "circle=demo-group&tab=in-prayer&prayer=prayer-1",
          ),
        }),
      ),
    );
    Reflect.deleteProperty(window.navigator, "share");
  });
  it("copies a prayer-board link when native sharing is unavailable", async () => {
    Reflect.deleteProperty(window.navigator, "share");
    const writeText = vi.mocked(window.navigator.clipboard.writeText);
    writeText.mockClear();
    renderApp("/prayer?circle=demo-group&tab=answered");

    fireEvent.click(
      screen.getByRole("button", { name: "Share prayer board" }),
    );

    await waitFor(() =>
      expect(writeText).toHaveBeenCalledWith(
        expect.stringContaining(
          "/prayer?circle=demo-group&tab=answered",
        ),
      ),
    );
    expect(
      screen.getByRole("status"),
    ).toHaveTextContent("Prayer board link copied.");
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
    fireEvent.click(
      screen.getAllByRole("button", { name: "Manage access" })[0],
    );
    expect(
      screen.getByRole("heading", { name: "Manage access" }),
    ).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Login" })).toBeInTheDocument();
    expect(
      screen.getByRole("heading", { name: "Discipleship" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("heading", { name: "Leadership" }),
    ).toBeInTheDocument();
    expect(screen.getByText("mara.santos-k7p4")).toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: "Award Discipleship badge" }),
    ).not.toBeInTheDocument();
  });
  it("lets admins create Circles only with approved SheepCount leaders", () => {
    const adminData = structuredClone(demoData);
    adminData.currentUser.role = "admin";
    adminData.group = { ...adminData.group!, role: "admin" };
    adminData.groups = adminData.groups.map((group) => ({
      ...group,
      role: "admin",
    }));
    render(
      <MemoryRouter initialEntries={["/circles"]}>
        <AppProvider initialData={adminData} initialSession={testSession}>
          <App />
        </AppProvider>
      </MemoryRouter>,
    );
    fireEvent.click(screen.getByRole("button", { name: "Create a Circle" }));
    expect(
      screen.getByRole("heading", { name: "Create a Circle" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("option", { name: /Karlo de la Rosa/ }),
    ).toHaveValue("demo-user");
    expect(
      screen.queryByRole("option", { name: /Mara Santos/ }),
    ).not.toBeInTheDocument();
  });
  it("lets an admin replace a mistaken SheepCount link with a Member ID", () => {
    const adminData = structuredClone(demoData);
    adminData.currentUser.role = "admin";
    adminData.group = { ...adminData.group!, role: "admin" };
    adminData.groups = adminData.groups.map((group) => ({
      ...group,
      role: "admin",
    }));
    render(
      <MemoryRouter initialEntries={["/circles/demo-group"]}>
        <AppProvider initialData={adminData} initialSession={testSession}>
          <App />
        </AppProvider>
      </MemoryRouter>,
    );
    fireEvent.click(
      screen.getAllByRole("button", { name: "Manage access" })[0],
    );
    expect(screen.getByText("Legacy Circles login")).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Create new Member ID" }),
    ).toBeInTheDocument();
    expect(
      screen.getByText(/original auth identity will not be deleted/i),
    ).toBeInTheDocument();
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
  it("surfaces the latest completed gathering on a Circle page", () => {
    const data = structuredClone(demoData);
    data.meetings[2].status = "completed";

    renderWithData("/circles/demo-group", data);

    expect(
      screen.getByRole("heading", { name: "Continue the gathering" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: /Continue Carrying one another/i }),
    ).toHaveAttribute("href", "/gatherings/meeting-3");
  });
  it("shows the full Circle gathering history on its own tab", () => {
    const data = structuredClone(demoData);
    const past = Array.from({ length: 6 }, (_, index) => {
      const meetingDate = new Date(
        Date.now() - (index + 2) * 24 * 60 * 60 * 1000,
      ).toISOString();
      return {
        ...data.meetings[2],
        id: `history-${index + 1}`,
        title: `Past gathering ${index + 1}`,
        meetingDate,
        endsAt: new Date(
          new Date(meetingDate).getTime() + 2 * 60 * 60 * 1000,
        ).toISOString(),
        status:
          index === 0
            ? ("completed" as const)
            : index === 1
              ? ("cancelled" as const)
              : ("scheduled" as const),
        rsvps: {},
      };
    });
    data.meetings = [
      data.meetings[0],
      ...past,
      { ...past[0], id: "other-circle-history", groupId: "other-circle" },
    ];

    renderWithData("/circles/demo-group?tab=history", data);

    expect(
      screen.getByRole("heading", { name: "Previous gatherings" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: /Past gathering 5/ }),
    ).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /Past gathering 6/ })).toBeInTheDocument();
    expect(screen.queryByText("other-circle-history")).not.toBeInTheDocument();
    expect(screen.getByRole("tab", { name: "Previous gatherings" })).toHaveAttribute("aria-selected", "true");
    expect(screen.getByText("Completed")).toBeInTheDocument();
    expect(screen.getByText("Cancelled")).toBeInTheDocument();
    expect(screen.getAllByText("Attendance pending").length).toBeGreaterThan(0);
  });
  it("uses the gathering cover on the dashboard", () => {
    const { container } = renderApp("/");
    expect(
      container.querySelector(
        'a[href="/gatherings/meeting-1"] img[src="/assets/devotional-table.webp"]',
      ),
    ).toBeInTheDocument();
  });
  it("orders the dashboard as hero, announcement, upcoming events, highlights, and prayer", () => {
    renderApp("/");
    const hero = screen.getByRole("heading", {
      name: "Make room for one another.",
    });
    const announcement = screen.getByRole("heading", {
      name: "Bring a story from your week",
    });
    const upcoming = screen.getByRole("heading", { name: "Upcoming events" });
    const highlights = screen.getByRole("heading", { name: "Recently in our Circles" });
    const prayer = screen.getByRole("heading", { name: "Prayer requests" });
    expect(
      hero.compareDocumentPosition(announcement) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
    expect(
      announcement.compareDocumentPosition(upcoming) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
    expect(
      upcoming.compareDocumentPosition(highlights) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
    expect(
      highlights.compareDocumentPosition(prayer) &
      Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
  });
  it("keeps prayer requests in a sticky desktop sidebar", () => {
    renderApp("/");

    const sidebar = screen.getByRole("complementary", {
      name: "Prayer requests",
    });
    expect(sidebar).toHaveClass("xl:sticky", "xl:top-24");
    expect(
      screen.getByRole("heading", { name: "Recently in our Circles" })
        .compareDocumentPosition(sidebar) & Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
  });
  it("omits the announcement and highlights sections when they are empty", () => {
    const data = structuredClone(demoData);
    data.announcements = [];
    data.galleries = [];
    data.dashboard = {
      meetings: data.meetings,
      prayers: data.prayers,
      announcements: [],
      galleries: [],
      highlights: [],
    };

    renderWithData("/", data);

    expect(screen.queryByText("Latest announcement")).not.toBeInTheDocument();
    expect(screen.queryByText("No current announcement")).not.toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Recently in our Circles" })).not.toBeInTheDocument();
  });
  it("filters upcoming events and expands more than five matches inline", () => {
    const data = structuredClone(demoData);
    const events = Array.from({ length: 8 }, (_, index) => ({
      ...data.meetings[0],
      id: `filter-event-${index}`,
      title: `Filter event ${index + 1}`,
      meetingDate: new Date(Date.now() + (index + 1) * 86400000).toISOString(),
      endsAt: new Date(Date.now() + (index + 1) * 86400000 + 7200000).toISOString(),
      scope: index < 2 ? "organization" as const : "circle" as const,
      groupId: index < 2 ? undefined : "demo-group",
      destinationName: index < 2 ? "Everyone" : "Grace & Ground",
    }));
    data.dashboard = {
      meetings: events,
      prayers: [],
      announcements: [],
      galleries: [],
      highlights: [],
    };

    renderWithData("/", data);

    const section = screen.getByRole("region", { name: "Upcoming events" });
    expect(within(section).getAllByRole("article")).toHaveLength(5);
    fireEvent.click(within(section).getByRole("button", { name: "Show more" }));
    expect(within(section).getAllByRole("article")).toHaveLength(8);
    expect(within(section).getByRole("button", { name: "Show less" })).toBeInTheDocument();

    fireEvent.click(within(section).getByRole("radio", { name: "Organization" }));
    expect(within(section).getAllByRole("article")).toHaveLength(2);
    expect(within(section).queryByRole("button", { name: "Show less" })).not.toBeInTheDocument();

    fireEvent.click(within(section).getByRole("radio", { name: "Circles" }));
    expect(within(section).getAllByRole("article")).toHaveLength(5);
    expect(within(section).getByRole("button", { name: "Show more" })).toBeInTheDocument();
  });
  it("shows the three newest organization highlights with Circle attribution", () => {
    const data = structuredClone(demoData);
    const highlights = Array.from({ length: 4 }, (_, index) => ({
      ...data.galleries[0],
      id: `highlight-${index}`,
      slug: `highlight-${index}`,
      title: `Circle highlight ${index + 1}`,
      destinationName: index === 0 ? "Grace & Ground" : "Another Circle",
      isOrganizationHighlight: true,
      highlightedAt: new Date(Date.now() - index * 86400000).toISOString(),
    }));
    data.dashboard = {
      meetings: data.meetings,
      prayers: [],
      announcements: [],
      galleries: data.galleries,
      highlights,
    };

    renderWithData("/", data);

    const section = screen.getByRole("region", { name: "Recently in our Circles" });
    expect(within(section).getAllByRole("article")).toHaveLength(3);
    expect(within(section).getByRole("heading", { name: "Circle highlight 1" })).toBeInTheDocument();
    expect(within(section).queryByRole("heading", { name: "Circle highlight 4" })).not.toBeInTheDocument();
    expect(within(section).getByText("Grace & Ground")).toBeInTheDocument();
  });
  it("keeps the nearest gathering detailed beneath the jumbotron", () => {
    renderApp("/");
    expect(
      screen.getByRole("heading", { name: "Rooted in grace" }),
    ).toBeInTheDocument();
    expect(screen.getByText("3 going")).toBeInTheDocument();
    expect(
      screen.getByLabelText(/Karlo de la Rosa, Mara Santos, Ana Lopez going/),
    ).toBeInTheDocument();
  });
  it("includes attending guest RSVPs in dashboard and gathering totals", () => {
    const data = structuredClone(demoData);
    const meeting = data.meetings[0] as (typeof data.meetings)[number] & {
      guestRsvpCounts?: { attending?: number };
    };
    meeting.guestRsvpCounts = { attending: 1 };

    const dashboard = renderWithData("/", data);
    expect(screen.getByText("4 going")).toBeInTheDocument();
    dashboard.unmount();

    renderWithData("/gatherings", data);
    expect(screen.getByText("4 going")).toBeInTheDocument();
  });
  it("shows a guest-only confirmation without rendering an empty avatar group", () => {
    const data = structuredClone(demoData);
    data.meetings[0].rsvps = {};
    const meeting = data.meetings[0] as (typeof data.meetings)[number] & {
      guestRsvpCounts?: { attending?: number };
    };
    meeting.guestRsvpCounts = { attending: 1 };

    renderWithData("/", data);

    expect(screen.getByText("1 guest confirmed")).toBeInTheDocument();
    expect(screen.getByText("1 going")).toBeInTheDocument();
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
    expect(screen.getAllByText("No one confirmed yet").length).toBeGreaterThan(0);
    expect(screen.getAllByText("0 going").length).toBeGreaterThan(0);
  });
  it("limits the jumbotron to the next three upcoming gatherings", () => {
    const carouselData = structuredClone(demoData);
    const later = new Date();
    later.setDate(later.getDate() + 20);
    carouselData.meetings.push(
      {
        ...carouselData.meetings[1],
        id: "meeting-4",
        title: "Third upcoming",
        meetingDate: later.toISOString(),
      },
      {
        ...carouselData.meetings[1],
        id: "meeting-5",
        title: "Fourth upcoming",
        meetingDate: new Date(later.getTime() + 86400000).toISOString(),
      },
    );
    render(
      <MemoryRouter initialEntries={["/"]}>
        <AppProvider initialData={carouselData} initialSession={testSession}>
          <App />
        </AppProvider>
      </MemoryRouter>,
    );
    expect(screen.getAllByRole("button", { name: /Show slide/ })).toHaveLength(
      4,
    );
    const carousel = screen.getByRole("region", { name: "Community highlights" });
    expect(within(carousel).queryByText("Fourth upcoming")).not.toBeInTheDocument();
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
    expect(
      await screen.findByRole("heading", { name: "Grace & Ground" }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("heading", { name: "Grace & Ground updates" }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("heading", { name: "Life in Grace & Ground" }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("heading", { name: "Stories from Grace & Ground" }),
    ).not.toBeInTheDocument();
    expect(
      screen.getByRole("heading", { name: "Our people" }),
    ).toBeInTheDocument();
  });
  it("gives ordinary members a read-only organization Home with app CTAs", async () => {
    const memberData = structuredClone(demoData);
    memberData.currentUser = {
      id: "member-auth",
      personId: "member-2",
      fullName: "Mara Santos",
      email: "mara@example.com",
      role: "member",
      isApprovedLeader: false,
    };
    memberData.group = { ...memberData.group!, role: "member" };
    memberData.groups = memberData.groups.map((group) => ({
      ...group,
      role: "member",
    }));
    render(
      <MemoryRouter initialEntries={["/"]}>
        <AppProvider initialData={memberData} initialSession={testSession}>
          <App />
        </AppProvider>
      </MemoryRouter>,
    );
    expect(
      await screen.findByText(
        "Here’s what is happening across Ministry Lens Church.",
      ),
    ).toBeInTheDocument();
    expect(
      screen.getAllByRole("link", { name: "Home" }).length,
    ).toBeGreaterThan(0);
    expect(
      screen.getAllByRole("link", { name: "My Circle" }).length,
    ).toBeGreaterThan(0);
    expect(
      screen.getAllByRole("link", { name: "Community" }).length,
    ).toBeGreaterThan(0);
    expect(
      screen.getByRole("link", { name: "View community pages" }),
    ).toHaveAttribute("href", "/ministry-lens-church?browse=1");
    expect(
      screen.getByRole("link", { name: "Share a testimony" }),
    ).toHaveAttribute("href", "/share-testimony");
    expect(
      screen.getByRole("link", { name: "View my Circle" }),
    ).toHaveAttribute("href", "/circles/demo-group");
    expect(
      screen.getByRole("link", { name: "Read update" }),
    ).toHaveAttribute(
      "href",
      "/ministry-lens-church/updates?browse=1#announcement-announcement-1",
    );
    expect(
      screen.getByRole("link", { name: "View gallery" }),
    ).toHaveAttribute(
      "href",
      "/ministry-lens-church/galleries/life-around-the-table?browse=1",
    );
    expect(
      screen.queryByRole("link", { name: "Publish" }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("link", { name: "Guest connections" }),
    ).not.toBeInTheDocument();
  });

  it("shows one contextual back action for a standalone Circle gathering", async () => {
    Object.defineProperty(window.navigator, "standalone", {
      value: true,
      configurable: true,
    });
    try {
      renderApp("/gatherings/meeting-1");
      expect(
        await screen.findByRole("heading", { name: "Rooted in grace" }),
      ).toBeInTheDocument();
      const backLinks = screen.getAllByRole("link", {
        name: "Back to Grace & Ground",
      });
      expect(backLinks).toHaveLength(1);
      expect(backLinks[0]).toHaveAttribute("href", "/circles/demo-group");
    } finally {
      Object.defineProperty(window.navigator, "standalone", {
        value: false,
        configurable: true,
      });
    }
  });
  it("forces a generated member to change their temporary password", async () => {
    const memberData = structuredClone(demoData);
    memberData.account = {
      kind: "generated",
      loginId: "mara.santos-k7p4",
      mustChangePassword: true,
      status: "active",
    };
    render(
      <MemoryRouter initialEntries={["/gatherings"]}>
        <AppProvider initialData={memberData} initialSession={testSession}>
          <App />
        </AppProvider>
      </MemoryRouter>,
    );
    expect(
      await screen.findByRole("heading", { name: "Choose your own password." }),
    ).toBeInTheDocument();
    expect(screen.getByText("At least 10 characters")).toBeInTheDocument();
    expect(screen.getByText("One uppercase letter")).toBeInTheDocument();
    expect(screen.getByText("One lowercase letter")).toBeInTheDocument();
    expect(screen.getByText("One number")).toBeInTheDocument();
    const password = screen.getByLabelText("New password");
    const confirmation = screen.getByLabelText("Confirm new password");
    expect(password).toHaveAttribute("type", "password");
    expect(confirmation).toHaveAttribute("type", "password");
    fireEvent.click(screen.getByRole("checkbox", { name: "Show passwords" }));
    expect(password).toHaveAttribute("type", "text");
    expect(confirmation).toHaveAttribute("type", "text");
  });
  it("shows the persistent dashboard return while browsing public pages", async () => {
    renderApp("/ministry-lens-church?browse=1");
    expect(await screen.findByText("Public preview")).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: "Back to dashboard" }),
    ).toHaveAttribute("href", "/");
    expect(
      screen.queryByRole("link", { name: "Sign up for a Cell Group" }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("link", { name: "Sign in" }),
    ).not.toBeInTheDocument();
  });
  it("keeps the published Circle directory read-only in browse mode", async () => {
    renderApp("/ministry-lens-church/circles?browse=1");
    expect(
      await screen.findByRole("heading", { name: "Join a Circle" }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("link", { name: "Sign up for a Cell Group" }),
    ).not.toBeInTheDocument();
  });
  it("keeps past gatherings out of public lists but preserves their direct link", async () => {
    const list = renderApp("/ministry-lens-church/gatherings");
    expect(
      await screen.findByRole("heading", { name: "Gatherings" }),
    ).toBeInTheDocument();
    expect(screen.queryByText("Carrying one another")).not.toBeInTheDocument();
    list.unmount();
    renderApp("/ministry-lens-church/gatherings/carrying-one-another");
    expect(
      await screen.findByText("This gathering has ended."),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: "Save my RSVP" }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("heading", { name: "After the gathering" }),
    ).not.toBeInTheDocument();
  });
  it("explains announcement audiences and keeps galleries discoverable in Publish", () => {
    renderApp("/content");
    expect(
      screen.getByRole("heading", { name: "Publish" }),
    ).toBeInTheDocument();
    expect(screen.getByText("Life around the table")).toBeInTheDocument();
    const announcementRow = screen
      .getByText("Bring a story from your week")
      .closest(".py-4") as HTMLElement;
    expect(within(announcementRow).getByRole("link", { name: /View/ })).toHaveAttribute(
      "href",
      `${window.location.origin}/ministry-lens-church/updates#announcement-announcement-1`,
    );
    expect(within(announcementRow).getByRole("button", { name: /Share/ })).toBeInTheDocument();
    expect(within(announcementRow).getByRole("button", { name: /Copy/ })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Add Announcements" }));
    expect(screen.getByLabelText("Members only")).toBeChecked();
    expect(screen.getByLabelText("Members and public")).not.toBeChecked();
  });
  it("focuses a canonical announcement fragment on public Updates", async () => {
    renderApp(
      "/ministry-lens-church/updates#announcement-announcement-1",
      false,
    );

    const announcement = await screen.findByRole("article");
    expect(announcement).toHaveAttribute("id", "announcement-announcement-1");
    await waitFor(() => expect(announcement).toHaveFocus());
    expect(
      within(announcement).getByRole("button", { name: "Share" }),
    ).toBeInTheDocument();
    expect(
      within(announcement).getByRole("button", { name: "Copy link" }),
    ).toBeInTheDocument();
  });
  it("separates admin publishing tools into URL-backed tabs", () => {
    const data = structuredClone(demoData);
    data.currentUser.role = "admin";
    data.group = { ...data.group!, role: "admin" };

    renderWithData("/content?tab=circle-profiles", data);

    expect(screen.getByRole("tab", { name: "Circle profiles" })).toHaveAttribute(
      "aria-selected",
      "true",
    );
    expect(screen.getByRole("heading", { name: "Circle profiles" })).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Galleries", level: 2 })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("tab", { name: "Content" }));
    expect(screen.getByRole("heading", { name: "Galleries", level: 2 })).toBeInTheDocument();
  });

  it("falls back to Content when a leader requests an admin publishing tab", () => {
    renderApp("/content?tab=assignments");

    expect(screen.getByRole("heading", { name: "Galleries", level: 2 })).toBeInTheDocument();
    expect(
      screen.queryByRole("heading", { name: "Content assignments" }),
    ).not.toBeInTheDocument();
  });
  it("links a new organization highlight to the latest completed gathering", () => {
    const data = structuredClone(demoData);
    data.meetings[2].status = "completed";

    renderWithData("/content", data);
    fireEvent.click(screen.getByRole("button", { name: "Add Galleries" }));

    expect(screen.getByLabelText("Completed gathering")).toHaveValue("meeting-3");
    expect(screen.getByLabelText("Share across the organization")).not.toBeChecked();
    fireEvent.click(screen.getByLabelText("Share across the organization"));
    expect(screen.getByLabelText("Share across the organization")).toBeChecked();
  });
  it("offers removal for an existing organization highlight", () => {
    renderApp("/content");

    expect(screen.getByRole("button", { name: "Remove Life around the table from organization highlights" })).toBeInTheDocument();
  });
  it("lets admins target a completed organization gathering for an organization gallery", () => {
    const data = structuredClone(demoData);
    data.currentUser.role = "admin";
    data.group = { ...data.group!, role: "admin" };
    data.groups = data.groups.map((group) => ({ ...group, role: "admin" }));
    data.accessibleMeetings = [
      {
        ...data.meetings[2],
        id: "organization-recap",
        groupId: undefined,
        scope: "organization",
        destinationName: "Entire organization",
        status: "completed",
        meetingDate: "2026-11-01T18:00:00.000Z",
      },
    ];

    renderWithData("/content", data);
    fireEvent.click(screen.getByRole("button", { name: "Add Galleries" }));
    fireEvent.change(screen.getByLabelText("Destination"), {
      target: { value: "organization" },
    });

    expect(screen.getByLabelText("Completed gathering")).toHaveValue(
      "organization-recap",
    );
    expect(
      screen.getByText(/Organization galleries are automatically highlighted/i),
    ).toBeInTheDocument();
    expect(
      screen.queryByLabelText("Share across the organization"),
    ).not.toBeInTheDocument();
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
    expect(
      screen.getByText("Bring a story from your week"),
    ).toBeInTheDocument();
    expect(
      screen.queryByText("Organization-wide update"),
    ).not.toBeInTheDocument();
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
    adminData.contentAssignments = [
      {
        id: "gallery-review",
        type: "gallery",
        title: "Needs a real Circle",
        groupId: "demo-group",
        groupName: "Grace & Ground",
        confirmedAt: undefined,
        publishedAt: new Date().toISOString(),
        hasParticipation: false,
      },
    ];
    render(
      <MemoryRouter initialEntries={["/content?tab=assignments"]}>
        <AppProvider initialData={adminData} initialSession={testSession}>
          <App />
        </AppProvider>
      </MemoryRouter>,
    );
    expect(
      screen.getByRole("heading", { name: "Content assignments" }),
    ).toBeInTheDocument();
    expect(screen.getByText("Needs a real Circle")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Review assignment" }));
    expect(
      screen.getByRole("heading", { name: "Review assignment" }),
    ).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Close" }));
    fireEvent.click(screen.getByRole("tab", { name: "Content" }));
    fireEvent.click(screen.getByRole("button", { name: "Add Galleries" }));
    expect(screen.getByLabelText("Destination")).toHaveValue("");
  });
  it("stages a newcomer for gathering closeout", async () => {
    const data = structuredClone(demoData);
    data.meetings[0].meetingDate = new Date(
      Date.now() - 60 * 60 * 1000,
    ).toISOString();
    data.meetings[0].endsAt = new Date(
      Date.now() + 60 * 60 * 1000,
    ).toISOString();
    renderWithData("/gatherings/meeting-1", data);
    fireEvent.click(await screen.findByRole("button", { name: "Add newcomer" }));
    fireEvent.change(screen.getByLabelText("First name"), { target: { value: "Jamie" } });
    fireEvent.change(screen.getByLabelText("Last name"), { target: { value: "Walkin" } });
    fireEvent.change(screen.getByLabelText("Birthdate"), { target: { value: "1998-06-14" } });
    const dialog = screen.getByRole("dialog", { name: "Add a newcomer" });
    fireEvent.click(within(dialog).getByRole("button", { name: "Add newcomer" }));
    expect(
      await screen.findByText(
        "Jamie Walkin is staged. Save the closeout to match or create their Prospect record.",
      ),
    ).toBeInTheDocument();
    expect(screen.getByText("Jamie Walkin")).toBeInTheDocument();
    expect(screen.getByText("Staged newcomer")).toBeInTheDocument();
  });

  it("adds an organization member without changing the Circle roster", async () => {
    const data = structuredClone(demoData);
    data.meetings[0].meetingDate = new Date(
      Date.now() - 60 * 60 * 1000,
    ).toISOString();
    data.meetings[0].endsAt = new Date(
      Date.now() + 60 * 60 * 1000,
    ).toISOString();
    data.organizationMembers = [
      ...data.members,
      {
        id: "organization-person",
        membershipId: "organization-organization-person",
        fullName: "Ruth Navarro",
        email: "ruth@example.com",
        role: "member",
        discipleshipBadge: false,
      },
    ];

    renderWithData("/gatherings/meeting-1", data);
    expect(screen.queryByText("Ruth Navarro")).not.toBeInTheDocument();
    fireEvent.click(
      await screen.findByRole("button", { name: "Add existing member" }),
    );
    const dialog = screen.getByRole("dialog", {
      name: "Add an existing member",
    });
    fireEvent.change(within(dialog).getByLabelText("Search organization members"), {
      target: { value: "Ruth" },
    });
    fireEvent.click(within(dialog).getByRole("button", { name: "Search" }));
    fireEvent.click(
      await within(dialog).findByRole("button", { name: "Add Ruth Navarro" }),
    );
    fireEvent.click(within(dialog).getByRole("button", { name: "Close" }));

    const row = screen.getByText("Ruth Navarro").closest("label");
    expect(row).not.toBeNull();
    expect(within(row!).getByRole("checkbox")).toBeChecked();
    expect(within(row!).getByText("Organization member")).toBeInTheDocument();
    expect(data.members.some((member) => member.id === "organization-person")).toBe(
      false,
    );

    fireEvent.click(screen.getByRole("button", { name: "Save draft" }));
    expect(
      await screen.findByText("Closeout saved. This gathering is still scheduled."),
    ).toBeInTheDocument();
    expect(within(row!).getByRole("checkbox")).toBeChecked();

    fireEvent.click(within(row!).getByRole("checkbox"));
    expect(within(row!).getByRole("checkbox")).not.toBeChecked();
  });

  it("prevents duplicate attendance rows for existing Circle members", async () => {
    const data = structuredClone(demoData);
    data.meetings[0].meetingDate = new Date(
      Date.now() - 60 * 60 * 1000,
    ).toISOString();
    data.meetings[0].endsAt = new Date(
      Date.now() + 60 * 60 * 1000,
    ).toISOString();
    data.organizationMembers = data.members;

    renderWithData("/gatherings/meeting-1", data);
    fireEvent.click(
      await screen.findByRole("button", { name: "Add existing member" }),
    );
    const dialog = screen.getByRole("dialog", {
      name: "Add an existing member",
    });
    fireEvent.change(within(dialog).getByLabelText("Search organization members"), {
      target: { value: "Mara" },
    });
    fireEvent.click(within(dialog).getByRole("button", { name: "Search" }));

    expect(
      await within(dialog).findByRole("button", { name: "Mara Santos already listed" }),
    ).toBeDisabled();
  });

  it("quick-adds multiple newcomers without closing the dialog", async () => {
    const data = structuredClone(demoData);
    data.meetings[0].meetingDate = new Date(
      Date.now() - 60 * 60 * 1000,
    ).toISOString();
    data.meetings[0].endsAt = new Date(
      Date.now() + 60 * 60 * 1000,
    ).toISOString();
    renderWithData("/gatherings/meeting-1", data);
    fireEvent.click(await screen.findByRole("button", { name: "Add newcomer" }));
    const firstName = screen.getByLabelText("First name");
    fireEvent.change(firstName, { target: { value: "Alex" } });
    fireEvent.change(screen.getByLabelText("Last name"), { target: { value: "Visitor" } });
    fireEvent.change(screen.getByLabelText("Birthdate"), { target: { value: "1995-04-18" } });
    fireEvent.click(screen.getByRole("button", { name: "Add another" }));

    expect(await screen.findByText("Alex Visitor")).toBeInTheDocument();
    expect(
      screen.getByRole("heading", { name: "Add a newcomer" }),
    ).toBeInTheDocument();
    expect(firstName).toHaveValue("");
    expect(firstName).toHaveFocus();
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
  it("uses one contextual top back action on standalone public details", async () => {
    Object.defineProperty(window.navigator, "standalone", {
      value: true,
      configurable: true,
    });
    try {
      renderApp(
        "/ministry-lens-church/gatherings/rooted-in-grace?browse=1",
      );
      expect(
        await screen.findByRole("heading", { name: "Rooted in grace" }),
      ).toBeInTheDocument();
      const backLinks = screen.getAllByRole("link", {
        name: "Back to Gatherings",
      });
      expect(backLinks).toHaveLength(1);
      expect(backLinks[0]).toHaveAttribute(
        "href",
        "/ministry-lens-church/gatherings?browse=1",
      );
      expect(screen.getByRole("link", { name: "App Home" })).toHaveAttribute(
        "href",
        "/",
      );
      expect(screen.queryByText("Public preview")).not.toBeInTheDocument();
    } finally {
      Object.defineProperty(window.navigator, "standalone", {
        value: false,
        configurable: true,
      });
    }
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
    fireEvent.click(
      screen.getByRole("button", { name: "Convert to Cell Group signup" }),
    );
    expect(
      screen.getByRole("heading", { name: "Convert to Cell Group signup" }),
    ).toBeInTheDocument();
    expect(screen.getByLabelText("Birthday")).toBeRequired();
    expect(
      screen.getByRole("checkbox", { name: /confirmed their consent/i }),
    ).toBeRequired();
  });
});
