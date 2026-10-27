import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import type { Session } from "@supabase/supabase-js";
import { AppProvider, useCircles } from "../AppContext";
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
      screen.getByRole("radio", { name: /a circle/i }),
    ).toBeDisabled();
    fireEvent.change(screen.getByLabelText("What can we pray for?"), {
      target: { value: "Prayer without a selected Circle" },
    });
    expect(screen.getByRole("button", { name: "Share request" })).toBeEnabled();
  });

  it("keeps a regular member's private destination fixed to the active Circle", () => {
    const data = structuredClone(demoData);
    data.currentUser.role = "member";
    data.groups.push({
      ...data.groups[0],
      id: "second-group",
      name: "Second Circle",
      role: "member",
    });

    render(
      <MemoryRouter>
        <AppProvider initialData={data} initialSession={testSession}>
          <PrayerForm onDone={vi.fn()} />
        </AppProvider>
      </MemoryRouter>,
    );

    expect(screen.queryByRole("combobox", { name: /choose circle/i })).not.toBeInTheDocument();
    expect(screen.getByRole("radio", { name: /my circle/i })).toBeChecked();
    expect(screen.getByText(data.group!.name, { exact: false })).toBeInTheDocument();
    expect(screen.getByRole("radio", { name: /entire organization/i })).toBeEnabled();
  });

  it("lets leaders choose any accessible Circle and defaults to the active one", () => {
    const data = structuredClone(demoData);
    data.currentUser.role = "leader";
    data.groups.push({
      ...data.groups[0],
      id: "second-group",
      name: "Second Circle",
      role: "member",
    });

    render(
      <MemoryRouter>
        <AppProvider initialData={data} initialSession={testSession}>
          <PrayerForm onDone={vi.fn()} />
        </AppProvider>
      </MemoryRouter>,
    );

    const destination = screen.getByRole("combobox", { name: /choose circle/i });
    expect(destination).toHaveValue(data.group!.id);
    expect(screen.getByRole("option", { name: data.group!.name })).toBeInTheDocument();
    expect(screen.getByRole("option", { name: "Second Circle" })).toBeInTheDocument();
  });

  it("opens the selected Circle after a leader shares there", async () => {
    const data = structuredClone(demoData);
    data.currentUser.role = "leader";
    data.groups.push({
      ...data.groups[0],
      id: "second-group",
      name: "Second Circle",
      role: "member",
    });
    const onDone = vi.fn();

    function Result() {
      const context = useCircles();
      return (
        <output>
          {context.data?.group?.name}:{context.data?.prayers[0]?.title}
        </output>
      );
    }

    render(
      <MemoryRouter>
        <AppProvider initialData={data} initialSession={testSession}>
          <PrayerForm onDone={onDone} />
          <Result />
        </AppProvider>
      </MemoryRouter>,
    );

    fireEvent.change(screen.getByRole("combobox", { name: /choose circle/i }), {
      target: { value: "second-group" },
    });
    fireEvent.change(screen.getByLabelText("What can we pray for?"), {
      target: { value: "Prayer for Second Circle" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Share request" }));

    await waitFor(() => expect(onDone).toHaveBeenCalled());
    expect(screen.getByText("Second Circle:Prayer for Second Circle")).toBeInTheDocument();
  });
});
