import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { PwaRefreshController } from "./PwaRefreshController";

vi.mock("../hooks/useStandalone", () => ({
  useStandalone: () => true,
}));

const touch = (clientX: number, clientY: number) => ({ clientX, clientY });

function pull({ x = 0, y = 100 }: { x?: number; y?: number } = {}) {
  fireEvent.touchStart(document, { touches: [touch(0, 0)] });
  fireEvent.touchMove(document, { touches: [touch(x, y)] });
  fireEvent.touchEnd(document);
}

describe("PwaRefreshController", () => {
  beforeEach(() => {
    Object.defineProperty(window, "scrollY", { value: 0, configurable: true });
    Object.defineProperty(navigator, "onLine", { value: true, configurable: true });
    Object.defineProperty(document, "visibilityState", { value: "visible", configurable: true });
  });

  afterEach(() => vi.useRealTimers());

  it("refreshes after a deliberate downward pull at the top of the page", async () => {
    const refresh = vi.fn().mockResolvedValue(true);
    render(<PwaRefreshController refresh={refresh} />);

    pull();

    await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
    expect(await screen.findByRole("status")).toHaveTextContent("Content updated");
  });

  it("does not refresh when the page is already scrolled", () => {
    Object.defineProperty(window, "scrollY", { value: 25, configurable: true });
    const refresh = vi.fn().mockResolvedValue(true);
    render(<PwaRefreshController refresh={refresh} />);

    pull();

    expect(refresh).not.toHaveBeenCalled();
  });

  it("cancels a horizontal gesture", () => {
    const refresh = vi.fn().mockResolvedValue(true);
    render(<PwaRefreshController refresh={refresh} />);

    pull({ x: 100, y: 20 });

    expect(refresh).not.toHaveBeenCalled();
  });

  it("does not intercept scrolling inside an open dialog", () => {
    const refresh = vi.fn().mockResolvedValue(true);
    render(
      <>
        <PwaRefreshController refresh={refresh} />
        <div role="dialog"><button>Inside modal</button></div>
      </>,
    );
    const button = screen.getByRole("button", { name: "Inside modal" });

    fireEvent.touchStart(button, { touches: [touch(0, 0)] });
    fireEvent.touchMove(button, { touches: [touch(0, 100)] });
    fireEvent.touchEnd(button);

    expect(refresh).not.toHaveBeenCalled();
  });

  it("keeps current content and reports an offline refresh failure", async () => {
    Object.defineProperty(navigator, "onLine", { value: false, configurable: true });
    const refresh = vi.fn().mockResolvedValue(true);
    render(<PwaRefreshController refresh={refresh} />);

    pull();

    expect(refresh).not.toHaveBeenCalled();
    expect(await screen.findByRole("status")).toHaveTextContent("You’re offline");
  });

  it("deduplicates refresh attempts while one is running", async () => {
    let finish: ((value: boolean) => void) | undefined;
    const refresh = vi.fn(() => new Promise<boolean>((resolve) => { finish = resolve; }));
    render(<PwaRefreshController refresh={refresh} />);

    pull();
    pull();

    expect(refresh).toHaveBeenCalledTimes(1);
    await act(async () => finish?.(true));
  });

  it("refreshes on foreground return only after data is 60 seconds old", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-11-07T00:00:00Z"));
    const refresh = vi.fn().mockResolvedValue(true);
    render(<PwaRefreshController refresh={refresh} />);

    act(() => {
      vi.setSystemTime(new Date("2026-11-07T00:00:59Z"));
      document.dispatchEvent(new Event("visibilitychange"));
    });
    expect(refresh).not.toHaveBeenCalled();

    await act(async () => {
      vi.setSystemTime(new Date("2026-11-07T00:01:00Z"));
      document.dispatchEvent(new Event("visibilitychange"));
      await Promise.resolve();
    });
    expect(refresh).toHaveBeenCalledTimes(1);
  });
});
