import { fireEvent, render, screen, within } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { AppProvider } from "../AppContext";
import { demoData } from "../data/demo";
import { CommunityFeed } from "./CommunityFeed";

vi.mock("../lib/supabase", () => ({ isSupabaseConfigured: false, supabase: null }));

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
    expect(screen.getByLabelText("Post audience")).toHaveValue("organization");
  });

  it("creates a Circle update in demo mode", async () => {
    renderFeed();
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

  it("supports Likes and one-level comments", async () => {
    renderFeed();
    const article = screen.getByRole("article", { name: /small acts of kindness/i });
    fireEvent.click(within(article).getByRole("button", { name: /^Like/ }));
    expect(within(article).getByRole("button", { name: /^Unlike/ })).toBeInTheDocument();
    fireEvent.change(within(article).getByLabelText("Write a comment"), { target: { value: "This encouraged me." } });
    fireEvent.click(within(article).getByRole("button", { name: "Comment" }));
    expect(await within(article).findByText("This encouraged me.")).toBeInTheDocument();
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
