import { blockSchema, type Block } from "./schema";
import { isWeatherDate, weatherDateInRequest, type WeatherPayload } from "./weather";

export function withVerifiedWeather(
  blocks: Block[],
  payloads: readonly WeatherPayload[],
  request?: string,
): Block[] {
  if (payloads.length === 0) return blocks;
  const date = weatherDateInRequest(request ?? "");
  const focused = payloads.length === 1 ? payloads[0] : undefined;
  const dateFirst =
    date &&
    isWeatherDate(date) &&
    focused?.focus === "daily" &&
    focused.focusDay === date &&
    focused.forecast.filter((day) => day.date === date).length === 1;
  const content = dateFirst
    ? blocks.filter((block) => !(block.type === "text" && block.style === "intro"))
    : blocks;
  const ids = new Set(content.map((block) => block.id));
  const weather = payloads.map((payload, index) => {
    let id = `weather-${index + 1}`;
    while (ids.has(id)) id += "-verified";
    ids.add(id);
    return blockSchema.parse({ ...payload, type: "weather", id });
  });
  const intro = content.findIndex((block) => block.type === "text" && block.style === "intro");
  const meta = content.findIndex((block) => block.type === "pageMeta");
  const position = (intro >= 0 ? intro : meta) + 1;
  return [...content.slice(0, position), ...weather, ...content.slice(position)];
}
