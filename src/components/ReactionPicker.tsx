import { HandHeart, Heart, Sparkles, ThumbsUp } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import type { FeedReactionSummary, FeedReactionType } from "../types";

const reactions: Array<{ type: FeedReactionType; label: string; icon: typeof Heart }> = [
  { type: "like", label: "Like", icon: ThumbsUp },
  { type: "amen", label: "Amen", icon: Heart },
  { type: "celebrate", label: "Celebrate", icon: Sparkles },
  { type: "support", label: "Support", icon: HandHeart },
];

export function ReactionPicker({
  value,
  summary,
  total,
  disabled,
  onChange,
}: {
  value?: FeedReactionType;
  summary?: FeedReactionSummary;
  total: number;
  disabled?: boolean;
  onChange: (reaction?: FeedReactionType) => void;
}) {
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  const selected = reactions.find((reaction) => reaction.type === value);
  const counts = summary ?? { like: total, amen: 0, celebrate: 0, support: 0 };
  const rankedReactions = reactions
    .filter(({ type }) => counts[type] > 0)
    .sort((left, right) => counts[right.type] - counts[left.type]);
  const visibleReactions = rankedReactions.slice(0, 3);
  const reactionDetails = rankedReactions
    .map(({ type, label }) => `${counts[type]} ${label}`)
    .join(", ");
  const reactionText = `${total} ${total === 1 ? "person" : "people"} reacted`;
  const buttonLabel = total
    ? `${selected ? `${selected.label}. ` : ""}${reactionText}${reactionDetails ? `. ${reactionDetails}` : ""}. Show reaction counts and choices`
    : "Choose a reaction";

  useEffect(() => {
    if (!open) return;
    const close = (event: PointerEvent) => {
      if (!root.current?.contains(event.target as Node)) setOpen(false);
    };
    const escape = (event: KeyboardEvent) => event.key === "Escape" && setOpen(false);
    document.addEventListener("pointerdown", close);
    document.addEventListener("keydown", escape);
    return () => {
      document.removeEventListener("pointerdown", close);
      document.removeEventListener("keydown", escape);
    };
  }, [open]);

  return (
    <div className="relative" ref={root}>
      <button
        type="button"
        className={`secondary-button border-0 ${value ? "text-olive" : ""}`}
        aria-label={buttonLabel}
        aria-expanded={open}
        disabled={disabled}
        onClick={() => setOpen((current) => !current)}
      >
        {total > 0 && <span className="inline-flex items-center gap-1" aria-hidden="true">
          {visibleReactions.map(({ type, icon: Icon }) => (
            <Icon key={type} size={16} fill={type === "amen" ? "currentColor" : "none"} />
          ))}
        </span>}
        {total > 0 ? reactionText : "React"}
        {!total && <span className="sr-only">Choose a reaction</span>}
      </button>
      {open && (
        <div className="absolute bottom-[calc(100%+.5rem)] left-0 z-30 grid min-w-48 gap-1 rounded-2xl border border-line bg-paper p-2 shadow-quiet" role="menu" aria-label="Reaction counts and choices">
          {reactions.map(({ type, label, icon: Icon }) => (
            <button
              key={type}
              type="button"
              role="menuitemradio"
              aria-checked={value === type}
              aria-label={label}
              className={`flex min-h-11 items-center gap-3 rounded-xl px-3 text-left hover:bg-parchment focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-olive ${value === type ? "bg-parchment text-olive" : ""}`}
              title={`${label}${counts[type] ? ` (${counts[type]})` : ""}`}
              onClick={() => { onChange(value === type ? undefined : type); setOpen(false); }}
            >
              <Icon size={18} aria-hidden="true" />
              <span className="flex-1">{label}</span>
              {counts[type] > 0 && <span className="text-sm text-muted" aria-hidden="true">{counts[type]}</span>}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
