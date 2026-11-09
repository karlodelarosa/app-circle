import { useState } from "react";
import { useCircles } from "../AppContext";
import type { Meeting } from "../types";
import { getErrorMessage } from "../lib/errors";
import { Modal } from "./Modal";

export function DeleteGatheringModal({
  meeting,
  onClose,
  onDeleted,
}: {
  meeting: Meeting;
  onClose: () => void;
  onDeleted?: () => void;
}) {
  const { deleteMeeting } = useCircles();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const remove = async () => {
    setBusy(true);
    setError("");
    try {
      const result = await deleteMeeting(meeting.id);
      if (!result.deleted) {
        setError(
          "This gathering has activity and cannot be deleted. Cancel it instead.",
        );
        return;
      }
      onClose();
      onDeleted?.();
    } catch (cause) {
      setError(
        getErrorMessage(cause, "The gathering could not be deleted."),
      );
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal title={`Delete ${meeting.title}?`} onClose={onClose}>
      <p className="leading-6 text-muted">
        This permanently removes the gathering. This action cannot be undone.
      </p>
      <p className="mt-3 text-sm leading-6 text-muted">
        Gatherings with RSVPs, attendance, reflections, closeout records, or
        linked content must be cancelled instead.
      </p>
      {error && (
        <p className="form-error mt-5" role="alert">
          {error}
        </p>
      )}
      <div className="mt-6 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
        <button className="secondary-button justify-center" onClick={onClose}>
          Keep gathering
        </button>
        <button
          className="primary-button justify-center bg-red-800 hover:bg-red-900"
          disabled={busy}
          onClick={() => void remove()}
        >
          {busy ? "Deleting…" : "Delete permanently"}
        </button>
      </div>
    </Modal>
  );
}
