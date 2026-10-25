import { blockSchema, type Block } from "./schema";
import type { WeatherPayload } from "./weather";

export function withVerifiedWeather(blocks: Block[], payloads: readonly WeatherPayload[]): Block[] {
  if (payloads.length === 0) return blocks;
  const ids = new Set(blocks.map((block) => block.id));
  const weather = payloads.map((payload, index) => {
    let id = `weather-${index + 1}`;
    while (ids.has(id)) id += "-verified";
    ids.add(id);
    return blockSchema.parse({ ...payload, type: "weather", id });
  });
  const intro = blocks.findIndex((block) => block.type === "text" && block.style === "intro");
  const meta = blocks.findIndex((block) => block.type === "pageMeta");
  const position = (intro >= 0 ? intro : meta) + 1;
  return [...blocks.slice(0, position), ...weather, ...blocks.slice(position)];
}
