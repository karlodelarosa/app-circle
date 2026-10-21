export async function copyText(value: string) {
  if (navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(value);
    return;
  }

  const input = document.createElement("textarea");
  input.value = value;
  input.setAttribute("readonly", "");
  input.style.position = "fixed";
  input.style.opacity = "0";
  document.body.appendChild(input);
  input.select();
  const copied =
    typeof document.execCommand === "function" && document.execCommand("copy");
  input.remove();
  if (!copied) throw new Error("This browser could not copy the link.");
}

export async function shareLink(title: string, url: string) {
  if (navigator.share) {
    try {
      await navigator.share({ title, url });
      return "shared" as const;
    } catch (cause) {
      if (cause instanceof DOMException && cause.name === "AbortError")
        return "cancelled" as const;
      throw cause;
    }
  }
  await copyText(url);
  return "copied" as const;
}
