import { describe, expect, it, vi } from "vitest";
import * as homeRoute from "../app/api/home/route";

vi.mock("@/lib/auth", () => ({
  requestAuth: async () => ({
    convex: null,
    authenticated: false,
    ownerKey: null,
    status: "guest",
  }),
  authFailure: () => null,
}));

describe("home", () => {
  it("takes the person's name and next event from the body, never the URL", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(Date.UTC(2026, 9, 25, 14, 0, 0));
    expect("GET" in homeRoute).toBe(false);
    const response = await homeRoute.POST(
      new Request("https://emblem.test/api/home", {
        method: "POST",
        body: JSON.stringify({
          name: "Sam",
          timezone: "America/New_York",
          nextEventTitle: "Dinner with Alex",
          nextEventStart: Date.UTC(2026, 9, 25, 22, 0, 0) / 1000,
        }),
      }),
    );
    const [snapshot] = (await response.text())
      .trim()
      .split("\n")
      .map((line) => JSON.parse(line));
    expect(snapshot.blocks[1].body).toBe(
      "Good morning, **Sam**.\nYour 📅 **Dinner with Alex** is tonight at **6:00 PM**.",
    );
  });

  it("rejects a body that is not the home request", async () => {
    const response = await homeRoute.POST(
      new Request("https://emblem.test/api/home", { method: "POST", body: '{"name":7}' }),
    );
    expect(response.status).toBe(400);
  });
});
