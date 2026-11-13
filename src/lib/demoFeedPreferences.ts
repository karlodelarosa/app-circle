const keys = {
  saved: "circles-demo-saved-feed-items",
  hidden: "circles-demo-hidden-feed-items",
} as const;

export type DemoFeedPreference = keyof typeof keys;

export function getDemoFeedPreferenceIds(preference: DemoFeedPreference): string[] {
  try {
    const value = window.sessionStorage.getItem(keys[preference]);
    return value ? JSON.parse(value) as string[] : [];
  } catch {
    return [];
  }
}

export function setDemoFeedPreference(preference: DemoFeedPreference, itemId: string, enabled: boolean) {
  try {
    const ids = new Set(getDemoFeedPreferenceIds(preference));
    if (enabled) ids.add(itemId);
    else ids.delete(itemId);
    window.sessionStorage.setItem(keys[preference], JSON.stringify([...ids]));
  } catch {
    // Demo preferences are best-effort when storage is blocked.
  }
}
