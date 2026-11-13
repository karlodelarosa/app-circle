import { fireEvent, render, screen } from "@testing-library/react";
import { vi } from "vitest";
import type { ReactElement } from "react";
import { ErrorBoundary } from "./ErrorBoundary";

function Broken(): ReactElement {
  throw new TypeError("Sensitive internal details");
}

describe("ErrorBoundary", () => {
  it("shows a safe recovery screen and reports only classified error data", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const fetchMock = vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 204 }));
    const reload = vi.fn();

    render(<ErrorBoundary onReload={reload}><Broken /></ErrorBoundary>);

    expect(screen.getByRole("heading", { name: "Circles hit an unexpected problem." })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Reload Circles" }));
    expect(reload).toHaveBeenCalled();
    expect(fetchMock).toHaveBeenCalledWith("/__telemetry/client-error", expect.objectContaining({
      method: "POST",
      body: expect.not.stringContaining("Sensitive internal details"),
    }));
  });
});
