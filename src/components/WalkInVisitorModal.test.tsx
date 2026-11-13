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
    fireEvent.change(screen.getByLabelText("First name"), {
      target: { value: "Jamie" },
    });
    fireEvent.change(screen.getByLabelText("Last name"), {
      target: { value: "Walkin" },
    });
    fireEvent.change(screen.getByLabelText("Birthdate"), {
      target: { value: "1998-06-14" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Add newcomer" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "The visitor could not be added.",
    );
    expect(screen.getByLabelText("First name")).toHaveValue("Jamie");
    expect(screen.getByLabelText("Last name")).toHaveValue("Walkin");
  });

  it("requires first name, last name, and birthdate", async () => {
    render(
      <WalkInVisitorModal
        scope="circle"
        busy={false}
        error=""
        onClose={() => undefined}
        onAdd={async () => true}
      />,
    );
    expect(screen.getByRole("button", { name: "Add newcomer" })).toBeDisabled();
    fireEvent.change(screen.getByLabelText("First name"), {
      target: { value: "Alex" },
    });
    fireEvent.change(screen.getByLabelText("Last name"), {
      target: { value: "Visitor" },
    });
    fireEvent.change(screen.getByLabelText("Birthdate"), {
      target: { value: "1995-04-18" },
    });
    await waitFor(() =>
      expect(screen.getByRole("button", { name: "Add newcomer" })).toBeEnabled(),
    );
  });
});
