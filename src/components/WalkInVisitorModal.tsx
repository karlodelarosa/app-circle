import { useRef, useState, type FormEvent } from "react";
import type { CloseoutNewcomerInput } from "../types";
import { Modal } from "./Modal";

export type WalkInVisitorInput = CloseoutNewcomerInput;

const emptyVisitor: WalkInVisitorInput = {
  firstName: "",
  lastName: "",
  birthdate: "",
};

export function WalkInVisitorModal({ busy, error, onAdd, onClose }: {
  scope?: "circle" | "organization";
  busy: boolean;
  error: string;
  onAdd: (input: WalkInVisitorInput) => Promise<boolean>;
  onClose: () => void;
}) {
  const [visitor, setVisitor] = useState(emptyVisitor);
  const nameRef = useRef<HTMLInputElement>(null);
  const submitDisabled = busy || !visitor.firstName.trim() ||
    !visitor.lastName.trim() || !visitor.birthdate;

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const submitter = (event.nativeEvent as SubmitEvent).submitter as HTMLButtonElement | null;
    const keepOpen = submitter?.value === "another";
    const added = await onAdd({
      firstName: visitor.firstName.trim(),
      lastName: visitor.lastName.trim(),
      birthdate: visitor.birthdate,
    });
    if (!added) return;
    setVisitor(emptyVisitor);
    if (keepOpen) requestAnimationFrame(() => nameRef.current?.focus());
    else onClose();
  };

  return (
    <Modal title="Add a newcomer" onClose={onClose}>
      <form onSubmit={(event) => void submit(event)} className="space-y-4">
        <p className="text-sm leading-6 text-muted">
          Record the newcomer in SheepCount as a Small Group Prospect. This
          does not add them as a Circle member or create a login.
        </p>
        <div className="grid gap-4 sm:grid-cols-2">
          <label className="field-label">First name
            <input ref={nameRef} className="field" required autoFocus maxLength={80}
              value={visitor.firstName}
              onChange={(event) => setVisitor({ ...visitor, firstName: event.target.value })} />
          </label>
          <label className="field-label">Last name
            <input className="field" required maxLength={80} value={visitor.lastName}
              onChange={(event) => setVisitor({ ...visitor, lastName: event.target.value })} />
          </label>
          <label className="field-label sm:col-span-2">Birthdate
            <input className="field" type="date" required min="1900-01-01"
              max={new Date().toISOString().slice(0, 10)} value={visitor.birthdate}
              onChange={(event) => setVisitor({ ...visitor, birthdate: event.target.value })} />
          </label>
        </div>
        {error && <p className="form-error" role="alert">{error}</p>}
        <div className="flex flex-col gap-3 sm:flex-row-reverse sm:justify-start">
          <button type="submit" name="walk-in-action" value="close"
            className="primary-button" disabled={submitDisabled}>
            {busy ? "Adding…" : "Add newcomer"}
          </button>
          <button type="submit" name="walk-in-action" value="another"
            className="secondary-button" disabled={submitDisabled}>Add another</button>
        </div>
      </form>
    </Modal>
  );
}
