import { describe, expect, it } from "vitest";
import { createExecutionGrant, verifyExecutionGrant } from "../lib/executionGrant";

describe("owner-bound execution grants", () => {
  it("round-trips only with the signing secret", async () => {
    const token = await createExecutionGrant(
      {
        ownerKey: "issuer|alice",
        runId: "run-1",
        leaseGeneration: 1,
        sources: ["gmail", "weather"],
        exp: 2_000,
      },
      "correct",
    );

    expect(await verifyExecutionGrant(token, "correct", 1_000)).toMatchObject({
      ownerKey: "issuer|alice",
      runId: "run-1",
      leaseGeneration: 1,
      sources: ["gmail", "weather"],
    });
    expect(await verifyExecutionGrant(token, "wrong", 1_000)).toBeNull();
  });

  it("rejects expired and overlong grants", async () => {
    const expired = await createExecutionGrant(
      {
        ownerKey: "issuer|alice",
        runId: "run-1",
        leaseGeneration: 1,
        sources: [],
        exp: 999,
      },
      "secret",
    );
    const overlong = await createExecutionGrant(
      {
        ownerKey: "issuer|alice",
        runId: "run-1",
        leaseGeneration: 1,
        sources: [],
        exp: 700_001,
      },
      "secret",
    );

    expect(await verifyExecutionGrant(expired, "secret", 1_000)).toBeNull();
    expect(await verifyExecutionGrant(overlong, "secret", 1_000)).toBeNull();
  });
});
