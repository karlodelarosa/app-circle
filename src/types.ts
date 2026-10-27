export type Role = "admin" | "leader" | "member";
export type RsvpStatus = "attending" | "tentative" | "declined";
export type MeetingStatus = "scheduled" | "completed" | "cancelled";
export type ConnectionStatus =
  | "new"
  | "contacted"
  | "visited"
  | "connected"
  | "closed";
export type ContactPreference = "email" | "phone" | "either";
export type CellGroupSignupStatus = "unassigned" | "placed";
export type CellGroupSignupSource =
  | "public"
  | "guest_self"
  | "leader_conversion";
export type PrayerCategory =
  "Family" | "Work or School" | "Health" | "Spiritual Growth" | "Other";
export type PrayerScope = "circle" | "organization";

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
    | "badge_revoked"
    | "login_replaced";
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
  groupId?: string;
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

export interface CellGroupSignup {
  id: string;
  organizationId: string;
  personId: string;
  firstName: string;
  lastName: string;
  fullName: string;
  birthdate: string;
  birthdateDiscrepancy?: string | null;
  phone: string;
  facebookContact: string;
  status: CellGroupSignupStatus;
  source: CellGroupSignupSource;
  sourceGuestConnectionId?: string;
  consentedAt: string;
  placedGroupId?: string;
  placedGroupName?: string;
  placedByPersonId?: string;
  placedAt?: string;
  createdAt: string;
  updatedAt: string;
}

export interface CellGroupSignupInput {
  firstName: string;
  lastName: string;
  birthdate: string;
  phone: string;
  facebookContact: string;
  consent: boolean;
  guestRsvpId?: string;
}

export interface CellGroupSignupResult {
  ok: boolean;
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
  groupId?: string;
  scope?: "circle" | "organization";
  destinationName?: string;
  canManage?: boolean;
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
  guestRsvpCounts?: Partial<Record<RsvpStatus, number>>;
  organizationId?: string;
  slug?: string;
  summary?: string;
  coverUrl?: string;
  visibility?: "private" | "public";
  publishedAt?: string;
  guestRsvpEnabled?: boolean;
  assignmentConfirmedAt?: string;
}

export interface GatheringReflection {
  id: string;
  gatheringId: string;
  organizationId: string;
  authorPersonId: string;
  authorName: string;
  body: string;
  createdAt: string;
  updatedAt: string;
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
  assignmentConfirmedAt?: string;
  destinationName?: string;
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
  assignmentConfirmedAt?: string;
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
  assignmentConfirmedAt?: string;
  destinationName?: string;
}

export type ContentAssignmentType =
  | "gathering"
  | "gallery"
  | "testimony"
  | "announcement";

export interface ContentAssignment {
  id: string;
  type: ContentAssignmentType;
  title: string;
  groupId?: string;
  groupName?: string;
  confirmedAt?: string;
  publishedAt?: string;
  hasParticipation: boolean;
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
  groupId?: string;
  scope: PrayerScope;
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
  destinationName?: string;
}

export interface AppData {
  organization: Organization;
  groups: Group[];
  group: Group | null;
  members: Member[];
  meetings: Meeting[];
  accessibleMeetings?: Meeting[];
  organizationMembers?: Member[];
  dashboard?: {
    meetings: Meeting[];
    prayers: PrayerRequest[];
    announcements: Announcement[];
    galleries: Gallery[];
  };
  prayers: PrayerRequest[];
  announcements: Announcement[];
  testimonies: Testimony[];
  galleries: Gallery[];
  publicCircleListings: CirclePublicListing[];
  approvedLeaders: ApprovedLeader[];
  contentAssignments: ContentAssignment[];
  currentUser: Profile & { role: Role };
  connectionAttentionCount: number;
  signupAttentionCount: number;
  account: {
    kind?: "existing" | "generated";
    loginId?: string;
    mustChangePassword: boolean;
    status?: string;
  };
}

export interface MeetingInput {
  scope: "circle" | "organization";
  groupId?: string;
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
  scope: PrayerScope;
  groupId?: string;
}
