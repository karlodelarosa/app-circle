export const formatDate = (value: string, options?: Intl.DateTimeFormatOptions) => new Intl.DateTimeFormat('en', options ?? {
  weekday: 'long', month: 'long', day: 'numeric'
}).format(new Date(value))

export const formatTime = (value: string) => new Intl.DateTimeFormat('en', {
  hour: 'numeric', minute: '2-digit'
}).format(new Date(value))

export const toDateTimeLocal = (value: string) => {
  const date = new Date(value)
  const offset = date.getTimezoneOffset()
  return new Date(date.getTime() - offset * 60_000).toISOString().slice(0, 16)
}

export const firstName = (name: string) => name.split(' ')[0]

export const relativeDate = (value: string) => {
  const days = Math.round((new Date(value).getTime() - Date.now()) / 86_400_000)
  if (days === 0) return 'Today'
  if (days === 1) return 'Tomorrow'
  if (days > 1 && days < 7) return `In ${days} days`
  if (days === -1) return 'Yesterday'
  return formatDate(value, { month: 'short', day: 'numeric' })
}
