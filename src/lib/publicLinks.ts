export const LAST_PUBLIC_ORG_KEY = "circles:last-public-organization";

export function withBrowseMode(path: string, browse: boolean) {
  if (!browse) return path;
  const separator = path.includes("?") ? "&" : "?";
  return `${path}${separator}browse=1`;
}

export function publicCommunityUrl(orgSlug: string) {
  return `${window.location.origin}/${encodeURIComponent(orgSlug)}?browse=1`;
}

export function canonicalGatheringUrl(orgSlug: string, gatheringSlug: string) {
  return `${window.location.origin}/${encodeURIComponent(orgSlug)}/gatherings/${encodeURIComponent(gatheringSlug)}`;
}

export function gatheringShareUrl(orgSlug: string, gatheringSlug: string) {
  const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string | undefined;
  if (!supabaseUrl) return canonicalGatheringUrl(orgSlug, gatheringSlug);
  const query = new URLSearchParams({
    organization: orgSlug,
    gathering: gatheringSlug,
    origin: window.location.origin,
  });
  return `${supabaseUrl}/functions/v1/circle-gathering-share?${query}`;
}
