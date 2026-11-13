import { act, render, screen, waitFor } from "@testing-library/react";
import { Turnstile } from "./Turnstile";

type WidgetOptions = {
  callback: (token: string) => void;
  "expired-callback": () => void;
  "error-callback": () => void;
};

function installTurnstile() {
  let options: WidgetOptions | undefined;
  const remove = vi.fn();
  window.turnstile = {
    render: vi.fn((_container, nextOptions) => {
      options = nextOptions;
      return "widget-1";
    }),
    remove,
  };
  return { getOptions: () => options!, remove };
}

describe("Turnstile", () => {
  afterEach(() => {
    window.turnstile = undefined;
  });

  it("delivers tokens and clears them when they expire", async () => {
    const widget = installTurnstile();
    const onToken = vi.fn();
    render(
      <Turnstile
        onToken={onToken}
        siteKey="site-key"
        testMode={false}
        loadApi={() => Promise.resolve()}
      />,
    );
    await waitFor(() => expect(window.turnstile?.render).toHaveBeenCalled());

    act(() => widget.getOptions().callback("verified-token"));
    expect(onToken).toHaveBeenLastCalledWith("verified-token");
    act(() => widget.getOptions()["expired-callback"]());
    expect(onToken).toHaveBeenLastCalledWith("");
  });

  it("reports widget errors and clears any token", async () => {
    const widget = installTurnstile();
    const onToken = vi.fn();
    render(
      <Turnstile
        onToken={onToken}
        siteKey="site-key"
        testMode={false}
        loadApi={() => Promise.resolve()}
      />,
    );
    await waitFor(() => expect(window.turnstile?.render).toHaveBeenCalled());

    act(() => widget.getOptions()["error-callback"]());

    expect(onToken).toHaveBeenLastCalledWith("");
    expect(screen.getByRole("alert")).toHaveTextContent("Security verification is unavailable");
  });

  it("reports a script load failure", async () => {
    render(
      <Turnstile
        onToken={vi.fn()}
        siteKey="site-key"
        testMode={false}
        loadApi={() => Promise.reject(new Error("blocked"))}
      />,
    );

    expect(await screen.findByRole("alert")).toHaveTextContent("Security verification is unavailable");
  });

  it("fails closed when the site key is missing", () => {
    const loadApi = vi.fn().mockResolvedValue(undefined);
    render(
      <Turnstile
        onToken={vi.fn()}
        siteKey=""
        testMode={false}
        loadApi={loadApi}
      />,
    );

    expect(loadApi).not.toHaveBeenCalled();
    expect(screen.getByRole("alert")).toHaveTextContent("Security verification is unavailable");
  });
});
