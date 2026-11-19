import { describe, expect, it } from "vitest";
import { clientIp, createRateLimiter } from "./rate-limit";

const IP = "203.0.113.9";
const OTHER_IP = "198.51.100.7";

function limiterAt(): { take(key: string, at: number): boolean } {
  let now = 0;
  const limiter = createRateLimiter(() => now);
  return {
    take(key, at) {
      now = at;
      return limiter.take(key);
    },
  };
}

function takes(
  limiter: { take(key: string, at: number): boolean },
  key: string,
  at: number,
  count: number,
): boolean[] {
  return Array.from({ length: count }, () => limiter.take(key, at));
}

describe("createRateLimiter", () => {
  it("allows five takes for a key and refuses the sixth until ten minutes have passed", () => {
    const limiter = limiterAt();

    expect(takes(limiter, IP, 0, 5)).toEqual([true, true, true, true, true]);
    expect(limiter.take(IP, 0)).toBe(false);
    expect(limiter.take(IP, 599_999)).toBe(false);
    expect(limiter.take(IP, 600_000)).toBe(true);
  });

  it("frees each take ten minutes after it was made", () => {
    const limiter = limiterAt();
    const early = [0, 60_000, 120_000, 180_000, 240_000].map((at) =>
      limiter.take(IP, at),
    );

    expect(early).toEqual([true, true, true, true, true]);
    expect(limiter.take(IP, 599_999)).toBe(false);
    expect(limiter.take(IP, 600_000)).toBe(true);
    expect(limiter.take(IP, 600_001)).toBe(false);
    expect(limiter.take(IP, 660_000)).toBe(true);
  });

  it("counts each key on its own", () => {
    const limiter = limiterAt();

    expect(takes(limiter, IP, 0, 5)).toEqual([true, true, true, true, true]);
    expect(limiter.take(IP, 0)).toBe(false);
    expect(limiter.take(OTHER_IP, 0)).toBe(true);
    expect(limiter.take(IP, 0)).toBe(false);
  });

  it("does not count a refused take", () => {
    const limiter = limiterAt();

    expect(takes(limiter, IP, 0, 5)).toEqual([true, true, true, true, true]);
    expect(takes(limiter, IP, 300_000, 5)).toEqual([
      false,
      false,
      false,
      false,
      false,
    ]);
    expect(takes(limiter, IP, 600_000, 5)).toEqual([
      true,
      true,
      true,
      true,
      true,
    ]);
    expect(limiter.take(IP, 600_000)).toBe(false);
  });
});

describe("clientIp", () => {
  it("takes the first forwarded address, then x-real-ip, then unknown", () => {
    const cases: [Record<string, string>, string][] = [
      [{ "x-forwarded-for": "203.0.113.9, 10.0.0.2" }, "203.0.113.9"],
      [{ "x-forwarded-for": " 203.0.113.9 , 10.0.0.2 " }, "203.0.113.9"],
      [
        { "x-forwarded-for": "203.0.113.9", "x-real-ip": "198.51.100.7" },
        "203.0.113.9",
      ],
      [{ "x-real-ip": " 198.51.100.7 " }, "198.51.100.7"],
      [{ "x-forwarded-for": "", "x-real-ip": "198.51.100.7" }, "198.51.100.7"],
      [
        { "x-forwarded-for": " , 10.0.0.2", "x-real-ip": "198.51.100.7" },
        "198.51.100.7",
      ],
      [{}, "unknown"],
      [{ "x-real-ip": "" }, "unknown"],
    ];

    const results = cases.map(([headers]) => clientIp(new Headers(headers)));

    expect(results).toEqual(cases.map(([, ip]) => ip));
  });
});
