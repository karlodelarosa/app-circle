import type { AppData } from '../types'

const now = new Date()
const addDays = (days: number, hour = 19) => {
  const value = new Date(now)
  value.setDate(value.getDate() + days)
  value.setHours(hour, 0, 0, 0)
  return value.toISOString()
}

export const demoData: AppData = {
  organization: {
    id: 'demo-org', slug: 'ministry-lens-church', name: 'Ministry Lens Church', subscriptionStatus: 'active', circlesEnabled: true
  },
  groups: [{
    id: 'demo-group', organizationId: 'demo-org', name: 'Grace & Ground',
    description: 'A small circle learning to follow Jesus in the ordinary rhythms of life.',
    regularSchedule: 'Every Thursday, 7:00 PM', location: '18 Acacia Street',
    leaderId: 'demo-user', role: 'leader', slug: 'grace-and-ground', isPublic: true, coverUrl: '/assets/devotional-table.webp'
  }],
  group: {
    id: 'demo-group', organizationId: 'demo-org',
    name: 'Grace & Ground',
    description: 'A small circle learning to follow Jesus in the ordinary rhythms of life.',
    regularSchedule: 'Every Thursday, 7:00 PM',
    location: '18 Acacia Street', leaderId: 'demo-user', role: 'leader', slug: 'grace-and-ground', isPublic: true, coverUrl: '/assets/devotional-table.webp'
  },
  currentUser: {
    id: 'demo-user',
    personId: 'demo-user',
    fullName: 'Karlo de la Rosa',
    email: 'karlo@example.com',
    role: 'leader'
  },
  connectionAttentionCount: 1,
  account: { kind: 'existing', mustChangePassword: false, status: 'active' },
  approvedLeaders: [{ personId: 'demo-user', fullName: 'Karlo de la Rosa', email: 'karlo@example.com' }],
  contentAssignments: [],
  members: [
    { id: 'demo-user', membershipId: 'membership-1', fullName: 'Karlo de la Rosa', email: 'karlo@example.com', role: 'leader', discipleshipBadge: true, badgeSource: 'system_grandfathered', leadershipStatus: 'approved', account: { status: 'active', kind: 'existing', mustChangePassword: false, transitions: [] } },
    { id: 'member-2', membershipId: 'membership-2', fullName: 'Mara Santos', email: 'mara@example.com', role: 'member', discipleshipBadge: true, badgeSource: 'manual', account: { status: 'active', kind: 'generated', loginId: 'mara.santos-k7p4', mustChangePassword: false, transitions: [] } },
    { id: 'member-3', membershipId: 'membership-3', fullName: 'Joaquin Reyes', email: 'joaquin@example.com', role: 'member', discipleshipBadge: false, account: { status: 'none', mustChangePassword: false, transitions: [] } },
    { id: 'member-4', membershipId: 'membership-4', fullName: 'Ana Lopez', email: 'ana@example.com', role: 'member', discipleshipBadge: false },
    { id: 'member-5', membershipId: 'membership-5', fullName: 'Theo Cruz', email: 'theo@example.com', role: 'member', discipleshipBadge: false }
  ],
  meetings: [
    {
      id: 'meeting-1', groupId: 'demo-group', title: 'Rooted in grace', meetingDate: addDays(2),
      location: 'The Reyes home · 18 Acacia Street', studyTopic: 'Colossians 2:6–7',
      notes: 'Bring your Bible and one story of grace from this week. Dinner will be served.',
      status: 'scheduled', createdBy: 'demo-user', organizationId: 'demo-org', slug: 'rooted-in-grace', summary: 'Dinner, Scripture, and an unhurried evening together.', visibility: 'public', publishedAt: now.toISOString(), guestRsvpEnabled: true, coverUrl: '/assets/devotional-table.webp',
      rsvps: { 'demo-user': 'attending', 'member-2': 'attending', 'member-3': 'tentative', 'member-4': 'attending' }
    },
    {
      id: 'meeting-2', groupId: 'demo-group', title: 'A life of prayer', meetingDate: addDays(9),
      location: 'The Santos home', studyTopic: 'Matthew 6:5–13', notes: 'We will share a simple meal before the study.',
      status: 'scheduled', createdBy: 'demo-user', organizationId: 'demo-org', slug: 'a-life-of-prayer', summary: 'A simple meal and a conversation about prayer.', visibility: 'public', publishedAt: now.toISOString(), guestRsvpEnabled: true, rsvps: {}
    },
    {
      id: 'meeting-3', groupId: 'demo-group', title: 'Carrying one another', meetingDate: addDays(-7),
      location: 'The Cruz home', studyTopic: 'Galatians 6:1–10',
      notes: 'We reflected on practical ways to carry one another’s burdens this month.',
      status: 'scheduled', createdBy: 'demo-user', organizationId: 'demo-org', slug: 'carrying-one-another', summary: 'A completed gathering kept available for people returning to an invitation.', visibility: 'public', publishedAt: now.toISOString(), guestRsvpEnabled: true, rsvps: { 'demo-user': 'attending', 'member-2': 'attending' }
    }
  ],
  announcements: [{ id: 'announcement-1', organizationId: 'demo-org', groupId: 'demo-group', title: 'Bring a story from your week', body: 'This Thursday we will begin around the table at 7:00 PM. Dinner is covered.', publishedAt: addDays(-1), isPublic: true }],
  testimonies: [{ id: 'testimony-1', organizationId: 'demo-org', groupId: 'demo-group', slug: 'grace-in-the-ordinary', title: 'Grace in the ordinary', body: 'In a season that felt hurried, our Circle became a place to slow down, listen, and notice how faithfully God was already at work.', authorName: 'Mara Santos', authorPersonId: 'member-2', imageUrl: '/assets/devotional-table.webp', publishedAt: addDays(-8), status: 'published' }],
  galleries: [{ id: 'gallery-1', organizationId: 'demo-org', groupId: 'demo-group', slug: 'life-around-the-table', title: 'Life around the table', description: 'Ordinary evenings made sacred by presence, prayer, and a shared meal.', coverUrl: '/assets/devotional-table.webp', publishedAt: addDays(-4), photos: [{ id: 'photo-1', imageUrl: '/assets/devotional-table.webp', altText: 'An open Bible and warm drink on a wooden table', caption: 'Making room to listen.' }] }],
  publicCircleListings: [{ id: 'demo-listing', organizationId: 'demo-org', groupId: 'demo-group', slug: 'grace-and-ground', description: 'A place for honest conversation, shared meals, and growing faith.', coverUrl: '/assets/devotional-table.webp', isPublished: true }],
  prayers: [
    {
      id: 'prayer-1', groupId: 'demo-group', userId: 'member-2', authorName: 'Mara Santos',
      title: 'Wisdom for a new season', description: 'Please pray for clarity as I consider a new role at work.',
      category: 'Work or School', isAnswered: false, createdAt: addDays(-1, 9), prayerCount: 8, prayedByMe: true
    },
    {
      id: 'prayer-2', groupId: 'demo-group', userId: 'member-3', authorName: 'Joaquin Reyes',
      title: 'Healing for my father', description: 'He has a procedure on Monday. Pray for peace and a smooth recovery.',
      category: 'Health', isAnswered: false, createdAt: addDays(-2, 14), prayerCount: 12, prayedByMe: false
    },
    {
      id: 'prayer-3', groupId: 'demo-group', userId: 'demo-user', authorName: 'Karlo de la Rosa',
      title: 'A gentle answer', description: 'Thank you for praying with us through a difficult family conversation.',
      category: 'Family', isAnswered: true, answeredNotes: 'God gave us honesty, patience, and a way forward.',
      createdAt: addDays(-5, 11), prayerCount: 6, prayedByMe: true
    }
  ]
}
