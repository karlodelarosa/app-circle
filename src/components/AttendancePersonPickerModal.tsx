import { Search, UserPlus } from "lucide-react";
import { useState } from "react";
import { getErrorMessage } from "../lib/errors";
import { supabase } from "../lib/supabase";
import { searchGatheringAttendancePeople } from "../services/circles";
import type { AttendancePersonSummary } from "../types";
import { Modal } from "./Modal";

export function AttendancePersonPickerModal({
  gatheringId,
  existingIds,
  fallbackPeople,
  onAdd,
  onClose,
}: {
  gatheringId: string;
  existingIds: string[];
  fallbackPeople: AttendancePersonSummary[];
  onAdd: (person: AttendancePersonSummary) => void;
  onClose: () => void;
}) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<AttendancePersonSummary[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [searched, setSearched] = useState(false);
  const listed = new Set(existingIds);

  const search = async () => {
    const value = query.trim();
    if (value.length < 2) {
      setError("Enter at least two characters to search.");
      setResults([]);
      return;
    }
    setBusy(true);
    setError("");
    setSearched(true);
    try {
      const people = supabase
        ? await searchGatheringAttendancePeople(supabase, gatheringId, value)
        : fallbackPeople
            .filter((person) =>
              `${person.fullName} ${person.email}`
                .toLocaleLowerCase()
                .includes(value.toLocaleLowerCase()),
            )
            .slice(0, 30);
      setResults(people);
    } catch (cause) {
      setResults([]);
      setError(
        getErrorMessage(cause, "Organization members could not be searched."),
      );
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal title="Add an existing member" onClose={onClose}>
      <form
        className="flex flex-col gap-3 sm:flex-row"
        onSubmit={(event) => {
          event.preventDefault();
          void search();
        }}
      >
        <label className="field-label min-w-0 flex-1">
          Search organization members
          <input
            className="field"
            type="search"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Name or email"
          />
        </label>
        <button className="secondary-button self-end" disabled={busy}>
          <Search size={16} /> {busy ? "Searching…" : "Search"}
        </button>
      </form>
      <p className="mt-3 text-xs leading-5 text-muted">
        Adding attendance here does not add the person to this Circle or change
        their account access.
      </p>
      {error && (
        <p className="form-error mt-4" role="alert">
          {error}
        </p>
      )}
      <div className="mt-5 space-y-2" aria-live="polite">
        {results.map((person) => {
          const alreadyListed = listed.has(person.id);
          return (
            <div
              key={person.id}
              className="flex items-center gap-3 rounded-xl border border-line p-3"
            >
              <div className="min-w-0 flex-1">
                <p className="text-sm font-medium">{person.fullName}</p>
                {person.email && (
                  <p className="truncate text-xs text-muted">{person.email}</p>
                )}
              </div>
              <button
                type="button"
                className="secondary-button"
                disabled={alreadyListed}
                aria-label={
                  alreadyListed
                    ? `${person.fullName} already listed`
                    : `Add ${person.fullName}`
                }
                onClick={() => onAdd(person)}
              >
                <UserPlus size={15} />
                {alreadyListed ? "Already listed" : "Add"}
              </button>
            </div>
          );
        })}
        {searched && !busy && !error && results.length === 0 && (
          <p className="text-sm text-muted">No active organization members found.</p>
        )}
      </div>
    </Modal>
  );
}
