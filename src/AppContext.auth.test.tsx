import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { AppProvider, useCircles } from "./AppContext";
import { demoData } from "./data/demo";
import * as circlesApi from "./services/circles";

const authState = vi.hoisted(() => ({
  callback: undefined as
    | ((event: string, session: Session | null) => void)
    | undefined,
}));

vi.mock("./lib/supabase", () => ({
  isSupabaseConfigured: true,
  supabase: {
    auth: {
      onAuthStateChange: (
        callback: (event: string, session: Session | null) => void,
      ) => {
        authState.callback = callback;
        return { data: { subscription: { unsubscribe: vi.fn() } } };
      },
      signOut: vi.fn(),
    },
  },
}));

vi.mock("./services/circles", async (importOriginal) => ({
  ...(await importOriginal<typeof import("./services/circles")>()),
  loadAppData: vi.fn(),
}));

const session = (expiresAt: number) =>
  ({
    access_token: `token-${expiresAt}`,
    refresh_token: "refresh",
    expires_in: 3600,
    expires_at: expiresAt,
    token_type: "bearer",
    user: { id: "user-1", email: "leader@example.com" },
  }) as Session;

function FormHarness() {
  const { loading, data } = useCircles();
  const [title, setTitle] = useState("");
  if (loading || !data) return <p>Loading</p>;
  return (
    <label>
      Gathering title
      <input value={title} onChange={(event) => setTitle(event.target.value)} />
    </label>
  );
}

describe("AppProvider session refresh behavior", () => {
  it("keeps the mounted form and skips data reloads for token refreshes", async () => {
    vi.mocked(circlesApi.loadAppData).mockResolvedValue(
      structuredClone(demoData),
    );
    render(
      <AppProvider>
        <FormHarness />
      </AppProvider>,
    );

    act(() => authState.callback?.("INITIAL_SESSION", session(100)));
    const input = await screen.findByLabelText("Gathering title");
    fireEvent.change(input, { target: { value: "Unfinished gathering" } });
    await waitFor(() => expect(circlesApi.loadAppData).toHaveBeenCalledTimes(1));

    act(() => authState.callback?.("TOKEN_REFRESHED", session(200)));

    expect(screen.getByLabelText("Gathering title")).toHaveValue(
      "Unfinished gathering",
    );
    expect(screen.queryByText("Loading")).not.toBeInTheDocument();
    await act(async () => Promise.resolve());
    expect(circlesApi.loadAppData).toHaveBeenCalledTimes(1);
  });
});
