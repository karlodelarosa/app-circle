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
  return canonicalGatheringUrl(orgSlug, gatheringSlug);
}
