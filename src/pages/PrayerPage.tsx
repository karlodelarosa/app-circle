import {
  Check,
  Heart,
  MessageCircleHeart,
  Plus,
  Share2,
  Sparkles,
} from "lucide-react";
import { useEffect, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { useCircles } from "../AppContext";
import { Modal } from "../components/Modal";
import { PrayerForm } from "../components/PrayerForm";
import { relativeDate } from "../lib/format";
import { prayerShareUrl, type PrayerTab } from "../lib/prayerLinks";
import { shareLink } from "../lib/share";
import type { PrayerRequest } from "../types";

function AnswerForm({
  prayer,
  onDone,
}: {
  prayer: PrayerRequest;
  onDone: () => void;
}) {
  const { markAnswered } = useCircles();
  const [notes, setNotes] = useState("");
  const [busy, setBusy] = useState(false);
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        setBusy(true);
        void markAnswered(prayer.id, notes)
          .then(onDone)
          .finally(() => setBusy(false));
      }}
      className="space-y-5"
    >
      <p className="leading-6 text-muted">
        Share the good news your circle can celebrate with you.
      </p>
      <label className="field-label">
        Praise note
        <textarea
          className="field min-h-28"
          required
          value={notes}
          onChange={(event) => setNotes(event.target.value)}
          placeholder="How did God answer?"
          autoFocus
        />
      </label>
      <button className="primary-button w-full" disabled={busy}>
        {busy ? "Saving…" : "Share praise report"}
      </button>
    </form>
  );
}

export function PrayerPage() {
  const { data, togglePrayer, selectGroup } = useCircles();
  const [searchParams, setSearchParams] = useSearchParams();
  const requestedCircle = searchParams.get("circle");
  const requestedPrayer = searchParams.get("prayer");
  const requestedTab: PrayerTab =
    searchParams.get("tab") === "answered" ? "answered" : "in-prayer";
  const [composer, setComposer] = useState(false);
  const [answering, setAnswering] = useState<PrayerRequest | null>(null);
  const [showAnswered, setShowAnswered] = useState(
    requestedTab === "answered",
  );
  const [contextResolved, setContextResolved] = useState(!requestedCircle);
  const [shareStatus, setShareStatus] = useState("");
  const requestedCircleIsAccessible = Boolean(
    !requestedCircle || data?.groups.some((group) => group.id === requestedCircle),
  );

  useEffect(() => {
    setShowAnswered(requestedTab === "answered");
  }, [requestedTab]);

  useEffect(() => {
    if (!data || !requestedCircle || !requestedCircleIsAccessible) {
      setContextResolved(!requestedCircle || !requestedCircleIsAccessible);
      return;
    }
    if (data.group?.id === requestedCircle) {
      setContextResolved(true);
      return;
    }
    setContextResolved(false);
    void selectGroup(requestedCircle).then(() => setContextResolved(true));
    // selectGroup changes identity with context state; these ids are stable.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data?.group?.id, requestedCircle, requestedCircleIsAccessible]);

  const activeCircleId = data?.group?.id;
  const prayersForContext = (data?.prayers ?? []).filter(
    (prayer) =>
      prayer.scope === "organization" || prayer.groupId === activeCircleId,
  );
  const focusedPrayer = requestedPrayer
    ? prayersForContext.find((prayer) => prayer.id === requestedPrayer)
    : undefined;
  const unavailable =
    !requestedCircleIsAccessible ||
    (contextResolved &&
      Boolean(requestedCircle) &&
      activeCircleId !== requestedCircle) ||
    (contextResolved && Boolean(requestedPrayer) && !focusedPrayer);

  useEffect(() => {
    if (!contextResolved || unavailable || !requestedPrayer) return;
    document.getElementById(`prayer-${requestedPrayer}`)?.focus();
  }, [contextResolved, requestedPrayer, unavailable, showAnswered]);

  if (!data) return null;

  if (!contextResolved)
    return (
      <div className="empty-state" role="status">
        <MessageCircleHeart />
        <h2>Opening prayer board…</h2>
      </div>
    );

  if (unavailable)
    return (
      <div className="empty-state">
        <MessageCircleHeart />
        <h2>Prayer unavailable</h2>
        <p>
          This prayer may have been removed, or it may belong to a Circle you
          cannot access.
        </p>
        <Link className="secondary-button" to="/prayer">
          Open my prayer board
        </Link>
      </div>
    );

  const canParticipate = Boolean(data.currentUser.personId);
  const prayers = prayersForContext.filter(
    (item) => item.isAnswered === showAnswered,
  );
  const tab: PrayerTab = showAnswered ? "answered" : "in-prayer";
  const share = async (prayer?: PrayerRequest) => {
    setShareStatus("");
    try {
      const result = await shareLink(
        prayer?.title || `${data.group?.name || data.organization.name} prayer board`,
        prayerShareUrl(activeCircleId, tab, prayer?.id),
      );
      if (result === "cancelled") return;
      setShareStatus(
        result === "copied"
          ? `${prayer ? "Prayer" : "Prayer board"} link copied.`
          : `${prayer ? "Prayer" : "Prayer board"} shared.`,
      );
    } catch {
      setShareStatus("The prayer link could not be shared.");
    }
  };
  const changeTab = (next: PrayerTab) => {
    setShowAnswered(next === "answered");
    const nextParams = new URLSearchParams(searchParams);
    if (activeCircleId) nextParams.set("circle", activeCircleId);
    nextParams.set("tab", next);
    nextParams.delete("prayer");
    setSearchParams(nextParams, { replace: true });
  };

  return (
    <div>
      <div className="page-heading">
        <div>
          <p className="page-kicker">Held among friends</p>
          <h1>Prayer</h1>
          <p>A private wall for the things we’re carrying together.</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <button className="secondary-button" onClick={() => void share()}>
            <Share2 size={17} /> Share prayer board
          </button>
          {canParticipate && (
            <button className="primary-button" onClick={() => setComposer(true)}>
              <Plus size={17} /> Share a request
            </button>
          )}
        </div>
      </div>
      {shareStatus && (
        <p
          className="mt-5 rounded-xl bg-paper px-4 py-3 text-sm text-muted"
          role="status"
        >
          {shareStatus}
        </p>
      )}
      <div
        className="mt-8 flex border-b border-line"
        role="tablist"
        aria-label="Prayer status"
      >
        <button
          role="tab"
          aria-selected={!showAnswered}
          onClick={() => changeTab("in-prayer")}
          className={`tab-button ${!showAnswered ? "tab-button-active" : ""}`}
        >
          In prayer
        </button>
        <button
          role="tab"
          aria-selected={showAnswered}
          onClick={() => changeTab("answered")}
          className={`tab-button ${showAnswered ? "tab-button-active" : ""}`}
        >
          Answered
        </button>
      </div>
      {prayers.length ? (
        <div className="mt-6 columns-1 gap-5 md:columns-2">
          {prayers.map((prayer) => {
            const mayAnswer =
              data.currentUser.role === "admin" ||
              data.currentUser.personId === prayer.userId ||
              (prayer.scope === "circle" &&
                data.group?.role === "leader" &&
                data.group.id === prayer.groupId);
            const isFocused = prayer.id === requestedPrayer;
            return (
              <article
                key={prayer.id}
                id={`prayer-${prayer.id}`}
                tabIndex={-1}
                className={`prayer-card mb-5 break-inside-avoid focus:outline-none ${isFocused ? "ring-2 ring-olive" : ""}`}
              >
                <div className="flex items-center justify-between gap-3">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="category-label">{prayer.category}</span>
                    <span className="text-xs text-muted">
                      {prayer.destinationName || data.group?.name || "My Circle"}
                    </span>
                  </div>
                  <span className="text-xs text-muted">
                    {relativeDate(prayer.createdAt)}
                  </span>
                </div>
                <h2>{prayer.title}</h2>
                <p>{prayer.description}</p>
                {prayer.isAnswered && prayer.answeredNotes && (
                  <div className="praise-note">
                    <Sparkles size={17} />
                    <div>
                      <strong>Praise report</strong>
                      <p>{prayer.answeredNotes}</p>
                    </div>
                  </div>
                )}
                <div className="mt-6 flex items-center justify-between gap-3 border-t border-line pt-4">
                  <div>
                    <div className="text-sm font-medium">{prayer.authorName}</div>
                    <div className="text-xs text-muted">
                      {prayer.prayerCount}{" "}
                      {prayer.prayerCount === 1 ? "person has" : "people have"} prayed
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <button
                      className="icon-button"
                      aria-label={`Share ${prayer.title}`}
                      onClick={() => void share(prayer)}
                    >
                      <Share2 size={16} />
                    </button>
                    {canParticipate && (
                      <button
                        onClick={() => void togglePrayer(prayer.id)}
                        className={`prayed-button ${prayer.prayedByMe ? "prayed-button-active" : ""}`}
                        aria-pressed={prayer.prayedByMe}
                      >
                        {prayer.prayedByMe ? <Check size={16} /> : <Heart size={16} />}
                        {prayer.prayedByMe ? "Prayed" : "I prayed"}
                      </button>
                    )}
                  </div>
                </div>
                {!prayer.isAnswered && mayAnswer && (
                  <button
                    onClick={() => setAnswering(prayer)}
                    className="mt-4 text-xs font-medium text-olive hover:underline"
                  >
                    Mark as answered
                  </button>
                )}
              </article>
            );
          })}
        </div>
      ) : (
        <div className="empty-state mt-8">
          <MessageCircleHeart />
          <h2>
            {showAnswered ? "Praise reports will live here" : "Nothing shared yet"}
          </h2>
          <p>
            {showAnswered
              ? "When a prayer is answered, your circle can celebrate it together."
              : "Share what you would like your circle to hold in prayer."}
          </p>
          {!showAnswered && canParticipate && (
            <button className="secondary-button" onClick={() => setComposer(true)}>
              Share the first request
            </button>
          )}
        </div>
      )}
      {composer && (
        <Modal title="Please pray with me" onClose={() => setComposer(false)}>
          <PrayerForm onDone={() => setComposer(false)} />
        </Modal>
      )}
      {answering && (
        <Modal title="Mark as answered" onClose={() => setAnswering(null)}>
          <AnswerForm prayer={answering} onDone={() => setAnswering(null)} />
        </Modal>
      )}
    </div>
  );
}
