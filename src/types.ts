export type Role = "admin" | "leader" | "member";
export type RsvpStatus = "attending" | "tentative" | "declined";
export type MeetingStatus = "scheduled" | "cancelled";
export type ConnectionStatus =
  | "new"
  | "contacted"
  | "visited"
  | "connected"
  | "closed";
export type ContactPreference = "email" | "phone" | "either";
export type PrayerCategory =
  "Family" | "Work or School" | "Health" | "Spiritual Growth" | "Other";

export interface Profile {
  id: string;
  personId?: string;
  fullName: string;
  email: string;
  avatarUrl?: string;
}

export interface Member extends Profile {
  membershipId: string;
  role: Role;
  account?: MemberAccountStatus;
  discipleshipBadge: boolean;
  badgeSource?: "manual" | "system_grandfathered";
  badgeAwardedAt?: string;
  leadershipStatus?: "approved" | "revoked";
}

export interface AccountTransition {
  action:
    | "generated_to_sheepcount"
    | "leadership_approved"
    | "badge_awarded"
    | "badge_revoked";
  note: string;
  createdAt: string;
}

export interface MemberAccountStatus {
  status: "none" | "active" | "inactive";
  kind?: "existing" | "generated";
  loginId?: string;
  mustChangePassword: boolean;
  transitions: AccountTransition[];
}

export interface ApprovedLeader {
  personId: string;
  fullName: string;
  email: string;
}

export interface Group {
  id: string;
  organizationId: string;
  name: string;
  description: string;
  regularSchedule: string;
  location: string;
  leaderId?: string;
  role: Role;
  slug?: string;
  coverUrl?: string;
  isPublic?: boolean;
}

export interface CirclePublicListing {
  id: string;
  organizationId: string;
  groupId: string;
  slug: string;
  description: string;
  coverUrl?: string;
  isPublished: boolean;
}

export interface GuestConnectionActivity {
  id: string;
  type:
    | "note"
    | "contacted"
    | "claimed"
    | "unclaimed"
    | "status_changed"
    | "converted";
  body: string;
  createdAt: string;
}

export interface GuestConnection {
  id: string;
  organizationId: string;
  groupId: string;
  groupName: string;
  name: string;
  email: string;
  phone: string;
  preferredContact: ContactPreference;
  followUpOptIn: boolean;
  consentedAt?: string;
  status: ConnectionStatus;
  claimedByPersonId?: string;
  claimedByName?: string;
  convertedPersonId?: string;
  lastActivityAt: string;
  rsvpCount: number;
  interestCount: number;
  attended: boolean;
  rsvps?: {
    id: string;
    gatheringId: string;
    title: string;
    startsAt: string;
    status: RsvpStatus;
    attendedAt?: string;
  }[];
  interests?: { id: string; message: string; status: string; createdAt: string }[];
  activities?: GuestConnectionActivity[];
}

export interface Organization {
  id: string;
  name: string;
  imageUrl?: string;
  subscriptionStatus: string;
  circlesEnabled: boolean;
  slug: string;
}

export interface Meeting {
  id: string;
  groupId: string;
  title: string;
  meetingDate: string;
  location: string;
  studyTopic: string;
  notes: string;
  status: MeetingStatus;
  createdBy: string;
  assignedLeaderId?: string;
  checkinCode?: string;
  checkinClosesAt?: string;
  rsvps: Record<string, RsvpStatus>;
  organizationId?: string;
  slug?: string;
  summary?: string;
  coverUrl?: string;
  visibility?: "private" | "public";
  publishedAt?: string;
  guestRsvpEnabled?: boolean;
}

export interface Announcement {
  id: string;
  organizationId: string;
  groupId?: string;
  title: string;
  body: string;
  publishedAt: string;
  expiresAt?: string;
  isPublic: boolean;
}

export interface Testimony {
  id: string;
  organizationId: string;
  groupId?: string;
  slug: string;
  title: string;
  body: string;
  authorName: string;
  authorPersonId?: string;
  imageUrl?: string;
  publishedAt: string;
  status?: "draft" | "published";
}

export interface GalleryPhoto {
  id: string;
  imageUrl: string;
  caption?: string;
  altText: string;
}
export interface Gallery {
  id: string;
  organizationId: string;
  gatheringId?: string;
  groupId?: string;
  slug: string;
  title: string;
  description: string;
  coverUrl?: string;
  publishedAt: string;
  photos: GalleryPhoto[];
}

export interface PublicSpace {
  organization: Organization;
  introduction: string;
  heroTitle: string;
  heroImageUrl?: string;
  gatherings: Meeting[];
  testimonies: Testimony[];
  galleries: Gallery[];
  circles: Group[];
  announcements: Announcement[];
}

export interface GuestRsvpInput {
  name: string;
  email: string;
  phone: string;
  status: RsvpStatus;
}

export interface PersonSearchResult {
  id: string;
  fullName: string;
  email: string;
  phone: string;
  membershipType: string;
  alreadyInGroup: boolean;
}

export interface PrayerRequest {
  id: string;
  groupId: string;
  userId: string;
  authorName: string;
  title: string;
  description: string;
  category: PrayerCategory;
  isAnswered: boolean;
  answeredNotes?: string;
  createdAt: string;
  prayerCount: number;
  prayedByMe: boolean;
}

export interface AppData {
  organization: Organization;
  groups: Group[];
  group: Group | null;
  members: Member[];
  meetings: Meeting[];
  prayers: PrayerRequest[];
  announcements: Announcement[];
  testimonies: Testimony[];
  galleries: Gallery[];
  publicCircleListings: CirclePublicListing[];
  approvedLeaders: ApprovedLeader[];
  currentUser: Profile & { role: Role };
  connectionAttentionCount: number;
  account: {
    kind?: "existing" | "generated";
    loginId?: string;
    mustChangePassword: boolean;
    status?: string;
  };
}

export interface MeetingInput {
  title: string;
  meetingDate: string;
  location: string;
  studyTopic: string;
  notes: string;
  summary?: string;
  visibility?: "private" | "public";
  guestRsvpEnabled?: boolean;
  coverUrl?: string;
  coverFile?: File;
  removeCover?: boolean;
}

export interface PrayerInput {
  title: string;
  description: string;
  category: PrayerCategory;
}
