type Container = { kind: "object"; keys: Set<string>; expectingKey: boolean } | { kind: "array" };

export function hasDuplicateJSONKeys(text: string): boolean {
  const stack: Container[] = [];
  let stringStart: number | undefined;
  let escaped = false;
  for (let index = 0; index < text.length; index++) {
    const c = text[index]!;
    if (stringStart !== undefined) {
      if (escaped) escaped = false;
      else if (c === "\\") escaped = true;
      else if (c === '"') {
        const container = stack.at(-1);
        if (container?.kind === "object" && container.expectingKey) {
          let key: string;
          try {
            key = JSON.parse(text.slice(stringStart, index + 1));
          } catch {
            return false;
          }
          if (container.keys.has(key)) return true;
          container.keys.add(key);
          container.expectingKey = false;
        }
        stringStart = undefined;
      }
      continue;
    }
    if (c === '"') stringStart = index;
    else if (c === "{") stack.push({ kind: "object", keys: new Set(), expectingKey: true });
    else if (c === "[") stack.push({ kind: "array" });
    else if (c === "}" || c === "]") stack.pop();
    else if (c === ",") {
      const container = stack.at(-1);
      if (container?.kind === "object") container.expectingKey = true;
    }
  }
  return false;
}

export function wellFormedStrings(value: unknown): boolean {
  if (typeof value === "string") return !/\p{Surrogate}/u.test(value);
  if (Array.isArray(value)) return value.every(wellFormedStrings);
  if (value && typeof value === "object") {
    return Object.entries(value).every(
      ([key, child]) => wellFormedStrings(key) && wellFormedStrings(child),
    );
  }
  return true;
}
