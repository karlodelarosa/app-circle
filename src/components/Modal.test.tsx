import { fireEvent, render, screen } from "@testing-library/react";
import { vi } from "vitest";
import { Modal } from "./Modal";

describe("Modal", () => {
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
});
