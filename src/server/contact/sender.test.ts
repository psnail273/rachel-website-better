import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import { createResendSender, type Mail } from "./sender";

const ADA_MAIL: Mail = {
  from: "Rachel Siegel website <website@example.com>",
  to: "rachel@example.com",
  replyTo: "ada@example.com",
  subject: "Website message from Ada Lovelace",
  text: "Name: Ada Lovelace\nEmail: ada@example.com\n\nHello Rachel",
};

const ADA_BODY = {
  from: "Rachel Siegel website <website@example.com>",
  to: "rachel@example.com",
  reply_to: "ada@example.com",
  subject: "Website message from Ada Lovelace",
  text: "Name: Ada Lovelace\nEmail: ada@example.com\n\nHello Rachel",
};

const REFUSAL =
  '{"statusCode":422,"name":"validation_error","message":"Invalid `from` field."}';

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

function accepted(): Response {
  return new Response('{"id":"em_1"}', {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

function stubFetch(
  answer: () => Promise<Response>,
): ReturnType<typeof vi.fn<typeof fetch>> {
  const fake = vi.fn<typeof fetch>(answer);
  vi.stubGlobal("fetch", fake);
  return fake;
}

function urlOf(input: string | URL | Request | undefined): string {
  if (input === undefined) return "";
  if (typeof input === "string") return input;
  return input instanceof URL ? input.href : input.url;
}

function packageDependency(name: string): unknown {
  const parsed: unknown = JSON.parse(
    readFileSync(
      join(import.meta.dirname, "..", "..", "..", "package.json"),
      "utf8",
    ),
  );
  if (typeof parsed !== "object" || parsed === null) return undefined;
  if (!("dependencies" in parsed)) return undefined;
  const dependencies = parsed.dependencies;
  if (typeof dependencies !== "object" || dependencies === null) {
    return undefined;
  }
  return Object.entries(dependencies).find(([key]) => key === name)?.[1];
}

describe("createResendSender", () => {
  it("posts the mail to Resend with the key and resolves when Resend accepts it", async () => {
    vi.stubEnv("RESEND_BASE_URL", undefined);
    const fake = stubFetch(() => Promise.resolve(accepted()));

    await expect(
      createResendSender("re_test_key").send(ADA_MAIL),
    ).resolves.toBeUndefined();
    expect(fake).toHaveBeenCalledTimes(1);
    const [input, init] = fake.mock.calls[0] ?? [];
    expect(urlOf(input)).toBe("https://api.resend.com/emails");
    expect(init?.method).toBe("POST");
    const headers = new Headers(init?.headers);
    expect(headers.get("authorization")).toBe("Bearer re_test_key");
    expect(headers.get("content-type")).toBe("application/json");
    const body = init?.body;
    expect(typeof body).toBe("string");
    const sent: unknown = JSON.parse(typeof body === "string" ? body : "null");
    expect(sent).toEqual(ADA_BODY);
  });

  it("rejects with Resend's own message when Resend refuses the mail or cannot be reached", async () => {
    vi.stubEnv("RESEND_BASE_URL", undefined);
    stubFetch(() =>
      Promise.resolve(
        new Response(REFUSAL, {
          status: 422,
          headers: { "content-type": "application/json" },
        }),
      ),
    );
    const refused = createResendSender("re_test_key").send(ADA_MAIL);

    await expect(refused).rejects.toThrow(new Error("Invalid `from` field."));

    stubFetch(() => Promise.reject(new TypeError("fetch failed")));
    const unreachable = createResendSender("re_test_key").send(ADA_MAIL);

    await expect(unreachable).rejects.toThrow(
      new Error("Unable to fetch data. The request could not be resolved."),
    );
  });

  it("is built on resend at exactly 6.37.0", () => {
    expect(packageDependency("resend")).toBe("6.37.0");
  });
});
