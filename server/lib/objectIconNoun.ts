export function objectIconNoun(query: string): string | null {
  if (/[/@:.#?&=]/.test(query)) return null;
  const noun = query
    .normalize("NFKC")
    .toLocaleLowerCase("en-US")
    .replace(/[^a-z0-9 ]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (noun.length < 2 || noun.length > 40) return null;
  const words = noun.split(" ");
  if (words.length > 4) return null;
  if (words.some((word) => /^\d+$/.test(word))) return null;
  return noun;
}
