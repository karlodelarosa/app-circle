import type { SupabaseClient } from "@supabase/supabase-js";
import {
  addPrayerUpdate,
  createFeedPost,
  deleteFeedPost,
  getCommunityMemberProfile,
  loadFeedCommentsPage,
  loadFeedNotificationPage,
  loadCommunityFeed,
  saveCommunityProfile,
  setFeedReaction,
  setFeedSaved,
  setPrayerFollow,
} from "./feed";

describe("community feed service", () => {
  it("loads a snapshot-stable activity page and normalizes comments and photos", async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: {
        items: [
          {
            id: "feed-1",
            type: "post",
            audience: "organization",
            destinationName: "Entire organization",
            authorPersonId: "person-1",
            authorName: "Mara Santos",
            body: "Grace for today.",
            createdAt: "2026-11-13T02:00:00.000Z",
            photos: [{ id: "photo-1", url: "signed", altText: "Shared table", displayOrder: 0 }],
            comments: [{ id: "comment-1", authorPersonId: "person-2", authorName: "Theo Cruz", body: "Amen", createdAt: "2026-11-13T02:01:00.000Z" }],
            commentCount: 1,
            likeCount: 2,
            likedByMe: true,
            canModerate: false,
            canEdit: true,
          },
        ],
        nextCursor: { activityAt: "2026-11-13T02:00:00.000Z", id: "feed-1", snapshotAt: "2026-11-13T03:00:00.000Z" },
      },
      error: null,
    });

    const result = await loadCommunityFeed(
      { rpc } as unknown as SupabaseClient,
      { limit: 20, circleId: "circle-1" },
    );

    expect(rpc).toHaveBeenCalledWith("get_circle_community_feed_v2", {
      p_before_activity_at: null,
      p_before_id: null,
      p_snapshot_at: null,
      p_limit: 20,
      p_circle_id: "circle-1",
      p_organization_only: false,
    });
    expect(result.items[0].photos[0].altText).toBe("Shared table");
    expect(result.nextCursor?.id).toBe("feed-1");
  });

  it("rejects an empty update before writing", async () => {
    const from = vi.fn();

    await expect(
      createFeedPost(
        { from } as unknown as SupabaseClient,
        {
          organizationId: "org-1",
          authorPersonId: "person-1",
          audience: "organization",
          body: "   ",
          photos: [],
        },
      ),
    ).rejects.toThrow("Write an update or add a photo");
    expect(from).not.toHaveBeenCalled();
  });

  it("writes reactions, saves, and follows through authorized RPCs", async () => {
    const rpc = vi.fn().mockResolvedValue({ data: null, error: null });
    const client = { rpc } as unknown as SupabaseClient;

    await setFeedReaction(client, "feed-1", "amen");
    await setFeedSaved(client, "feed-1", true);
    await setPrayerFollow(client, "prayer-1", true);

    expect(rpc).toHaveBeenNthCalledWith(1, "set_circle_feed_reaction", { p_feed_item_id: "feed-1", p_reaction: "amen" });
    expect(rpc).toHaveBeenNthCalledWith(2, "set_circle_feed_saved", { p_feed_item_id: "feed-1", p_saved: true });
    expect(rpc).toHaveBeenNthCalledWith(3, "set_circle_prayer_follow", { p_prayer_id: "prayer-1", p_followed: true });
  });

  it("validates profile and prayer update input before calling RPCs", async () => {
    const rpc = vi.fn().mockResolvedValue({ data: { id: "update-1" }, error: null });
    const client = { rpc } as unknown as SupabaseClient;

    await saveCommunityProfile(client, {
      bio: "Learning to serve faithfully.",
      bioVisibility: "organization",
      joinDateVisibility: "shared_circle",
    });
    await addPrayerUpdate(client, "prayer-1", "progress", "The procedure went well.");

    expect(rpc).toHaveBeenNthCalledWith(1, "upsert_circle_community_profile", {
      p_bio: "Learning to serve faithfully.", p_bio_visibility: "organization", p_join_date_visibility: "shared_circle",
    });
    expect(rpc).toHaveBeenNthCalledWith(2, "add_circle_prayer_update", {
      p_prayer_id: "prayer-1", p_update_type: "progress", p_body: "The procedure went well.",
    });
    await expect(addPrayerUpdate(client, "prayer-1", "progress", " ")).rejects.toThrow("Prayer updates");
  });

  it("loads an audience-sanitized community profile", async () => {
    const rpc = vi.fn().mockResolvedValue({ data: { personId: "person-1", fullName: "Mara Santos", circles: [], recentItems: [] }, error: null });
    const client = { rpc } as unknown as SupabaseClient;
    const profile = await getCommunityMemberProfile(client, "person-1");
    expect(rpc).toHaveBeenCalledWith("get_circle_community_member_profile", { p_person_id: "person-1" });
    expect(profile.fullName).toBe("Mara Santos");
  });

  it("passes stable cursors to comment and notification pages", async () => {
    const rpc = vi.fn()
      .mockResolvedValueOnce({ data: { comments: [], nextCursor: null }, error: null })
      .mockResolvedValueOnce({ data: { notifications: [], nextCursor: null }, error: null });
    const client = { rpc } as unknown as SupabaseClient;
    const cursor = { createdAt: "2026-11-13T02:00:00.000Z", id: "00000000-0000-4000-8000-000000000001" };

    await loadFeedCommentsPage(client, "feed-1", cursor, 25);
    expect(rpc).toHaveBeenNthCalledWith(1, "get_circle_feed_comments", {
      p_feed_item_id: "feed-1", p_after_created_at: cursor.createdAt, p_after_id: cursor.id, p_limit: 25,
    });
    await loadFeedNotificationPage(client, cursor, 15);
    expect(rpc).toHaveBeenNthCalledWith(2, "get_circle_feed_notifications", {
      p_before_updated_at: cursor.createdAt, p_before_id: cursor.id, p_limit: 15,
    });
  });

  it("cleans private photo objects after deleting their post", async () => {
    const selectEq = vi.fn().mockResolvedValue({ data: [{ storage_path: "org/person/photo.webp" }], error: null });
    const select = vi.fn().mockReturnValue({ eq: selectEq });
    const deleteEq = vi.fn().mockResolvedValue({ error: null });
    const removeRow = vi.fn().mockReturnValue({ eq: deleteEq });
    const removeObjects = vi.fn().mockResolvedValue({ error: null });
    const from = vi.fn((table: string) => table === "circle_feed_post_photos"
      ? { select }
      : { delete: removeRow });
    const storageFrom = vi.fn().mockReturnValue({ remove: removeObjects });

    await deleteFeedPost({ from, storage: { from: storageFrom } } as unknown as SupabaseClient, "post-1");

    expect(deleteEq).toHaveBeenCalledWith("id", "post-1");
    expect(removeObjects).toHaveBeenCalledWith(["org/person/photo.webp"]);
  });
});
