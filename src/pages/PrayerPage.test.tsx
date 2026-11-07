import { render, screen } from "@testing-library/react";
import { PrayerPage } from "./PrayerPage";
import { demoData } from "../data/demo";

const testData = structuredClone(demoData);
testData.prayers[0].prayerCount = 1;
testData.prayers[1].prayerCount = 2;

vi.mock("../AppContext", () => ({
  useCircles: () => ({ data: testData, togglePrayer: vi.fn() }),
}));

describe("PrayerPage", () => {
  it("shows anonymous singular and plural prayer totals", () => {
    render(<PrayerPage />);

    expect(screen.getByText("1 person has prayed")).toBeInTheDocument();
    expect(screen.getByText("2 people have prayed")).toBeInTheDocument();
  });
});
