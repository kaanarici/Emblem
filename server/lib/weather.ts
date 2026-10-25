const DAY_NAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
const WEATHER_CACHE_TTL_MS = 10 * 60_000;

export type WeatherTiming = (stage: string, durationMs: number) => void;

type WeatherCondition =
  | "clear"
  | "partly-cloudy"
  | "cloudy"
  | "fog"
  | "drizzle"
  | "rain"
  | "snow"
  | "thunderstorm"
  | "wind";

export type WeatherPayload = {
  location: string;
  focus?: "overview" | "daily";
  focusDay?: string;
  current: {
    observedAt: string;
    tempC: number;
    feels: number;
    condition: WeatherCondition;
    high: number;
    low: number;
    humid: number;
    windKph: number;
    precipitationMm: number;
    precipPct: number;
    isDay: boolean;
  };
  hourly: {
    time: string;
    tempC: number;
    feels: number;
    condition: WeatherCondition;
    precipPct: number;
    windKph: number;
    humid: number;
    isDay: boolean;
  }[];
  forecast: {
    date: string;
    day: string;
    condition: WeatherCondition;
    high: number;
    low: number;
    precipPct: number;
    windKph: number;
    uvIndex: number;
    sunrise: string;
    sunset: string;
  }[];
};

type WeatherResult = WeatherPayload | { error: string };
type CacheEntry = { expiresAt: number; value: WeatherPayload };

const weatherCache = new Map<string, CacheEntry>();
const weatherLocations = new WeakMap<WeatherPayload, string>();

export function weatherLocationKey(weather: WeatherPayload): string | undefined {
  return weatherLocations.get(weather);
}
const placeAliases = new Map<string, string>();
const inFlight = new Map<string, Promise<WeatherResult>>();

function wmoToCondition(code: number): WeatherCondition {
  if (code === 0) return "clear";
  if (code === 1 || code === 2) return "partly-cloudy";
  if (code === 3) return "cloudy";
  if (code === 45 || code === 48) return "fog";
  if (code >= 51 && code <= 57) return "drizzle";
  if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return "rain";
  if ((code >= 71 && code <= 77) || code === 85 || code === 86) return "snow";
  if (code >= 95) return "thunderstorm";
  return "cloudy";
}

function coordinateKey(latitude: number, longitude: number): string {
  return `coordinates:${latitude.toFixed(3)},${longitude.toFixed(3)}`;
}

function placeKey(place: string): string {
  return `place:${place.trim().toLocaleLowerCase()}`;
}

function cached(key: string, onTiming?: WeatherTiming): WeatherPayload | undefined {
  const canonicalKey = placeAliases.get(key) ?? key;
  const entry = weatherCache.get(canonicalKey);
  if (!entry || entry.expiresAt <= Date.now()) return undefined;
  onTiming?.("weather.cache", 0);
  return entry.value;
}

function requestSignal(parent?: AbortSignal): AbortSignal {
  const timeout = AbortSignal.timeout(8000);
  return parent ? AbortSignal.any([parent, timeout]) : timeout;
}

export async function getWeather(
  place: string,
  abortSignal?: AbortSignal,
  onTiming?: WeatherTiming,
  options: { date?: string } = {},
): Promise<WeatherResult> {
  if (options.date !== undefined && !isWeatherDate(options.date))
    return { error: "Invalid forecast date" };
  const requestKey = placeKey(place);
  const hit = cached(requestKey, onTiming);
  if (hit) return projectWeatherDate(hit, options.date);

  const pending = inFlight.get(requestKey);
  if (pending) {
    onTiming?.("weather.cache", 0);
    return projectWeatherDate(await pending, options.date);
  }

  const request = loadWeather(place, abortSignal, onTiming, requestKey);
  inFlight.set(requestKey, request);
  try {
    return projectWeatherDate(await request, options.date);
  } finally {
    if (inFlight.get(requestKey) === request) inFlight.delete(requestKey);
  }
}

async function loadWeather(
  place: string,
  abortSignal: AbortSignal | undefined,
  onTiming: WeatherTiming | undefined,
  requestKey: string,
): Promise<WeatherResult> {
  const geocodeStarted = performance.now();
  const geo = await fetch(
    `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(place)}&count=1`,
    { signal: requestSignal(abortSignal) },
  );
  onTiming?.("weather.geocode", performance.now() - geocodeStarted);
  if (!geo.ok) return { error: `geocoding failed for "${place}"` };
  const geoData = (await geo.json()) as {
    results?: {
      latitude: number;
      longitude: number;
      name: string;
      admin1?: string;
      country?: string;
    }[];
  };
  const loc = geoData.results?.[0];
  if (!loc) return { error: `no location found for "${place}"` };

  const canonicalKey = coordinateKey(loc.latitude, loc.longitude);
  placeAliases.set(requestKey, canonicalKey);
  const canonicalHit = cached(canonicalKey, onTiming);
  if (canonicalHit) return canonicalHit;

  const forecastStarted = performance.now();
  const fc = await fetch(
    `https://api.open-meteo.com/v1/forecast?latitude=${loc.latitude}&longitude=${loc.longitude}` +
      `&current=temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,wind_speed_10m,is_day` +
      `&hourly=temperature_2m,apparent_temperature,relative_humidity_2m,precipitation_probability,weather_code,wind_speed_10m,is_day` +
      `&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max,uv_index_max,sunrise,sunset` +
      `&timezone=auto&forecast_days=7` +
      `&temperature_unit=celsius&wind_speed_unit=kmh&precipitation_unit=mm`,
    { signal: requestSignal(abortSignal) },
  );
  onTiming?.("weather.forecast", performance.now() - forecastStarted);
  if (!fc.ok) return { error: "forecast fetch failed" };
  const data = (await fc.json()) as {
    current: {
      time: string;
      temperature_2m: number;
      apparent_temperature: number;
      relative_humidity_2m: number;
      precipitation: number;
      weather_code: number;
      wind_speed_10m: number;
      is_day: number;
    };
    hourly: {
      time: string[];
      temperature_2m: number[];
      apparent_temperature: number[];
      relative_humidity_2m: number[];
      precipitation_probability: number[];
      weather_code: number[];
      wind_speed_10m: number[];
      is_day: number[];
    };
    daily: {
      time: string[];
      weather_code: number[];
      temperature_2m_max: number[];
      temperature_2m_min: number[];
      precipitation_probability_max: number[];
      wind_speed_10m_max: number[];
      uv_index_max: number[];
      sunrise: string[];
      sunset: string[];
    };
  };

  const completeSeries = (series: Record<string, unknown> | undefined, fields: string[]) => {
    if (
      !series ||
      !Array.isArray(series.time) ||
      series.time.length === 0 ||
      !series.time.every((value) => typeof value === "string")
    )
      return false;
    const length = series.time.length;
    return fields.every(
      (field) =>
        Array.isArray(series[field]) &&
        series[field].length === length &&
        (series[field] as unknown[]).every(Number.isFinite),
    );
  };
  if (
    !data.current ||
    ![
      data.current.temperature_2m,
      data.current.apparent_temperature,
      data.current.relative_humidity_2m,
      data.current.precipitation,
      data.current.weather_code,
      data.current.wind_speed_10m,
      data.current.is_day,
    ].every(Number.isFinite) ||
    typeof data.current.time !== "string" ||
    !completeSeries(data.hourly, [
      "temperature_2m",
      "apparent_temperature",
      "relative_humidity_2m",
      "precipitation_probability",
      "weather_code",
      "wind_speed_10m",
      "is_day",
    ]) ||
    !completeSeries(data.daily, [
      "weather_code",
      "temperature_2m_max",
      "temperature_2m_min",
      "precipitation_probability_max",
      "wind_speed_10m_max",
      "uv_index_max",
    ]) ||
    !Array.isArray(data.daily.sunrise) ||
    !Array.isArray(data.daily.sunset) ||
    data.daily.sunrise.length !== data.daily.time.length ||
    data.daily.sunset.length !== data.daily.time.length
  ) {
    return { error: "Forecast data incomplete" };
  }

  const label = loc.name;
  const forecast = data.daily.time.map((iso, index) => ({
    date: iso,
    day: index === 0 ? "Today" : DAY_NAMES[new Date(`${iso}T12:00:00Z`).getUTCDay()],
    condition: wmoToCondition(data.daily.weather_code[index]),
    high: Math.round(data.daily.temperature_2m_max[index]),
    low: Math.round(data.daily.temperature_2m_min[index]),
    precipPct: Math.round(data.daily.precipitation_probability_max[index] ?? 0),
    windKph: Math.round(data.daily.wind_speed_10m_max[index] ?? 0),
    uvIndex: Math.round(data.daily.uv_index_max[index] ?? 0),
    sunrise: data.daily.sunrise[index],
    sunset: data.daily.sunset[index],
  }));
  const today = forecast[0];
  if (!today) return { error: "forecast data incomplete" };
  const currentHour = Math.max(
    0,
    data.hourly.time.findLastIndex((time) => time <= data.current.time),
  );
  const hourly = data.hourly.time.map((time, index) => {
    return {
      time,
      tempC: Math.round(data.hourly.temperature_2m[index]),
      feels: Math.round(data.hourly.apparent_temperature[index]),
      condition: wmoToCondition(data.hourly.weather_code[index]),
      precipPct: Math.round(data.hourly.precipitation_probability[index] ?? 0),
      windKph: Math.round(data.hourly.wind_speed_10m[index] ?? 0),
      humid: Math.round(data.hourly.relative_humidity_2m[index] ?? 0),
      isDay: data.hourly.is_day[index] === 1,
    };
  });
  const value: WeatherPayload = {
    location: label,
    current: {
      observedAt: data.current.time,
      tempC: Math.round(data.current.temperature_2m),
      feels: Math.round(data.current.apparent_temperature),
      condition: wmoToCondition(data.current.weather_code),
      high: today.high,
      low: today.low,
      humid: Math.round(data.current.relative_humidity_2m),
      windKph: Math.round(data.current.wind_speed_10m),
      precipitationMm: data.current.precipitation,
      precipPct: hourly[currentHour]?.precipPct ?? 0,
      isDay: data.current.is_day === 1,
    },
    hourly,
    forecast,
  };
  weatherLocations.set(value, canonicalKey);
  weatherCache.set(canonicalKey, {
    expiresAt: Date.now() + WEATHER_CACHE_TTL_MS,
    value,
  });
  return value;
}

export function isWeatherDate(date: string): boolean {
  return (
    /^\d{4}-\d{2}-\d{2}$/.test(date) &&
    Number.isFinite(Date.parse(`${date}T00:00:00Z`)) &&
    new Date(`${date}T00:00:00Z`).toISOString().slice(0, 10) === date
  );
}

export function weatherDateInRequest(request: string): string | undefined {
  const match =
    /^Show the weather for [^\r\n]+ on (\d{4}-\d{2}-\d{2})\. Focus on this date with its hourly forecast and the upcoming daily forecast\.(?: Include precipitation probabilities and amounts\.| Include wind, UV, sunrise and sunset for outdoor plans\.)?$/.exec(
      request.trim(),
    );
  return match?.[1];
}

function projectWeatherDate(result: WeatherResult, date?: string): WeatherResult {
  if ("error" in result) return result;
  let projected: WeatherPayload;
  if (date) {
    if (!result.forecast.some((day) => day.date === date))
      return { error: "Requested date is outside the available seven-day forecast" };
    const hourly = result.hourly.filter(
      (hour) => hour.time.startsWith(`${date}T`) && Number(hour.time.slice(11, 13)) % 3 === 0,
    );
    if (hourly.length !== 8)
      return { error: "Complete hourly forecast unavailable for requested date" };
    projected = { ...result, focus: "daily", focusDay: date, hourly };
  } else {
    const index = Math.max(
      0,
      result.hourly.findLastIndex((hour) => hour.time <= result.current.observedAt),
    );
    projected = { ...result, focus: "overview", hourly: result.hourly.slice(index, index + 24) };
  }
  const key = weatherLocationKey(result);
  if (key) weatherLocations.set(projected, key);
  return projected;
}
