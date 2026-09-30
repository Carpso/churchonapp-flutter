// Lipila only allows letters, numbers and spaces in narrations (and in the
// card customer name/city/country/address fields) — colons, apostrophes,
// ampersands, emoji etc. make the API reject the request with
// "narration can only contain letters, numbers and spaces".
//
// Ported verbatim from chisomo `src/lipila.ts:92 sanitizeNarration`.
export function sanitizeNarration(s: string): string {
  return String(s ?? "")
    .normalize("NFKD")
    .replace(/[^A-Za-z0-9 ]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 50);
}

// Mobile-money account numbers must be digits only (260XXXXXXXXX).
export function sanitizeAccountNumber(s: string): string {
  return String(s ?? "").replace(/[^0-9]/g, "");
}
