import { fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import type { Session } from "@supabase/supabase-js";
import { AppProvider } from "../AppContext";
import { demoData } from "../data/demo";
import { PrayerForm } from "./PrayerForm";

vi.mock("../lib/supabase", () => ({
  isSupabaseConfigured: false,
  supabase: null,
}));

const testSession = {
  access_token: "test-token",
  refresh_token: "test-refresh-token",
  expires_in: 3600,
  token_type: "bearer",
  user: { id: "demo-user", email: "karlo@example.com" },
} as Session;

describe("PrayerForm", () => {
  it("defaults to the organization when no Circle is selected", () => {
    const data = structuredClone(demoData);
    data.group = null;
    render(
      <MemoryRouter>
        <AppProvider initialData={data} initialSession={testSession}>
          <PrayerForm onDone={vi.fn()} />
        </AppProvider>
      </MemoryRouter>,
    );

    expect(
      screen.getByRole("radio", { name: /entire organization/i }),
    ).toBeChecked();
    expect(
      screen.getByRole("radio", { name: /my circle/i }),
    ).toBeDisabled();
    fireEvent.change(screen.getByLabelText("What can we pray for?"), {
      target: { value: "Prayer without a selected Circle" },
    });
    expect(screen.getByRole("button", { name: "Share request" })).toBeEnabled();
  });
});
