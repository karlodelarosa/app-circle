export function validatePassword(password: string) {
  if (password.length < 10) return "Your password must contain at least 10 characters.";
  if (!/[A-Z]/.test(password)) return "Your password must include at least one uppercase letter.";
  if (!/[a-z]/.test(password)) return "Your password must include at least one lowercase letter.";
  if (!/\d/.test(password)) return "Your password must include at least one number.";
  return null;
}
