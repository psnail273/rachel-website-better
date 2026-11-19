import { describe, expect, it } from "vitest";
import { clientIp } from "./rate-limit";

function fake(values: Record<string, string>): {
  get(name: string): string | null;
} {
  return { get: (name) => values[name] ?? null };
}

describe("clientIp", () => {
  it("trims the spaces around the forwarded address and around x-real-ip", () => {
    expect(
      clientIp(fake({ "x-forwarded-for": "  203.0.113.9  , 10.0.0.2" })),
    ).toBe("203.0.113.9");
    expect(clientIp(fake({ "x-real-ip": "  198.51.100.7  " }))).toBe(
      "198.51.100.7",
    );
    expect(clientIp(fake({ "x-real-ip": "   " }))).toBe("unknown");
    expect(
      clientIp(fake({ "x-forwarded-for": "   ", "x-real-ip": "198.51.100.7" })),
    ).toBe("198.51.100.7");
  });
});
