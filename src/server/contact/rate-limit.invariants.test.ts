import fc from "fast-check";
import { describe, expect, it } from "vitest";
import { clientIp, createRateLimiter } from "./rate-limit";

const WINDOW = 600_000;

const header = fc.option(fc.string(), { nil: null });

describe("clientIp invariants", () => {
  it("never returns an empty string", () => {
    fc.assert(
      fc.property(header, header, (forwarded, real) => {
        const headers = {
          get: (name: string): string | null =>
            name === "x-forwarded-for"
              ? forwarded
              : name === "x-real-ip"
                ? real
                : null,
        };

        expect(clientIp(headers)).not.toBe("");
      }),
      { numRuns: 200 },
    );
  });
});

describe("createRateLimiter invariants", () => {
  it("never allows more than five takes for one key within any half-open window [t, t + 600,000) of non-decreasing take times", () => {
    fc.assert(
      fc.property(
        fc.array(fc.integer({ min: 0, max: 300_000 }), {
          minLength: 1,
          maxLength: 40,
        }),
        (steps) => {
          const times = steps.reduce<number[]>(
            (all, step) => [...all, (all.at(-1) ?? 0) + step],
            [],
          );
          let now = 0;
          const limiter = createRateLimiter(() => now);
          const allowed: number[] = [];
          for (const time of times) {
            now = time;
            if (limiter.take("203.0.113.9")) allowed.push(time);
          }
          const crowded = allowed.filter(
            (start) =>
              allowed.filter((t) => t >= start && t < start + WINDOW).length >
              5,
          );

          expect(crowded).toEqual([]);
        },
      ),
      { numRuns: 200 },
    );
  });
});
