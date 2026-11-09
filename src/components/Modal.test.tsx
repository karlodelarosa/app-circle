import { fireEvent, render, screen } from "@testing-library/react";
import { useState } from "react";
import { vi } from "vitest";
import { Modal } from "./Modal";

describe("Modal", () => {
  it("portals the dialog to the document body with a dedicated scroll region", () => {
    const host = document.createElement("div");
    document.body.append(host);

    const { unmount } = render(
      <Modal title="Long form" onClose={vi.fn()}>
        <div>Form fields</div>
      </Modal>,
      { container: host },
    );

    const dialog = screen.getByRole("dialog");
    const scrollRegion = screen.getByRole("document", { name: "Long form content" });
    expect(dialog.parentElement).toBe(document.body);
    expect(scrollRegion).toHaveClass("modal-scroll-region");

    unmount();
    host.remove();
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  });

  it("traps keyboard focus and restores the opener on close", () => {
    const onClose = vi.fn();
    const opener = document.createElement("button");
    document.body.append(opener);
    opener.focus();

    const { unmount } = render(
      <Modal title="Accessible dialog" onClose={onClose}>
        <button>First action</button>
        <button>Last action</button>
      </Modal>,
    );

    const close = screen.getByRole("button", { name: "Close" });
    const last = screen.getByRole("button", { name: "Last action" });
    expect(close).toHaveFocus();
    last.focus();
    fireEvent.keyDown(document, { key: "Tab" });
    expect(close).toHaveFocus();
    fireEvent.keyDown(document, { key: "Escape" });
    expect(onClose).toHaveBeenCalled();
    unmount();
    expect(opener).toHaveFocus();
    opener.remove();
  });

  it("keeps a controlled input focused when the parent creates a new close callback", () => {
    function ControlledModal() {
      const [value, setValue] = useState("");
      return (
        <Modal title="Edit Circle details" onClose={() => undefined}>
          <label>
            Circle name
            <input
              value={value}
              onChange={(event) => setValue(event.target.value)}
            />
          </label>
        </Modal>
      );
    }

    const opener = document.createElement("button");
    document.body.append(opener);
    opener.focus();
    const { unmount } = render(<ControlledModal />);
    const input = screen.getByLabelText("Circle name");
    input.focus();

    fireEvent.change(input, { target: { value: "A" } });

    expect(input).toHaveFocus();
    unmount();
    opener.remove();
  });
});
