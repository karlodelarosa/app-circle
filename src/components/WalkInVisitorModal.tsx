import { useRef, useState, type FormEvent } from "react";
import type { ContactPreference } from "../types";
import { Modal } from "./Modal";

export interface WalkInVisitorInput {
  name: string;
  email: string;
  phone: string;
  preferredContact: ContactPreference;
  consent: boolean;
}

const emptyVisitor = {
  fullName: "",
  email: "",
  phone: "",
  preferredContact: "either" as ContactPreference,
  consent: false,
};

export function WalkInVisitorModal({
  scope,
  busy,
  error,
  onAdd,
  onClose,
}: {
  scope?: "circle" | "organization";
  busy: boolean;
  error: string;
  onAdd: (input: WalkInVisitorInput) => Promise<boolean>;
  onClose: () => void;
}) {
  const [visitor, setVisitor] = useState(emptyVisitor);
  const nameRef = useRef<HTMLInputElement>(null);
  const hasContact = Boolean(visitor.email.trim() || visitor.phone.trim());
  const contactPreferenceInvalid = Boolean(
    hasContact &&
      ((visitor.preferredContact === "email" && !visitor.email.trim()) ||
        (visitor.preferredContact === "phone" && !visitor.phone.trim())),
  );
  const submitDisabled =
    busy || !visitor.fullName.trim() || contactPreferenceInvalid;

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const submitter = (event.nativeEvent as SubmitEvent)
      .submitter as HTMLButtonElement | null;
    const keepOpen = submitter?.value === "another";
    const added = await onAdd({
      name: visitor.fullName.trim(),
      email: visitor.email,
      phone: visitor.phone,
      preferredContact: visitor.preferredContact,
      consent: visitor.consent,
    });
    if (!added) return;

    setVisitor(emptyVisitor);
    if (keepOpen) {
      requestAnimationFrame(() => nameRef.current?.focus());
    } else {
      onClose();
    }
  };

  return (
    <Modal title="Add a walk-in visitor" onClose={onClose}>
      <form onSubmit={(event) => void submit(event)} className="space-y-4">
        <p className="text-sm leading-6 text-muted">
          A name is enough for attendance. Add contact details only when this
          visitor should also appear in Connections for follow-up.
        </p>
        <label className="field-label">
          Full name
          <input
            ref={nameRef}
            className="field"
            required
            autoFocus
            maxLength={120}
            value={visitor.fullName}
            onChange={(event) =>
              setVisitor({ ...visitor, fullName: event.target.value })
            }
          />
        </label>
        {scope !== "organization" ? (
          <details className="rounded-xl border border-line bg-parchment px-4 py-3">
            <summary className="cursor-pointer text-sm font-medium text-olive focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-olive focus-visible:ring-offset-2">
              Add contact details (optional)
            </summary>
            <div className="mt-4 grid gap-4 sm:grid-cols-2">
              <label className="field-label">
                Email
                <input
                  className="field"
                  type="email"
                  value={visitor.email}
                  onChange={(event) =>
                    setVisitor({ ...visitor, email: event.target.value })
                  }
                />
              </label>
              <label className="field-label">
                Phone
                <input
                  className="field"
                  value={visitor.phone}
                  onChange={(event) =>
                    setVisitor({ ...visitor, phone: event.target.value })
                  }
                />
              </label>
              <label className="field-label sm:col-span-2">
                Preferred contact
                <select
                  className="field"
                  value={visitor.preferredContact}
                  onChange={(event) =>
                    setVisitor({
                      ...visitor,
                      preferredContact: event.target.value as ContactPreference,
                    })
                  }
                >
                  <option value="either">Either email or phone</option>
                  <option value="email">Email</option>
                  <option value="phone">Phone</option>
                </select>
              </label>
              <label className="flex items-start gap-3 text-sm leading-6 text-muted sm:col-span-2">
                <input
                  type="checkbox"
                  className="mt-1 h-4 w-4 shrink-0"
                  checked={visitor.consent}
                  onChange={(event) =>
                    setVisitor({ ...visitor, consent: event.target.checked })
                  }
                />
                The visitor agreed that a Circle leader may contact them after
                this gathering.
              </label>
            </div>
          </details>
        ) : (
          <p className="rounded-xl border border-line bg-parchment p-3 text-sm leading-6 text-muted">
            Organization gathering visitors are recorded by name only. Add
            them to a specific Circle later if follow-up is needed.
          </p>
        )}
        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
        <div className="flex flex-col gap-3 sm:flex-row-reverse sm:justify-start">
          <button
            type="submit"
            name="walk-in-action"
            value="close"
            className="primary-button"
            disabled={submitDisabled}
          >
            {busy ? "Adding…" : "Add visitor"}
          </button>
          <button
            type="submit"
            name="walk-in-action"
            value="another"
            className="secondary-button"
            disabled={submitDisabled}
          >
            Add another
          </button>
        </div>
      </form>
    </Modal>
  );
}
