import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  CommunityFeedItem,
  CommunityFeedPage,
  CommunityMemberProfile,
  CommunityProfileVisibility,
  FeedAudience,
  FeedComment,
  FeedCommentPage,
  FeedCursor,
  FeedNotification,
  FeedNotificationPage,
  FeedReactionType,
  FeedReportReason,
  PrayerUpdate,
  PrayerUpdateType,
} from "../types";
import { optimizeFeedPhoto, validateFeedPhotos } from "../lib/images";

const cleanBody = (body: string, maximum: number, label: string) => {
  const value = body.trim();
  if (!value || value.length > maximum)
    throw new Error(`${label} must be between 1 and ${maximum.toLocaleString()} characters.`);
  return value;
};

async function signFeedPhotos(client: SupabaseClient, items: CommunityFeedItem[]) {
  const paths = items.flatMap((item) =>
    item.photos.map((photo) => photo.url).filter((url) => !/^https?:|^\//.test(url) && url.includes("/")),
  );
  if (!paths.length) return items;
  const result = await client.storage.from("circle-feed-media").createSignedUrls([...new Set(paths)], 3600);
  if (result.error) throw result.error;
  const signed = new Map((result.data ?? []).flatMap((entry) =>
    entry.path && entry.signedUrl ? [[entry.path, entry.signedUrl] as const] : [],
  ));
  return items.map((item) => ({
    ...item,
    photos: item.photos.map((photo) => ({ ...photo, url: signed.get(photo.url) ?? photo.url })),
  }));
}

export async function loadCommunityFeed(
  client: SupabaseClient,
  options: {
    cursor?: FeedCursor;
    limit?: number;
    circleId?: string;
    organizationOnly?: boolean;
  } = {},
): Promise<CommunityFeedPage> {
  const limit = Math.min(Math.max(options.limit ?? 20, 1), 50);
  const { data, error } = await client.rpc("get_circle_community_feed_v2", {
    p_before_activity_at: options.cursor?.activityAt ?? null,
    p_before_id: options.cursor?.id ?? null,
    p_snapshot_at: options.cursor?.snapshotAt ?? null,
    p_limit: limit,
    p_circle_id: options.circleId ?? null,
    p_organization_only: options.organizationOnly ?? false,
  });
  if (error) throw error;
  const payload = (data ?? {}) as CommunityFeedPage;
  const allItems = await signFeedPhotos(client, [...(payload.pinnedItems ?? []), ...(payload.items ?? [])]);
  const pinnedCount = payload.pinnedItems?.length ?? 0;
  return {
    items: allItems.slice(pinnedCount),
    pinnedItems: allItems.slice(0, pinnedCount),
    nextCursor: payload.nextCursor ?? undefined,
    snapshotAt: payload.snapshotAt,
  };
}

export async function uploadFeedPhotos(
  client: SupabaseClient,
  organizationId: string,
  personId: string,
  photos: Array<{ file: File; altText: string }>,
) {
  validateFeedPhotos(photos.map((photo) => photo.file));
  if (photos.some((photo) => !photo.altText.trim() || photo.altText.trim().length > 300))
    throw new Error("Describe each photo in 300 characters or fewer.");
  const uploaded: Array<{ storagePath: string; altText: string; displayOrder: number }> = [];
  try {
    for (const [displayOrder, photo] of photos.entries()) {
      const blob = await optimizeFeedPhoto(photo.file);
      const storagePath = `${organizationId}/${personId}/${crypto.randomUUID()}.webp`;
      const { error } = await client.storage.from("circle-feed-media").upload(storagePath, blob, {
        contentType: "image/webp",
        upsert: false,
      });
      if (error) throw error;
      uploaded.push({ storagePath, altText: photo.altText.trim(), displayOrder });
    }
    return uploaded;
  } catch (cause) {
    if (uploaded.length)
      await client.storage.from("circle-feed-media").remove(uploaded.map((photo) => photo.storagePath));
    throw cause;
  }
}

export async function createFeedPost(
  client: SupabaseClient,
  input: {
    organizationId: string;
    authorPersonId: string;
    audience: FeedAudience;
    groupId?: string;
    body: string;
    photos: Array<{ storagePath: string; altText: string; displayOrder: number }>;
  },
): Promise<string> {
  const body = input.body.trim();
  if (!body && !input.photos.length)
    throw new Error("Write an update or add a photo before sharing.");
  if (body.length > 5_000) throw new Error("Updates can be up to 5,000 characters.");
  if (input.photos.length > 4) throw new Error("Add no more than four photos.");
  if (input.audience === "circle" && !input.groupId)
    throw new Error("Choose a Circle for this update.");
  if (input.photos.some((photo) => !photo.altText.trim() || photo.altText.trim().length > 300))
    throw new Error("Describe each photo in 300 characters or fewer.");

  const { data, error } = await client
    .from("circle_feed_posts")
    .insert({
      organization_id: input.organizationId,
      cell_group_id: input.audience === "circle" ? input.groupId : null,
      author_person_id: input.authorPersonId,
      audience: input.audience,
      body,
    })
    .select("id")
    .single();
  if (error) {
    if (input.photos.length)
      await client.storage.from("circle-feed-media").remove(input.photos.map((photo) => photo.storagePath));
    throw error;
  }
  const postId = data.id as string;
  if (input.photos.length) {
    const { error: photoError } = await client.from("circle_feed_post_photos").insert(
      input.photos.map((photo) => ({
        organization_id: input.organizationId,
        post_id: postId,
        storage_path: photo.storagePath,
        alt_text: photo.altText.trim(),
        display_order: photo.displayOrder,
      })),
    );
    if (photoError) {
      await client.from("circle_feed_posts").delete().eq("id", postId);
      await client.storage.from("circle-feed-media").remove(input.photos.map((photo) => photo.storagePath));
      throw photoError;
    }
  }
  return postId;
}

export async function updateFeedPost(client: SupabaseClient, postId: string, body: string) {
  const value = cleanBody(body, 5_000, "An update");
  const { error } = await client
    .from("circle_feed_posts")
    .update({ body: value, updated_at: new Date().toISOString() })
    .eq("id", postId);
  if (error) throw error;
}

export async function deleteFeedPost(client: SupabaseClient, postId: string) {
  const { data: photos, error: photoError } = await client
    .from("circle_feed_post_photos")
    .select("storage_path")
    .eq("post_id", postId);
  if (photoError) throw photoError;
  const { error } = await client.from("circle_feed_posts").delete().eq("id", postId);
  if (error) throw error;
  const paths = (photos ?? []).map((photo) => photo.storage_path as string);
  if (paths.length) {
    const { error: storageError } = await client.storage.from("circle-feed-media").remove(paths);
    if (storageError) throw storageError;
  }
}

export async function removeFeedPhoto(client: SupabaseClient, photoId: string) {
  const { data, error: readError } = await client
    .from("circle_feed_post_photos")
    .select("storage_path")
    .eq("id", photoId)
    .single();
  if (readError) throw readError;
  const { error } = await client.from("circle_feed_post_photos").delete().eq("id", photoId);
  if (error) throw error;
  const { error: storageError } = await client.storage
    .from("circle-feed-media")
    .remove([data.storage_path as string]);
  if (storageError) throw storageError;
}

export async function addFeedComment(
  client: SupabaseClient,
  feedItemId: string,
  authorPersonId: string,
  body: string,
): Promise<void> {
  const value = cleanBody(body, 2_000, "A comment");
  const { error } = await client.from("circle_feed_comments").insert({
    feed_item_id: feedItemId,
    author_person_id: authorPersonId,
    body: value,
  });
  if (error) throw error;
}

export async function updateFeedComment(client: SupabaseClient, commentId: string, body: string) {
  const value = cleanBody(body, 2_000, "A comment");
  const { error } = await client
    .from("circle_feed_comments")
    .update({ body: value, updated_at: new Date().toISOString() })
    .eq("id", commentId);
  if (error) throw error;
}

export async function deleteFeedComment(client: SupabaseClient, commentId: string) {
  const { error } = await client.from("circle_feed_comments").delete().eq("id", commentId);
  if (error) throw error;
}

export async function loadFeedComments(
  client: SupabaseClient,
  feedItemId: string,
): Promise<FeedComment[]> {
  return (await loadFeedCommentsPage(client, feedItemId, undefined, 200)).comments;
}

export async function loadFeedCommentsPage(
  client: SupabaseClient,
  feedItemId: string,
  cursor?: FeedCursor,
  limit = 50,
): Promise<FeedCommentPage> {
  const { data, error } = await client.rpc("get_circle_feed_comments", {
    p_feed_item_id: feedItemId,
    p_after_created_at: cursor?.createdAt ?? null,
    p_after_id: cursor?.id ?? null,
    p_limit: Math.min(Math.max(limit, 1), 200),
  });
  if (error) throw error;
  const payload = (data ?? {}) as FeedCommentPage;
  return { comments: payload.comments ?? [], nextCursor: payload.nextCursor ?? undefined };
}

export async function setFeedLike(
  client: SupabaseClient,
  feedItemId: string,
  personId: string,
  liked: boolean,
) {
  const request = liked
    ? client.from("circle_feed_likes").upsert(
        { feed_item_id: feedItemId, person_id: personId },
        { onConflict: "feed_item_id,person_id" },
      )
    : client
        .from("circle_feed_likes")
        .delete()
        .eq("feed_item_id", feedItemId)
        .eq("person_id", personId);
  const { error } = await request;
  if (error) throw error;
}

export async function setFeedReaction(
  client: SupabaseClient,
  feedItemId: string,
  reaction?: FeedReactionType,
) {
  const { error } = await client.rpc("set_circle_feed_reaction", {
    p_feed_item_id: feedItemId,
    p_reaction: reaction ?? null,
  });
  if (error) throw error;
}

export async function setFeedSaved(client: SupabaseClient, feedItemId: string, saved: boolean) {
  const { error } = await client.rpc("set_circle_feed_saved", {
    p_feed_item_id: feedItemId,
    p_saved: saved,
  });
  if (error) throw error;
}

export async function setFeedPersonallyHidden(client: SupabaseClient, feedItemId: string, hidden: boolean) {
  const { error } = await client.rpc("set_circle_feed_personally_hidden", {
    p_feed_item_id: feedItemId,
    p_hidden: hidden,
  });
  if (error) throw error;
}

export async function reportFeedItem(
  client: SupabaseClient,
  feedItemId: string,
  reason: FeedReportReason,
  note = "",
) {
  const value = note.trim();
  if (value.length > 1_000) throw new Error("Report notes can be up to 1,000 characters.");
  const { error } = await client.rpc("report_circle_feed_item", {
    p_feed_item_id: feedItemId,
    p_reason: reason,
    p_note: value || null,
  });
  if (error) throw error;
}

export async function setFeedCommentsEnabled(client: SupabaseClient, feedItemId: string, enabled: boolean) {
  const { error } = await client.rpc("set_circle_feed_comments_enabled", {
    p_feed_item_id: feedItemId,
    p_enabled: enabled,
  });
  if (error) throw error;
}

export async function setFeedPinned(client: SupabaseClient, feedItemId: string, pinned: boolean) {
  const { error } = await client.rpc("set_circle_feed_pinned", {
    p_feed_item_id: feedItemId,
    p_pinned: pinned,
  });
  if (error) throw error;
}

export async function setPrayerFollow(client: SupabaseClient, prayerId: string, followed: boolean) {
  const { error } = await client.rpc("set_circle_prayer_follow", {
    p_prayer_id: prayerId,
    p_followed: followed,
  });
  if (error) throw error;
}

export async function addPrayerUpdate(
  client: SupabaseClient,
  prayerId: string,
  type: PrayerUpdateType,
  body: string,
): Promise<string> {
  const value = cleanBody(body, 2_000, "Prayer updates");
  const { data, error } = await client.rpc("add_circle_prayer_update", {
    p_prayer_id: prayerId,
    p_update_type: type,
    p_body: value,
  });
  if (error) throw error;
  return typeof data === "string" ? data : String((data as { id?: string } | null)?.id ?? "");
}

export async function loadPrayerUpdates(client: SupabaseClient, prayerId: string): Promise<PrayerUpdate[]> {
  const { data, error } = await client.rpc("get_circle_prayer_updates", { p_prayer_id: prayerId });
  if (error) throw error;
  return (data ?? []) as PrayerUpdate[];
}

export async function saveCommunityProfile(
  client: SupabaseClient,
  input: {
    bio: string;
    bioVisibility: CommunityProfileVisibility;
    joinDateVisibility: CommunityProfileVisibility;
  },
) {
  const bio = input.bio.trim();
  if (bio.length > 500) throw new Error("Your community bio can be up to 500 characters.");
  const { error } = await client.rpc("upsert_circle_community_profile", {
    p_bio: bio,
    p_bio_visibility: input.bioVisibility,
    p_join_date_visibility: input.joinDateVisibility,
  });
  if (error) throw error;
}

export async function getCommunityMemberProfile(
  client: SupabaseClient,
  personId: string,
): Promise<CommunityMemberProfile> {
  const { data, error } = await client.rpc("get_circle_community_member_profile", { p_person_id: personId });
  if (error) throw error;
  if (!data) throw new Error("This member profile is not available.");
  const profile = data as CommunityMemberProfile;
  return { ...profile, recentItems: await signFeedPhotos(client, profile.recentItems ?? []) };
}

export async function searchCommunityMembers(client: SupabaseClient, query = "") {
  const { data, error } = await client.rpc("search_circle_community_members", {
    p_query: query.trim(),
    p_limit: 50,
  });
  if (error) throw error;
  return (data ?? []) as CommunityMemberProfile[];
}

export async function searchCommunityFeed(
  client: SupabaseClient,
  input: { query?: string; type?: string; circleId?: string; authorPersonId?: string; savedOnly?: boolean },
): Promise<CommunityFeedItem[]> {
  const { data, error } = await client.rpc("search_circle_community_feed", {
    p_query: input.query?.trim() || null,
    p_type: input.type || null,
    p_circle_id: input.circleId || null,
    p_author_person_id: input.authorPersonId || null,
    p_saved_only: input.savedOnly ?? false,
    p_limit: 50,
  });
  if (error) throw error;
  return signFeedPhotos(client, (data ?? []) as CommunityFeedItem[]);
}

export async function getCommunityFeedItem(client: SupabaseClient, feedItemId: string): Promise<CommunityFeedItem> {
  const { data, error } = await client.rpc("get_circle_community_feed_item", { p_feed_item_id: feedItemId });
  if (error) throw error;
  if (!data) throw new Error("This community post is not available.");
  return (await signFeedPhotos(client, [data as CommunityFeedItem]))[0];
}

export async function markCommunityFeedSeen(client: SupabaseClient) {
  const { error } = await client.rpc("mark_circle_community_feed_seen");
  if (error) throw error;
}

export async function setFeedItemHidden(client: SupabaseClient, feedItemId: string, hidden: boolean) {
  const { error } = await client.rpc("set_circle_feed_item_hidden", {
    p_feed_item_id: feedItemId,
    p_hidden: hidden,
  });
  if (error) throw error;
}

export async function loadFeedNotifications(client: SupabaseClient): Promise<FeedNotification[]> {
  return (await loadFeedNotificationPage(client)).notifications;
}

export async function loadFeedNotificationPage(
  client: SupabaseClient,
  cursor?: FeedCursor,
  limit = 30,
): Promise<FeedNotificationPage> {
  const { data, error } = await client.rpc("get_circle_feed_notifications", {
    p_before_updated_at: cursor?.createdAt ?? null,
    p_before_id: cursor?.id ?? null,
    p_limit: Math.min(Math.max(limit, 1), 100),
  });
  if (error) throw error;
  const payload = (data ?? {}) as FeedNotificationPage;
  return { notifications: payload.notifications ?? [], nextCursor: payload.nextCursor ?? undefined };
}

export async function markFeedNotificationsRead(client: SupabaseClient) {
  const { error } = await client.rpc("mark_circle_feed_notifications_read");
  if (error) throw error;
}
