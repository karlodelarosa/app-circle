import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import type { Session } from "@supabase/supabase-js";
import { AppProvider, useCircles } from "./AppContext";
import { demoData } from "./data/demo";
import * as circlesApi from "./services/circles";

vi.mock("./lib/supabase", () => ({
  isSupabaseConfigured: true,
  supabase: {
    auth: {
      onAuthStateChange: vi.fn(() => ({
        data: { subscription: { unsubscribe: vi.fn() } },
      })),
    },
  },
}));

vi.mock("./services/circles", async (importOriginal) => ({
  ...(await importOriginal<typeof import("./services/circles")>()),
  createPrayer: vi.fn(),
  loadAppData: vi.fn(),
  setPrayerClick: vi.fn(),
}));

const testSession = {
  access_token: "test-token",
  refresh_token: "test-refresh-token",
  expires_in: 3600,
  token_type: "bearer",
  user: { id: "demo-user", email: "leader@example.com" },
} as Session;

function FailedPrayerHarness() {
  const { addPrayer, data } = useCircles();
  return (
    <div>
      <output>{data?.group?.name}</output>
      <button
        onClick={() => {
          void addPrayer({
            title: "Prayer that fails",
            description: "",
            category: "Family",
            scope: "circle",
            groupId: "second-group",
          }).catch(() => undefined);
        }}
      >
        Share elsewhere
      </button>
    </div>
  );
}

function PrayerToggleHarness() {
  const { togglePrayer, data } = useCircles();
  const prayer = data?.prayers.find((item) => item.id === "prayer-2");
  return (
    <div>
      <output>{prayer ? `${prayer.prayerCount}:${prayer.prayedByMe}` : "missing"}</output>
      <button onClick={() => void togglePrayer("prayer-2").catch(() => undefined)}>
        I prayed
      </button>
    </div>
  );
}

describe("AppProvider prayer destinations", () => {
  it("keeps the active Circle when a cross-Circle submission fails", async () => {
    const data = structuredClone(demoData);
    data.currentUser.role = "leader";
    data.groups.push({
      ...data.groups[0],
      id: "second-group",
      name: "Second Circle",
      role: "member",
    });
    vi.mocked(circlesApi.createPrayer).mockRejectedValueOnce(
      new Error("Prayer could not be shared"),
    );
    vi.mocked(circlesApi.loadAppData).mockResolvedValue(data);

    render(
      <AppProvider initialData={data} initialSession={testSession}>
        <FailedPrayerHarness />
      </AppProvider>,
    );

    await waitFor(() => expect(circlesApi.loadAppData).toHaveBeenCalled());
    vi.mocked(circlesApi.loadAppData).mockClear();
    fireEvent.click(screen.getByRole("button", { name: "Share elsewhere" }));

    await waitFor(() => expect(circlesApi.createPrayer).toHaveBeenCalled());
    expect(screen.getByText(data.group!.name)).toBeInTheDocument();
    expect(circlesApi.loadAppData).not.toHaveBeenCalled();
  });

  it("optimistically updates the anonymous total and rolls it back on failure", async () => {
    const data = structuredClone(demoData);
    let rejectSave: ((reason: Error) => void) | undefined;
    vi.mocked(circlesApi.loadAppData).mockResolvedValue(data);
    vi.mocked(circlesApi.setPrayerClick).mockImplementationOnce(
      () => new Promise<void>((_resolve, reject) => { rejectSave = reject; }),
    );

    render(
      <AppProvider initialData={data} initialSession={testSession}>
        <PrayerToggleHarness />
      </AppProvider>,
    );
    await waitFor(() => expect(circlesApi.loadAppData).toHaveBeenCalled());

    fireEvent.click(screen.getByRole("button", { name: "I prayed" }));
    expect(screen.getByText("13:true")).toBeInTheDocument();

    rejectSave?.(new Error("Could not save prayer click"));
    await waitFor(() => expect(screen.getByText("12:false")).toBeInTheDocument());
  });
});
