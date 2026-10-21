import type { Profile } from '../types'

const tones = ['bg-[#D9CDB7]', 'bg-[#C9D0BC]', 'bg-[#D8C3B5]', 'bg-[#BAC8C0]']

export function Avatar({ person, size = 'md' }: { person: Pick<Profile, 'fullName' | 'avatarUrl' | 'id'>; size?: 'sm' | 'md' | 'lg' }) {
  const initials = person.fullName.split(' ').map((part) => part[0]).slice(0, 2).join('')
  const tone = tones[person.id.charCodeAt(0) % tones.length]
  const classes = size === 'lg' ? 'h-12 w-12 text-sm' : size === 'sm' ? 'h-7 w-7 text-[10px]' : 'h-9 w-9 text-xs'
  if (person.avatarUrl) return <img src={person.avatarUrl} alt="" className={`${classes} rounded-full object-cover ring-2 ring-paper`} />
  return <span aria-hidden="true" className={`${classes} ${tone} inline-flex shrink-0 items-center justify-center rounded-full font-semibold text-ink ring-2 ring-paper`}>{initials}</span>
}
