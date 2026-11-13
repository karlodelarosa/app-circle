import { fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { AppProvider } from "../AppContext";
import { demoData } from "../data/demo";
import { CommunitySettingsPage, FeedItemPage, MemberProfilePage, MembersPage } from "./CommunityPages";

vi.mock("../lib/supabase", () => ({ isSupabaseConfigured: false, supabase: null }));

beforeEach(() => window.sessionStorage.clear());

function renderPage(path: string, route: string, element: React.ReactNode) {
  return render(<MemoryRouter initialEntries={[path]}><AppProvider initialData={structuredClone(demoData)}><Routes><Route path={route} element={element} /></Routes></AppProvider></MemoryRouter>);
}

describe("community identity and deep-link pages", () => {
  it("lists authenticated community members without exposing contact details", async () => {
    renderPage("/members", "/members", <MembersPage />);
    expect(await screen.findByRole("heading", { name: "Members" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /Mara Santos/ })).toHaveAttribute("href", "/members/member-2");
    expect(screen.queryByText("mara@example.com")).not.toBeInTheDocument();
  });

  it("shows an editable community profile to its owner", async () => {
    renderPage("/members/demo-user", "/members/:personId", <MemberProfilePage />);
    expect(await screen.findByRole("heading", { name: "Karlo de la Rosa" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Edit profile" }));
    expect(screen.getByLabelText("Community bio")).toBeInTheDocument();
    expect(screen.getByLabelText("Who can see your bio")).toHaveValue("organization");
  });

  it("opens a private feed item from a stable deep link", async () => {
    renderPage("/feed/feed-post-1", "/feed/:feedItemId", <FeedItemPage />);
    expect(await screen.findByRole("heading", { name: "Community post" })).toBeInTheDocument();
    expect(screen.getByRole("article", { name: /small acts of kindness/i })).toBeInTheDocument();
  });

  it("provides a place to manage saved and hidden activity", async () => {
    renderPage("/community-settings", "/community-settings", <CommunitySettingsPage />);
    expect(await screen.findByRole("heading", { name: "Community settings" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Hidden posts" })).toBeInTheDocument();
  });
});
