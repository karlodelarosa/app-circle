import { GATHERING_SHARE_PREVIEW_VERSION } from "./sharePreview";

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
  return `${canonicalGatheringUrl(orgSlug, gatheringSlug)}?share=${GATHERING_SHARE_PREVIEW_VERSION}`;
}

export function announcementShareUrl(orgSlug: string, announcementId: string) {
  return `${window.location.origin}/${encodeURIComponent(orgSlug)}/updates#announcement-${encodeURIComponent(announcementId)}`;
}

export function galleryImageUrl(
  organizationSlug: string,
  gallerySlug: string,
  photoId?: string,
) {
  const url = new URL("/__media/gallery-image", window.location.origin);
  url.searchParams.set("organization", organizationSlug);
  url.searchParams.set("gallery", gallerySlug);
  if (photoId) url.searchParams.set("photo", photoId);
  url.searchParams.set("v", "1");
  return url.href;
}
