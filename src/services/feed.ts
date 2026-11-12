import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  CommunityFeedPage,
  FeedAudience,
  FeedComment,
  FeedCommentPage,
  FeedCursor,
  FeedNotification,
  FeedNotificationPage,
} from "../types";
import { optimizeFeedPhoto, validateFeedPhotos } from "../lib/images";

const cleanBody = (body: string, maximum: number, label: string) => {
  const value = body.trim();
  if (!value || value.length > maximum)
    throw new Error(`${label} must be between 1 and ${maximum.toLocaleString()} characters.`);
  return value;
};

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
  const { data, error } = await client.rpc("get_circle_community_feed", {
    p_before_created_at: options.cursor?.createdAt ?? null,
    p_before_id: options.cursor?.id ?? null,
    p_limit: limit,
    p_circle_id: options.circleId ?? null,
    p_organization_only: options.organizationOnly ?? false,
  });
  if (error) throw error;
  const payload = (data ?? {}) as CommunityFeedPage;
  const paths = (payload.items ?? []).flatMap((item) =>
    item.photos.map((photo) => photo.url).filter((url) => !/^https?:|^\//.test(url) && url.includes("/")),
  );
  let signed = new Map<string, string>();
  if (paths.length) {
    const result = await client.storage.from("circle-feed-media").createSignedUrls(paths, 3600);
    if (result.error) throw result.error;
    signed = new Map((result.data ?? []).flatMap((entry) =>
      entry.path && entry.signedUrl ? [[entry.path, entry.signedUrl] as const] : [],
    ));
  }
  return {
    items: (payload.items ?? []).map((item) => ({
      ...item,
      photos: item.photos.map((photo) => ({ ...photo, url: signed.get(photo.url) ?? photo.url })),
    })),
    nextCursor: payload.nextCursor ?? undefined,
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
