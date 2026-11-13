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
  const SelectedIcon = selected?.icon ?? Heart;

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
        aria-label={value ? `${selected?.label}${total ? ` · ${total}` : ""}` : undefined}
        aria-expanded={open}
        disabled={disabled}
        onClick={() => setOpen((current) => !current)}
      >
        <SelectedIcon size={16} fill={value === "amen" ? "currentColor" : "none"} />
        {selected?.label ?? "React"}{total ? ` · ${total}` : ""}
        {!value && <span className="sr-only">Choose a reaction</span>}
      </button>
      {open && (
        <div className="absolute bottom-[calc(100%+.5rem)] left-0 z-30 flex gap-1 rounded-2xl border border-line bg-paper p-2 shadow-quiet" role="menu" aria-label="Reactions">
          {reactions.map(({ type, label, icon: Icon }) => (
            <button
              key={type}
              type="button"
              role="menuitemradio"
              aria-checked={value === type}
              aria-label={label}
              className={`grid min-h-11 min-w-11 place-items-center rounded-xl hover:bg-parchment focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-olive ${value === type ? "bg-parchment text-olive" : ""}`}
              title={`${label}${summary?.[type] ? ` (${summary[type]})` : ""}`}
              onClick={() => { onChange(value === type ? undefined : type); setOpen(false); }}
            >
              <Icon size={18} />
              <span className="sr-only">{label}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
