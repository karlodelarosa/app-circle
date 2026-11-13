import { ArrowDown, Check, LoaderCircle, WifiOff } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { useStandalone } from "../hooks/useStandalone";

const PULL_THRESHOLD = 72;
const MAX_PULL_DISTANCE = 104;
const STALE_AFTER_MS = 60_000;

type RefreshStatus = "idle" | "pulling" | "refreshing" | "success" | "error" | "offline";

export function PwaRefreshController({
  refresh,
}: {
  refresh: () => Promise<boolean>;
}) {
  const standalone = useStandalone();
  const [status, setStatus] = useState<RefreshStatus>("idle");
  const [pullDistance, setPullDistance] = useState(0);
  const startPoint = useRef<{ x: number; y: number }>();
  const currentPull = useRef(0);
  const refreshPromise = useRef<Promise<boolean>>();
  const lastRefreshAt = useRef(Date.now());
  const resetTimer = useRef<number>();

  const scheduleReset = useCallback(() => {
    window.clearTimeout(resetTimer.current);
    resetTimer.current = window.setTimeout(() => setStatus("idle"), 1800);
  }, []);

  const runRefresh = useCallback(() => {
    if (refreshPromise.current) return refreshPromise.current;
    if (!navigator.onLine) {
      setStatus("offline");
      scheduleReset();
      return Promise.resolve(false);
    }

    setStatus("refreshing");
    setPullDistance(0);
    const operation = refresh()
      .then((succeeded) => {
        if (succeeded) lastRefreshAt.current = Date.now();
        setStatus(succeeded ? "success" : "error");
        scheduleReset();
        return succeeded;
      })
      .catch(() => {
        setStatus("error");
        scheduleReset();
        return false;
      })
      .finally(() => {
        refreshPromise.current = undefined;
      });
    refreshPromise.current = operation;
    return operation;
  }, [refresh, scheduleReset]);

  useEffect(() => {
    if (!standalone) return;

    const onTouchStart = (event: TouchEvent) => {
      if (refreshPromise.current || window.scrollY > 0 || event.touches.length !== 1) return;
      if (event.target instanceof Element && event.target.closest('[role="dialog"]')) return;
      const touch = event.touches[0];
      startPoint.current = { x: touch.clientX, y: touch.clientY };
      currentPull.current = 0;
    };
    const onTouchMove = (event: TouchEvent) => {
      if (!startPoint.current || event.touches.length !== 1) return;
      const touch = event.touches[0];
      const deltaX = touch.clientX - startPoint.current.x;
      const deltaY = touch.clientY - startPoint.current.y;
      if (Math.abs(deltaX) > Math.abs(deltaY) || deltaY <= 0) {
        startPoint.current = undefined;
        currentPull.current = 0;
        setPullDistance(0);
        setStatus("idle");
        return;
      }
      event.preventDefault();
      currentPull.current = deltaY;
      setPullDistance(Math.min(MAX_PULL_DISTANCE, deltaY));
      setStatus("pulling");
    };
    const onTouchEnd = () => {
      if (!startPoint.current) return;
      const shouldRefresh = currentPull.current >= PULL_THRESHOLD;
      startPoint.current = undefined;
      currentPull.current = 0;
      setPullDistance(0);
      if (shouldRefresh) void runRefresh();
      else setStatus("idle");
    };
    const onTouchCancel = () => {
      startPoint.current = undefined;
      currentPull.current = 0;
      setPullDistance(0);
      setStatus("idle");
    };
    const refreshIfStale = () => {
      if (document.visibilityState !== "visible") return;
      if (Date.now() - lastRefreshAt.current >= STALE_AFTER_MS) void runRefresh();
    };

    document.addEventListener("touchstart", onTouchStart, { passive: true });
    document.addEventListener("touchmove", onTouchMove, { passive: false });
    document.addEventListener("touchend", onTouchEnd, { passive: true });
    document.addEventListener("touchcancel", onTouchCancel, { passive: true });
    document.addEventListener("visibilitychange", refreshIfStale);
    window.addEventListener("pageshow", refreshIfStale);
    return () => {
      document.removeEventListener("touchstart", onTouchStart);
      document.removeEventListener("touchmove", onTouchMove);
      document.removeEventListener("touchend", onTouchEnd);
      document.removeEventListener("touchcancel", onTouchCancel);
      document.removeEventListener("visibilitychange", refreshIfStale);
      window.removeEventListener("pageshow", refreshIfStale);
      window.clearTimeout(resetTimer.current);
    };
  }, [runRefresh, standalone]);

  if (!standalone || status === "idle") return null;
  const ready = status === "pulling" && pullDistance >= PULL_THRESHOLD;
  const label = status === "pulling"
    ? ready ? "Release to refresh" : "Pull to refresh"
    : status === "refreshing"
      ? "Refreshing content"
      : status === "success"
        ? "Content updated"
        : status === "offline"
          ? "You’re offline. Current content is still available."
          : "Content could not be refreshed";
  const Icon = status === "refreshing"
    ? LoaderCircle
    : status === "success"
      ? Check
      : status === "offline" || status === "error"
        ? WifiOff
        : ArrowDown;

  return (
    <div
      role="status"
      aria-live="polite"
      className="pointer-events-none fixed left-1/2 top-[max(.75rem,env(safe-area-inset-top))] z-[80] flex -translate-x-1/2 items-center gap-2 rounded-full bg-ink px-4 py-2 text-xs font-medium text-paper shadow-quiet"
      style={status === "pulling" ? { transform: `translate(-50%, ${Math.min(32, pullDistance / 3)}px)` } : undefined}
    >
      <Icon size={15} className={status === "refreshing" ? "animate-spin" : ready ? "rotate-180" : ""} />
      {label}
    </div>
  );
}
