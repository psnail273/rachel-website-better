import { afterEach, describe, expect, it, vi, type MockInstance } from "vitest";
import { sendMessage } from "./actions";

const headersMock = vi.hoisted(() => vi.fn<() => Promise<Headers>>());

vi.mock("next/headers", () => ({ headers: headersMock }));

const REFUSAL =
  '{"statusCode":422,"name":"validation_error","message":"Invalid `from` field."}';

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

function configure(): void {
  vi.stubEnv("RESEND_API_KEY", "re_test_key");
  vi.stubEnv("CONTACT_TO_EMAIL", "rachel@example.com");
  vi.stubEnv(
    "CONTACT_FROM_EMAIL",
    "Rachel Siegel website <website@example.com>",
  );
  vi.stubEnv("RESEND_BASE_URL", undefined);
}

function unconfigure(): void {
  vi.stubEnv("RESEND_API_KEY", "");
  vi.stubEnv("CONTACT_TO_EMAIL", "");
  vi.stubEnv("CONTACT_FROM_EMAIL", "");
}

function forwardedFor(address: string): void {
  headersMock.mockResolvedValue(new Headers({ "x-forwarded-for": address }));
}

function stubFetch(
  answer: () => Response,
): ReturnType<typeof vi.fn<typeof fetch>> {
  const fake = vi.fn<typeof fetch>(() => Promise.resolve(answer()));
  vi.stubGlobal("fetch", fake);
  return fake;
}

function silenceErrors(): MockInstance<typeof console.error> {
  return vi.spyOn(console, "error").mockImplementation(() => undefined);
}

function valid(): FormData {
  const data = new FormData();
  data.set("name", "Ada Lovelace");
  data.set("email", "ada@example.com");
  data.set("message", "Hello Rachel");
  data.set("company", "");
  return data;
}

function urlOf(input: string | URL | Request | undefined): string {
  if (input === undefined) return "";
  if (typeof input === "string") return input;
  return input instanceof URL ? input.href : input.url;
}

describe("sendMessage", () => {
  it("sends through Resend with the configured key and addresses", async () => {
    configure();
    forwardedFor("192.0.2.2");
    const errors = silenceErrors();
    const fake = stubFetch(
      () =>
        new Response('{"id":"em_1"}', {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
    );
    const actions = await import("./actions");

    const result = await sendMessage(valid());

    expect(result).toStrictEqual({ ok: true });
    expect(fake).toHaveBeenCalledTimes(1);
    const [input, init] = fake.mock.calls[0] ?? [];
    expect(urlOf(input)).toBe("https://api.resend.com/emails");
    expect(init?.method).toBe("POST");
    expect(new Headers(init?.headers).get("authorization")).toBe(
      "Bearer re_test_key",
    );
    const body = init?.body;
    expect(typeof body).toBe("string");
    const sent: unknown = JSON.parse(typeof body === "string" ? body : "null");
    expect(sent).toEqual({
      from: "Rachel Siegel website <website@example.com>",
      to: "rachel@example.com",
      reply_to: "ada@example.com",
      subject: "Website message from Ada Lovelace",
      text: "Name: Ada Lovelace\nEmail: ada@example.com\n\nHello Rachel",
    });
    expect(errors).not.toHaveBeenCalled();
    expect(Object.keys(actions).sort()).toEqual(["sendMessage"]);
  });

  it("fails and logs when the site is not configured", async () => {
    unconfigure();
    forwardedFor("192.0.2.1");
    const errors = silenceErrors();
    const fake = stubFetch(() => new Response("{}", { status: 200 }));

    const result = await sendMessage(valid());

    expect(result).toStrictEqual({ ok: false, reason: "failed" });
    expect(errors.mock.calls).toEqual([["Contact form: not configured."]]);
    expect(fake).not.toHaveBeenCalled();
  });

  it("fails and logs Resend's message when Resend refuses the mail", async () => {
    configure();
    forwardedFor("192.0.2.5");
    const errors = silenceErrors();
    stubFetch(
      () =>
        new Response(REFUSAL, {
          status: 422,
          headers: { "content-type": "application/json" },
        }),
    );

    const result = await sendMessage(valid());

    expect(result).toStrictEqual({ ok: false, reason: "failed" });
    expect(errors.mock.calls).toEqual([
      ["Contact form: the send failed: Invalid `from` field."],
    ]);
  });

  it("refuses the sixth submission from one forwarded address and counts other addresses apart", async () => {
    unconfigure();
    const errors = silenceErrors();
    const fake = stubFetch(() => new Response("{}", { status: 200 }));
    forwardedFor("192.0.2.3, 10.0.0.2");

    const firstFive = [];
    for (let count = 0; count < 5; count += 1) {
      firstFive.push(await sendMessage(valid()));
    }
    const sixth = await sendMessage(valid());
    forwardedFor("192.0.2.4");
    const other = await sendMessage(valid());

    expect(firstFive).toEqual([
      { ok: false, reason: "failed" },
      { ok: false, reason: "failed" },
      { ok: false, reason: "failed" },
      { ok: false, reason: "failed" },
      { ok: false, reason: "failed" },
    ]);
    expect(sixth).toStrictEqual({ ok: false, reason: "rate-limited" });
    expect(other).toStrictEqual({ ok: false, reason: "failed" });
    expect(errors.mock.calls).toEqual([
      ["Contact form: not configured."],
      ["Contact form: not configured."],
      ["Contact form: not configured."],
      ["Contact form: not configured."],
      ["Contact form: not configured."],
      ["Contact form: not configured."],
    ]);
    expect(fake).not.toHaveBeenCalled();
  });
});
