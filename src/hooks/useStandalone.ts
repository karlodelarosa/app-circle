import { useEffect, useState } from "react";

const detectStandalone = () =>
  window.matchMedia?.("(display-mode: standalone)").matches ||
  Boolean((navigator as Navigator & { standalone?: boolean }).standalone);

export function useStandalone() {
  const [standalone, setStandalone] = useState(detectStandalone);

  useEffect(() => {
    const media = window.matchMedia?.("(display-mode: standalone)");
    const update = () => setStandalone(detectStandalone());
    media?.addEventListener("change", update);
    return () => media?.removeEventListener("change", update);
  }, []);

  return standalone;
}
