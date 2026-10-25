export type LatencyStages = Record<string, number>;

type Percentiles = { p50: number; p90: number; p95: number };
type LatencyStore = Record<string, Record<string, number[]>>;

const globalLatency = globalThis as typeof globalThis & {
  __emblemLatency?: LatencyStore;
};

const store = (globalLatency.__emblemLatency ??= {});
const WINDOW_SIZE = 200;

function percentile(values: number[], fraction: number): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.max(0, Math.ceil(sorted.length * fraction) - 1)];
}

function rounded(value: number): number {
  return Math.round(value * 10) / 10;
}

export function recordGenerationLatency(route: string, stages: LatencyStages) {
  const routeStore = (store[route] ??= {});
  const percentiles: Record<string, Percentiles> = {};

  for (const [stage, duration] of Object.entries(stages)) {
    if (!Number.isFinite(duration) || duration < 0) continue;
    const samples = (routeStore[stage] ??= []);
    samples.push(duration);
    if (samples.length > WINDOW_SIZE) samples.splice(0, samples.length - WINDOW_SIZE);
    percentiles[stage] = {
      p50: rounded(percentile(samples, 0.5)),
      p90: rounded(percentile(samples, 0.9)),
      p95: rounded(percentile(samples, 0.95)),
    };
  }

  const event = {
    type: "metric" as const,
    id: "generation-timing" as const,
    route,
    stages: Object.fromEntries(
      Object.entries(stages).map(([stage, duration]) => [stage, rounded(duration)]),
    ),
    percentiles,
    sampleSize: routeStore.total?.length ?? 0,
  };
  console.info(`generation_timing ${JSON.stringify(event)}`);
  return event;
}
