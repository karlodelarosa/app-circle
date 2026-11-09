export type PrayerTab = "in-prayer" | "answered";

export function prayerShareUrl(
  circleId: string | undefined,
  tab: PrayerTab,
  prayerId?: string,
) {
  const url = new URL("/prayer", window.location.origin);
  if (circleId) url.searchParams.set("circle", circleId);
  url.searchParams.set("tab", tab);
  if (prayerId) url.searchParams.set("prayer", prayerId);
  return url.toString();
}
