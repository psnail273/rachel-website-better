import { afterEach, describe, expect, it, vi } from "vitest";
import { sendMessage } from "./actions";

const headersMock = vi.hoisted(() => vi.fn<() => Promise<Headers>>());

vi.mock("next/headers", () => ({ headers: headersMock }));

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("sendMessage with a padded key", () => {
  it("sends the trimmed key from the parsed config", async () => {
    vi.stubEnv("RESEND_API_KEY", " re_test_key ");
    vi.stubEnv("CONTACT_TO_EMAIL", "rachel@example.com");
    vi.stubEnv(
      "CONTACT_FROM_EMAIL",
      "Rachel Siegel website <website@example.com>",
    );
    vi.stubEnv("RESEND_BASE_URL", undefined);
    headersMock.mockResolvedValue(
      new Headers({ "x-forwarded-for": "192.0.2.77" }),
    );
    const fake = vi.fn<typeof fetch>(() =>
      Promise.resolve(
        new Response('{"id":"em_1"}', {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      ),
    );
    vi.stubGlobal("fetch", fake);
    const data = new FormData();
    data.set("name", "Ada Lovelace");
    data.set("email", "ada@example.com");
    data.set("message", "Hello Rachel");
    data.set("company", "");

    const result = await sendMessage(data);

    expect(result).toStrictEqual({ ok: true });
    expect(fake).toHaveBeenCalledTimes(1);
    const [, init] = fake.mock.calls[0] ?? [];
    expect(new Headers(init?.headers).get("authorization")).toBe(
      "Bearer re_test_key",
    );
  });
});
