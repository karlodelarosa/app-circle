const randomFourDigits = () => {
  const [value] = crypto.getRandomValues(new Uint32Array(1));
  return 1000 + (value % 9000);
};

export function memberIdBase(firstName: string) {
  const [firstWord = ""] = firstName.trim().split(/\s+/);
  return firstWord
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]/g, "")
    .slice(0, 20) || "member";
}

export async function findAvailableMemberId(
  firstName: string,
  isAvailable: (candidate: string) => Promise<boolean>,
  nextSuffix: () => number = randomFourDigits,
) {
  const base = memberIdBase(firstName);
  for (let attempt = 0; attempt < 20; attempt++) {
    const suffix = String(nextSuffix()).padStart(4, "0").slice(-4);
    const candidate = `${base}-${suffix}`;
    if (await isAvailable(candidate)) return candidate;
  }
  throw new Error("A unique Member ID could not be generated.");
}
