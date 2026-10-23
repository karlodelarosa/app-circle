import { act, fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Meeting } from "../types";
import { DashboardJumbotron } from "./DashboardJumbotron";

const gathering: Meeting = {
  id: "gathering-1",
  groupId: "circle-1",
  title: "Dinner around the table",
  meetingDate: new Date(Date.now() + 86400000).toISOString(),
  location: "The Santos home",
  studyTopic: "John 15",
  notes: "",
  status: "scheduled",
  createdBy: "leader-1",
  rsvps: {},
};

const renderCarousel = () =>
  render(
    <MemoryRouter>
      <DashboardJumbotron
        defaultImage="/assets/devotional-table.webp"
        gatherings={[gathering]}
        circleName="Grace & Ground"
        circlePath="/circles/circle-1"
      />
    </MemoryRouter>,
  );

afterEach(() => {
  vi.useRealTimers();
});

describe("DashboardJumbotron", () => {
  it("shows only the welcome slide when there are no gatherings", () => {
    render(
      <MemoryRouter>
        <DashboardJumbotron
          defaultImage="/assets/devotional-table.webp"
          welcomeImage="/assets/welcome-table.webp"
          gatherings={[]}
          circleName="Grace & Ground"
          circlePath="/circles/circle-1"
        />
      </MemoryRouter>,
    );
    expect(screen.getByRole("heading", { name: "Make room for one another." })).toBeInTheDocument();
    expect(screen.getByRole("group", { name: "Slide 1 of 1" }).querySelector("img")).toHaveAttribute("src", "/assets/welcome-table.webp");
    expect(screen.getByText("Welcome to Grace & Ground")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "View my Circle" })).toHaveAttribute("href", "/circles/circle-1");
    expect(screen.getByRole("group", { name: "Slide 1 of 1" })).toHaveClass("lg:min-h-[21rem]");
    expect(screen.queryByRole("button", { name: "Next slide" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /Show slide/ })).not.toBeInTheDocument();
  });

  it("supports buttons, keyboard arrows, and pointer swipes", () => {
    renderCarousel();
    const carousel = screen.getByRole("region", { name: "Community highlights" });
    const first = screen.getByRole("button", { name: "Show slide 1" });
    const second = screen.getByRole("button", { name: "Show slide 2" });

    expect(first).toHaveAttribute("aria-current", "true");
    fireEvent.click(screen.getByRole("button", { name: "Next slide" }));
    expect(second).toHaveAttribute("aria-current", "true");
    fireEvent.keyDown(carousel, { key: "ArrowLeft" });
    expect(first).toHaveAttribute("aria-current", "true");
    const track = carousel.querySelector(".touch-pan-y")!;
    fireEvent(track, new MouseEvent("pointerdown", { bubbles: true, clientX: 180 }));
    fireEvent(track, new MouseEvent("pointermove", { bubbles: true, clientX: 90 }));
    fireEvent(track, new MouseEvent("pointerup", { bubbles: true, clientX: 90 }));
    expect(second).toHaveAttribute("aria-current", "true");
  });

  it("autoplays every seven seconds and pauses while hovered", () => {
    vi.useFakeTimers();
    const hiddenDescriptor = Object.getOwnPropertyDescriptor(document, "hidden");
    Object.defineProperty(document, "hidden", { configurable: true, value: false });
    renderCarousel();
    const carousel = screen.getByRole("region", { name: "Community highlights" });
    const first = screen.getByRole("button", { name: "Show slide 1" });
    const second = screen.getByRole("button", { name: "Show slide 2" });

    act(() => vi.advanceTimersByTime(7000));
    expect(second).toHaveAttribute("aria-current", "true");
    fireEvent.mouseEnter(carousel);
    act(() => vi.advanceTimersByTime(7000));
    expect(second).toHaveAttribute("aria-current", "true");
    fireEvent.mouseLeave(carousel);
    act(() => vi.advanceTimersByTime(7000));
    expect(first).toHaveAttribute("aria-current", "true");

    if (hiddenDescriptor) Object.defineProperty(document, "hidden", hiddenDescriptor);
  });

  it("does not autoplay when reduced motion is requested", () => {
    vi.useFakeTimers();
    const original = window.matchMedia;
    Object.defineProperty(window, "matchMedia", {
      configurable: true,
      value: vi.fn().mockReturnValue({
        matches: true,
        addEventListener: vi.fn(),
        removeEventListener: vi.fn(),
      }),
    });
    renderCarousel();
    const first = screen.getByRole("button", { name: "Show slide 1" });
    act(() => vi.advanceTimersByTime(14000));
    expect(first).toHaveAttribute("aria-current", "true");
    Object.defineProperty(window, "matchMedia", {
      configurable: true,
      value: original,
    });
  });
});
