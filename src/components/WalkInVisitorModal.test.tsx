import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { useState } from "react";
import { WalkInVisitorModal } from "./WalkInVisitorModal";

describe("WalkInVisitorModal", () => {
  it("retains the visitor name when adding fails", async () => {
    function FailureHarness() {
      const [error, setError] = useState("");
      return (
        <WalkInVisitorModal
          scope="circle"
          busy={false}
          error={error}
          onClose={() => undefined}
          onAdd={async () => {
            setError("The visitor could not be added.");
            return false;
          }}
        />
      );
    }

    render(<FailureHarness />);
    fireEvent.change(screen.getByLabelText("Full name"), {
      target: { value: "Jamie Walkin" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Add visitor" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "The visitor could not be added.",
    );
    expect(screen.getByLabelText("Full name")).toHaveValue("Jamie Walkin");
  });

  it("validates a preferred contact method only after contact is supplied", async () => {
    render(
      <WalkInVisitorModal
        scope="circle"
        busy={false}
        error=""
        onClose={() => undefined}
        onAdd={async () => true}
      />,
    );
    fireEvent.change(screen.getByLabelText("Full name"), {
      target: { value: "Alex Visitor" },
    });
    expect(screen.getByRole("button", { name: "Add visitor" })).toBeEnabled();

    fireEvent.click(screen.getByText("Add contact details (optional)"));
    fireEvent.change(screen.getByLabelText("Phone"), {
      target: { value: "+63 900 000 0000" },
    });
    fireEvent.change(screen.getByLabelText("Preferred contact"), {
      target: { value: "email" },
    });
    expect(screen.getByRole("button", { name: "Add visitor" })).toBeDisabled();

    fireEvent.change(screen.getByLabelText("Email"), {
      target: { value: "alex@example.com" },
    });
    await waitFor(() =>
      expect(screen.getByRole("button", { name: "Add visitor" })).toBeEnabled(),
    );
  });
});
