const MEMBER_LOGIN_DOMAIN = "members.circles.elgchurch.com";

export function memberIdToEmail(identifier: string) {
  return `${identifier.toLowerCase().trim()}@${MEMBER_LOGIN_DOMAIN}`;
}
