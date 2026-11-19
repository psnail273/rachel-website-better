export type RateLimiter = { take(key: string): boolean };

const LIMIT = 5;
const WINDOW_MS = 600_000;

export function createRateLimiter(now: () => number): RateLimiter {
  const takes = new Map<string, number[]>();
  return {
    take(key) {
      const time = now();
      const recent = (takes.get(key) ?? []).filter(
        (earlier) => time - earlier < WINDOW_MS,
      );
      if (recent.length >= LIMIT) return false;
      takes.set(key, [...recent, time]);
      return true;
    },
  };
}

export function clientIp(headers: {
  get(name: string): string | null;
}): string {
  const [firstHop = ""] = (headers.get("x-forwarded-for") ?? "").split(",");
  const forwarded = firstHop.trim();
  if (forwarded !== "") return forwarded;
  const real = (headers.get("x-real-ip") ?? "").trim();
  return real === "" ? "unknown" : real;
}
