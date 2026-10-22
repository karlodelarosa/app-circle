import { ArrowLeft, Home } from "lucide-react";
import { useEffect, useLayoutEffect, useState } from "react";
import {
  Link,
  Outlet,
  useLocation,
  useNavigate,
} from "react-router-dom";
import { useStandalone } from "../hooks/useStandalone";

export function RouteScrollManager() {
  const { pathname } = useLocation();

  useLayoutEffect(() => {
    const previous = window.history.scrollRestoration;
    window.history.scrollRestoration = "manual";
    window.scrollTo({ top: 0, left: 0, behavior: "auto" });
    return () => {
      window.history.scrollRestoration = previous;
    };
  }, [pathname]);

  return null;
}

export function RouteOutlet() {
  const { pathname } = useLocation();
  return (
    <div key={pathname} className="route-reveal">
      <Outlet />
    </div>
  );
}

export function StandaloneRouteBar({
  homeTo,
  homeLabel,
  fallbackTo,
  hidden = false,
}: {
  homeTo: string;
  homeLabel: string;
  fallbackTo: string;
  hidden?: boolean;
}) {
  const standalone = useStandalone();
  const navigate = useNavigate();
  if (!standalone || hidden) return null;
  const goBack = () => {
    const historyIndex = Number(
      (window.history.state as { idx?: number } | null)?.idx ?? 0,
    );
    if (historyIndex > 0) navigate(-1);
    else navigate(fallbackTo, { replace: true });
  };
  return (
    <nav
      aria-label="App navigation"
      className="flex min-h-12 items-center justify-between border-b border-line bg-paper px-4"
    >
      <button
        type="button"
        onClick={goBack}
        className="inline-flex min-h-11 items-center gap-2 text-sm font-medium text-olive"
      >
        <ArrowLeft size={17} /> Back
      </button>
      <Link
        to={homeTo}
        className="inline-flex min-h-11 items-center gap-2 text-sm font-medium text-olive"
      >
        <Home size={17} /> {homeLabel}
      </Link>
    </nav>
  );
}

export function PwaUpdatePrompt() {
  const [visible, setVisible] = usePwaUpdateNotice();
  if (!visible) return null;
  return (
    <div
      role="status"
      className="fixed inset-x-4 bottom-24 z-[70] mx-auto flex max-w-md items-center gap-3 rounded-2xl bg-ink p-4 text-paper shadow-quiet lg:bottom-6"
    >
      <p className="min-w-0 flex-1 text-sm">A new version of Circles is ready.</p>
      <button
        type="button"
        className="min-h-10 rounded-xl bg-paper px-3 text-sm font-medium text-ink"
        onClick={() => {
          window.__circlesUpdatePending = false;
          void window.__circlesUpdateSW?.(true);
        }}
      >
        Update
      </button>
      <button
        type="button"
        className="min-h-10 px-2 text-sm text-paper/75"
        onClick={() => setVisible(false)}
      >
        Later
      </button>
    </div>
  );
}

function usePwaUpdateNotice() {
  const [visible, setVisible] = useState(
    () => Boolean(window.__circlesUpdatePending),
  );
  useEffect(() => {
    const show = () => setVisible(true);
    window.addEventListener("circles:pwa-update", show);
    if (window.__circlesUpdatePending) show();
    return () => window.removeEventListener("circles:pwa-update", show);
  }, []);
  return [visible, setVisible] as const;
}

declare global {
  interface Window {
    __circlesUpdateSW?: (reloadPage?: boolean) => Promise<void>;
    __circlesUpdatePending?: boolean;
  }
}
