# Capability Map: Gathering Reflections and Prayer Audience

## Approved assumptions

1. Gathering comments are private to authenticated members, not public guests.
2. Comments are visible to everyone who can access the gathering, not only leaders.
3. Comments form a post-gathering discussion, with multiple comments allowed per member.
4. A Circle prayer is shared with the member's currently selected Circle; an organization prayer reaches all active organization members.
5. Prayer requests remain private inside the app and never appear on public organization pages.
6. Existing prayers remain Circle-only after migration.
7. Prayer actions, answered status, and praise reports follow the prayer's selected audience.

## Modules

| Module id | Responsibility | Depends on |
| --- | --- | --- |
| `prayer-scope` | Let a member choose **My Circle** or **Entire organization** when creating a prayer; enforce that audience for viewing, praying, and marking it answered. | Existing organization membership and Circle-access model |
| `gathering-comments` | Let authenticated members add and read comments attached to a completed gathering, with access inherited from that gathering's Circle or organization scope. | Existing gathering and membership-access model |

## Build order

`prayer-scope` and `gathering-comments` are independent and may be developed in either order or in parallel. The specification workflow starts with `prayer-scope`.
