import fc from "fast-check";
import { describe, expect, it, vi } from "vitest";
import { handleContact } from "./handle";
import type { RateLimiter } from "./rate-limit";
import type { MailSender } from "./sender";

describe("handleContact invariants", () => {
  it("never sends when the honeypot holds any non-empty string", async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.string({ minLength: 1 }),
        fc.string(),
        fc.string(),
        fc.string(),
        async (company, name, email, message) => {
          const send = vi.fn<MailSender["send"]>(() => Promise.resolve());
          const take = vi.fn<RateLimiter["take"]>(() => true);
          const data = new FormData();
          data.set("name", name);
          data.set("email", email);
          data.set("message", message);
          data.set("company", company);

          const result = await handleContact(data, {
            ip: "203.0.113.9",
            config: {
              apiKey: "re_test_key",
              to: "rachel@example.com",
              from: "Rachel Siegel website <website@example.com>",
            },
            sender: { send },
            limiter: { take },
            log: vi.fn(),
          });

          expect({
            result,
            sent: send.mock.calls.length,
            taken: take.mock.calls.length,
          }).toEqual({
            result: { ok: true },
            sent: 0,
            taken: 0,
          });
        },
      ),
      { numRuns: 100 },
    );
  });
});
