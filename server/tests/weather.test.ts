import { afterEach, describe, expect, it, vi } from "vitest";
import { getWeather } from "../lib/weather";
import { withVerifiedWeather } from "../lib/weatherComposition";
import type { Block } from "../lib/schema";

const dates = ["2026-10-25", "2026-10-26"];
const hours = dates.flatMap((date) =>
  Array.from({ length: 24 }, (_, hour) => `${date}T${String(hour).padStart(2, "0")}:00`),
);

function stubOpenMeteo(latitude: number) {
  vi.stubGlobal(
    "fetch",
    vi.fn(async (url: string) => {
      if (url.includes("geocoding-api"))
        return Response.json({ results: [{ name: "Testville", latitude, longitude: 1 }] });
      return Response.json({
        current: {
          time: "2026-10-25T14:15",
          temperature_2m: 18.4,
          apparent_temperature: 17.6,
          relative_humidity_2m: 60,
          precipitation: 0,
          weather_code: 2,
          wind_speed_10m: 12,
          is_day: 1,
        },
        hourly: {
          time: hours,
          temperature_2m: hours.map((_, index) => 10 + (index % 24) / 2),
          precipitation_probability: hours.map((_, index) => index),
          weather_code: hours.map((_, index) => (index < 24 ? 0 : 61)),
          is_day: hours.map((time) => (Number(time.slice(11, 13)) >= 7 ? 1 : 0)),
        },
        daily: {
          time: dates,
          weather_code: [0, 61],
          temperature_2m_max: [21.2, 15.6],
          temperature_2m_min: [10.1, 9.4],
          precipitation_probability_max: [10, 80],
          wind_speed_10m_max: [14, 25],
          uv_index_max: [5, 2],
          sunrise: dates.map((date) => `${date}T07:28`),
          sunset: dates.map((date) => `${date}T18:16`),
        },
      });
    }),
  );
}

afterEach(() => vi.unstubAllGlobals());

describe("weather", () => {
  it("gives every day of the week its own hours and places one native block after the lead", async () => {
    stubOpenMeteo(10);
    const weather = await getWeather("Testville");
    if ("error" in weather) throw new Error(weather.error);

    expect(weather.current.precipPct).toBe(14);
    expect(weather.forecast.map((day) => [day.day, day.hours.length])).toEqual([
      ["Today", 24],
      ["Monday", 24],
    ]);
    expect(weather.forecast[1].hours[9]).toEqual([9, 15, "rain", 33, true]);

    const page: Block[] = [
      { type: "pageMeta", id: "meta", title: "Weather" },
      { type: "text", id: "intro", style: "intro", body: "Rain arrives Monday." },
    ];
    expect(withVerifiedWeather(page, [weather]).map((block) => block.type)).toEqual([
      "pageMeta",
      "text",
      "weather",
    ]);
  });

  it("opens a requested date in place and refuses dates outside the forecast", async () => {
    stubOpenMeteo(20);
    const monday = await getWeather("Second Town", undefined, undefined, { date: "2026-10-26" });
    if ("error" in monday) throw new Error(monday.error);
    expect(monday.focusDay).toBe("2026-10-26");
    expect(monday.forecast).toHaveLength(2);

    expect(await getWeather("Second Town", undefined, undefined, { date: "2026-11-02" })).toEqual({
      error: "Requested date is outside the available seven-day forecast",
    });
  });
});
