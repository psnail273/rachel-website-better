export type RateLimiter = { take(key: string): boolean };

export const createRateLimiter: (now: () => number) => RateLimiter = () => ({
  take: () => false,
});

export const clientIp: (headers: {
  get(name: string): string | null;
}) => string = () => "";
