import { useEffect, useId, useRef, useState } from "react";

interface TurnstileApi {
  render(container: HTMLElement, options: {
    sitekey: string;
    callback: (token: string) => void;
    "expired-callback": () => void;
    "error-callback": () => void;
    theme: "light";
  }): string;
  remove(widgetId: string): void;
}

declare global {
  interface Window {
    turnstile?: TurnstileApi;
  }
}

let loader: Promise<void> | undefined;
function loadTurnstile() {
  if (window.turnstile) return Promise.resolve();
  if (loader) return loader;
  loader = new Promise((resolve, reject) => {
    const existing = document.querySelector<HTMLScriptElement>("script[data-circles-turnstile]");
    const script = existing || document.createElement("script");
    script.addEventListener("load", () => resolve(), { once: true });
    script.addEventListener("error", () => reject(new Error("Verification unavailable")), { once: true });
    if (!existing) {
      script.src = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";
      script.async = true;
      script.defer = true;
      script.dataset.circlesTurnstile = "true";
      document.head.append(script);
    }
  });
  return loader;
}

export function Turnstile({ onToken }: { onToken: (token: string) => void }) {
  const siteKey = import.meta.env.VITE_TURNSTILE_SITE_KEY || "";
  const testMode = import.meta.env.MODE === "test";
  const container = useRef<HTMLDivElement>(null);
  const statusId = useId();
  const [failed, setFailed] = useState(!siteKey && !testMode);

  useEffect(() => {
    if (testMode) {
      onToken("test-token");
      return () => onToken("");
    }
    if (!siteKey || !container.current) return;
    let active = true;
    let widgetId: string | undefined;
    void loadTurnstile()
      .then(() => {
        if (!active || !container.current || !window.turnstile) return;
        widgetId = window.turnstile.render(container.current, {
          sitekey: siteKey,
          theme: "light",
          callback: (token) => {
            setFailed(false);
            onToken(token);
          },
          "expired-callback": () => onToken(""),
          "error-callback": () => {
            onToken("");
            setFailed(true);
          },
        });
      })
      .catch(() => setFailed(true));
    return () => {
      active = false;
      if (widgetId && window.turnstile) window.turnstile.remove(widgetId);
      onToken("");
    };
  }, [onToken, siteKey, testMode]);

  return (
    <div aria-describedby={statusId}>
      <div ref={container} />
      <p id={statusId} className={`mt-1 text-xs ${failed ? "text-red-700" : "text-muted"}`} role={failed ? "alert" : undefined}>
        {failed ? "Security verification is unavailable. Please refresh and try again." : "Complete the security check before submitting."}
      </p>
    </div>
  );
}
