import { fireEvent, render, screen, within } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { AppProvider } from "../AppContext";
import { demoData } from "../data/demo";
import { CommunityFeed } from "./CommunityFeed";

vi.mock("../lib/supabase", () => ({ isSupabaseConfigured: false, supabase: null }));

beforeEach(() => window.sessionStorage.clear());

const renderFeed = () => render(
  <MemoryRouter>
    <AppProvider initialData={structuredClone(demoData)}>
      <CommunityFeed />
    </AppProvider>
  </MemoryRouter>,
);

const renderFeedWith = (communityFeed: NonNullable<typeof demoData.communityFeed>) => {
  const data = structuredClone(demoData);
  data.communityFeed = communityFeed;
  return render(
    <MemoryRouter>
      <AppProvider initialData={data}>
        <CommunityFeed />
      </AppProvider>
    </MemoryRouter>,
  );
};

describe("CommunityFeed", () => {
  it("defaults new updates to the entire organization", () => {
    renderFeed();
    expect(screen.getByRole("heading", { name: "Community feed" })).toBeInTheDocument();
    fireEvent.focus(screen.getByLabelText("Share an update"));
    expect(screen.getByLabelText("Post audience")).toHaveValue("organization");
  });

  it("expands the compact composer and preserves a collapsed draft", () => {
    renderFeed();
    expect(screen.queryByLabelText("Post audience")).not.toBeInTheDocument();
    const input = screen.getByLabelText("Share an update");
    fireEvent.focus(input);
    fireEvent.change(input, { target: { value: "An unfinished thought" } });
    fireEvent.change(screen.getByLabelText("Post audience"), { target: { value: "demo-group" } });
    fireEvent.click(screen.getByRole("button", { name: "Collapse" }));
    expect(screen.queryByRole("button", { name: "Post update" })).not.toBeInTheDocument();
    expect(input).toHaveValue("An unfinished thought");
    fireEvent.focus(input);
    expect(screen.getByLabelText("Post audience")).toHaveValue("demo-group");
  });

  it("keeps search tucked away until requested", () => {
    renderFeed();
    expect(screen.queryByRole("searchbox")).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Open community search" }));
    fireEvent.change(screen.getByRole("searchbox"), { target: { value: "kindness" } });
    fireEvent.click(screen.getByRole("button", { name: "Close community search" }));
    expect(screen.queryByRole("searchbox")).not.toBeInTheDocument();
    expect(screen.getByText("Search filters active")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Open community search" }));
    expect(screen.getByRole("searchbox")).toHaveValue("kindness");
  });

  it("creates a Circle update in demo mode", async () => {
    renderFeed();
    fireEvent.focus(screen.getByLabelText("Share an update"));
    fireEvent.change(screen.getByLabelText("Post audience"), { target: { value: "demo-group" } });
    fireEvent.change(screen.getByLabelText("Share an update"), { target: { value: "Dinner was a gift tonight." } });
    fireEvent.click(screen.getByRole("button", { name: "Post update" }));

    const article = await screen.findByRole("article", { name: /Dinner was a gift tonight/ });
    expect(within(article).getByText("Grace & Ground")).toBeInTheDocument();
  });

  it("lets authors edit their standalone updates", async () => {
    renderFeed();
    fireEvent.change(screen.getByLabelText("Share an update"), { target: { value: "First draft" } });
    fireEvent.click(screen.getByRole("button", { name: "Post update" }));
    const article = await screen.findByRole("article", { name: /First draft/ });
    fireEvent.click(within(article).getByRole("button", { name: "Post actions" }));
    fireEvent.click(within(article).getByRole("menuitem", { name: "Edit update" }));
    fireEvent.change(within(article).getByLabelText("Edit update"), { target: { value: "A clearer reflection" } });
    fireEvent.click(within(article).getByRole("button", { name: "Save" }));
    expect(within(article).getByText("A clearer reflection")).toBeInTheDocument();
  });

  it("supports reactions and one-level comments", async () => {
    renderFeed();
    const article = screen.getByRole("article", { name: /small acts of kindness/i });
    fireEvent.click(within(article).getByRole("button", { name: /choose a reaction/i }));
    fireEvent.click(within(article).getByRole("menuitemradio", { name: "Like" }));
    expect(within(article).getByRole("button", { name: /^Like/ })).toBeInTheDocument();
    fireEvent.change(within(article).getByLabelText("Write a comment"), { target: { value: "This encouraged me." } });
    fireEvent.click(within(article).getByRole("button", { name: "Comment" }));
    expect(await within(article).findByText("This encouraged me.")).toBeInTheDocument();
  });

  it("offers familiar reactions, saving, and personal hiding", async () => {
    renderFeed();
    const article = screen.getByRole("article", { name: /small acts of kindness/i });

    fireEvent.click(within(article).getByRole("button", { name: /choose a reaction/i }));
    fireEvent.click(within(article).getByRole("menuitemradio", { name: "Amen" }));
    expect(within(article).getByRole("button", { name: /Amen/ })).toBeInTheDocument();

    fireEvent.click(within(article).getByRole("button", { name: "Post actions" }));
    fireEvent.click(within(article).getByRole("menuitem", { name: "Save post" }));
    fireEvent.click(within(article).getByRole("button", { name: "Post actions" }));
    expect(within(article).getByRole("menuitem", { name: "Remove from saved" })).toBeInTheDocument();
    fireEvent.click(within(article).getByRole("menuitem", { name: "Hide this post" }));
    expect(screen.queryByRole("article", { name: /small acts of kindness/i })).not.toBeInTheDocument();
  });

  it("keeps member-only actions unavailable to administrators without a person profile", () => {
    const data = structuredClone(demoData);
    data.currentUser.personId = undefined;
    render(
      <MemoryRouter>
        <AppProvider initialData={data}>
          <CommunityFeed />
        </AppProvider>
      </MemoryRouter>,
    );
    const article = screen.getByRole("article", { name: /small acts of kindness/i });
    expect(within(article).getByRole("button", { name: /choose a reaction/i })).toBeDisabled();
    fireEvent.click(within(article).getByRole("button", { name: "Post actions" }));
    expect(within(article).queryByRole("menuitem", { name: "Save post" })).not.toBeInTheDocument();
    expect(within(article).queryByRole("menuitem", { name: "Report post" })).not.toBeInTheDocument();
    expect(within(article).getByRole("menuitem", { name: "Copy link" })).toBeInTheDocument();
  });

  it("lets moderators pin activity and close comments without deleting it", () => {
    renderFeed();
    const article = screen.getByRole("article", { name: /small acts of kindness/i });
    fireEvent.click(within(article).getByRole("button", { name: "Post actions" }));
    fireEvent.click(within(article).getByRole("menuitem", { name: "Close comments" }));
    expect(within(article).getByText("Comments are closed for this post.")).toBeInTheDocument();
    fireEvent.click(within(article).getByRole("button", { name: "Post actions" }));
    fireEvent.click(within(article).getByRole("menuitem", { name: "Pin post" }));
    expect(screen.getByRole("heading", { name: "Pinned for this community" })).toBeInTheDocument();
    expect(screen.getAllByRole("article", { name: /small acts of kindness/i })).toHaveLength(1);
  });

  it("reports safety concerns without automatically hiding the post", async () => {
    renderFeed();
    const article = screen.getByRole("article", { name: /small acts of kindness/i });
    fireEvent.click(within(article).getByRole("button", { name: "Post actions" }));
    fireEvent.click(within(article).getByRole("menuitem", { name: "Report post" }));
    fireEvent.change(within(article).getByLabelText("Details (optional)"), { target: { value: "Please review the personal detail." } });
    fireEvent.click(within(article).getByRole("button", { name: "Send report" }));
    expect(await within(article).findByText("Report sent to community leaders.")).toBeInTheDocument();
    expect(article).toBeInTheDocument();
  });

  it("keeps Pray and Follow separate and lets the author add an update", async () => {
    const prayer = {
      ...demoData.communityFeed![1],
      authorPersonId: "demo-user",
      authorName: "Karlo de la Rosa",
      canEdit: true,
      prayer: { ...demoData.prayers[0], userId: "demo-user", authorName: "Karlo de la Rosa" },
    };
    renderFeedWith([prayer]);
    const article = screen.getByRole("article", { name: /Wisdom for a new season/ });

    fireEvent.click(within(article).getByRole("button", { name: /^Follow updates/ }));
    expect(within(article).getByRole("button", { name: /^Following/ })).toBeInTheDocument();
    expect(within(article).getByRole("button", { name: /^Praying/ })).toBeInTheDocument();

    fireEvent.click(within(article).getByRole("button", { name: "Add prayer update" }));
    fireEvent.change(within(article).getByLabelText("Prayer update"), { target: { value: "We received clarity today." } });
    fireEvent.click(within(article).getByRole("button", { name: "Share update" }));
    expect(await within(article).findByText("We received clarity today.")).toBeInTheDocument();
  });

  it("filters the current feed with familiar search controls", () => {
    renderFeed();
    fireEvent.click(screen.getByRole("button", { name: "Open community search" }));
    fireEvent.change(screen.getByRole("searchbox", { name: "Search community" }), { target: { value: "kindness" } });
    expect(screen.getByRole("article", { name: /small acts of kindness/i })).toBeInTheDocument();
    expect(screen.queryByRole("article", { name: /Wisdom for a new season/ })).not.toBeInTheDocument();
  });

  it("supports structured type, author, and date filters", () => {
    renderFeed();
    fireEvent.change(screen.getByLabelText("Activity type"), { target: { value: "prayer" } });
    expect(screen.getByRole("article", { name: /Wisdom for a new season/ })).toBeInTheDocument();
    expect(screen.queryByRole("article", { name: /small acts of kindness/i })).not.toBeInTheDocument();
    fireEvent.change(screen.getByLabelText("Activity type"), { target: { value: "" } });
    fireEvent.change(screen.getByLabelText("Author"), { target: { value: "member-2" } });
    expect(screen.getByRole("article", { name: /small acts of kindness/i })).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText("From date"), { target: { value: "2999-01-01" } });
    expect(screen.queryByRole("article")).not.toBeInTheDocument();
  });

  it("shows gathering reflection context and answered-prayer praise", () => {
    const reflection = {
      ...demoData.communityFeed![0], id: "reflection-feed", type: "reflection" as const, sourceId: "reflection-1",
      title: undefined, body: "God met us around the table.", gatheringId: "meeting-3", gatheringTitle: "Carrying one another",
    };
    const prayer = {
      ...demoData.communityFeed![1], id: "answered-feed", prayer: demoData.prayers[2], title: demoData.prayers[2].title,
      body: demoData.prayers[2].description,
    };
    renderFeedWith([reflection, prayer]);

    const reflectionCard = screen.getByRole("article", { name: /God met us around the table/ });
    expect(within(reflectionCard).getByText(/Gathering reflection from Carrying one another/)).toBeInTheDocument();
    expect(within(reflectionCard).getByRole("link", { name: "Open gathering" })).toHaveAttribute("href", "/gatherings/meeting-3");
    const prayerCard = screen.getByRole("article", { name: /A gentle answer/ });
    expect(within(prayerCard).getByText("Answered prayer")).toBeInTheDocument();
    expect(within(prayerCard).getByText(/God gave us honesty/)).toBeInTheDocument();
  });

  it("exposes the existing RSVP choices on scheduled-gathering cards", () => {
    const meeting = demoData.meetings[0];
    renderFeedWith([{
      ...demoData.communityFeed![0], id: "gathering-feed", type: "gathering", sourceId: meeting.id,
      title: meeting.title, body: undefined, meeting, authorName: "Community leader",
    }]);
    const card = screen.getByRole("article", { name: /Rooted in grace/ });
    expect(within(card).getByRole("button", { name: "Going" })).toBeInTheDocument();
    expect(within(card).getByRole("button", { name: "Maybe" })).toBeInTheDocument();
    expect(within(card).getByRole("button", { name: "Can't go" })).toBeInTheDocument();
  });
});
