import { describe, expect, it, vi } from "vitest";
import type { ContactResult } from "../../lib/contact";
import type { ContactConfig } from "./config";
import { handleContact } from "./handle";
import { createRateLimiter, type RateLimiter } from "./rate-limit";
import type { MailSender } from "./sender";

const CONFIG: ContactConfig = {
  apiKey: "re_test_key",
  to: "rachel@example.com",
  from: "Rachel Siegel website <website@example.com>",
};

const IP = "203.0.113.9";
const OTHER_IP = "198.51.100.7";

const EMAIL_EMPTY = "Enter your email address.";
const EMAIL_BAD = "Enter an email address like name@example.com.";
const MESSAGE_EMPTY = "Write a message.";
const MESSAGE_LONG = "Keep your message under 5,000 characters.";

const NOT_CONFIGURED = "Contact form: not configured.";

function setup(
  over: { config?: ContactConfig | null; limiter?: RateLimiter } = {},
): {
  send: ReturnType<typeof vi.fn<MailSender["send"]>>;
  take: ReturnType<typeof vi.fn<RateLimiter["take"]>>;
  log: ReturnType<typeof vi.fn<(line: string) => void>>;
  deps: Parameters<typeof handleContact>[1];
} {
  const send = vi.fn<MailSender["send"]>(() => Promise.resolve());
  const take = vi.fn<RateLimiter["take"]>(() => true);
  const log = vi.fn<(line: string) => void>();
  const deps = {
    ip: IP,
    config: over.config === undefined ? CONFIG : over.config,
    sender: { send },
    limiter: over.limiter ?? { take },
    log,
  };
  return { send, take, log, deps };
}

function form(fields: Record<string, string>): FormData {
  const data = new FormData();
  for (const [name, value] of Object.entries(fields)) data.set(name, value);
  return data;
}

function ada(extra: Record<string, string> = {}): FormData {
  return form({
    name: "Ada Lovelace",
    email: "ada@example.com",
    message: "Hello Rachel",
    company: "",
    ...extra,
  });
}

function adaMail(
  over: { subject?: string; text?: string } = {},
): Record<string, string> {
  return {
    from: CONFIG.from,
    to: CONFIG.to,
    replyTo: "ada@example.com",
    subject: over.subject ?? "Website message from Ada Lovelace",
    text:
      over.text ?? "Name: Ada Lovelace\nEmail: ada@example.com\n\nHello Rachel",
  };
}

describe("handleContact", () => {
  it("sends one mail from and to the configured addresses, replying to the visitor, and reports success", async () => {
    const { send, take, log, deps } = setup();
    const padded = form({
      name: " Ada Lovelace ",
      email: " ada@example.com ",
      message: " Hello Rachel\nSee you ",
      company: "",
    });

    const result = await handleContact(padded, deps);

    expect(result).toStrictEqual({ ok: true });
    expect(send.mock.calls).toEqual([
      [
        adaMail({
          text: "Name: Ada Lovelace\nEmail: ada@example.com\n\nHello Rachel\nSee you",
        }),
      ],
    ]);
    expect(take.mock.calls).toEqual([[IP]]);
    expect(log).not.toHaveBeenCalled();

    const near = setup();
    const noCompany = form({
      name: "Ada Lovelace",
      email: "ada@example.com",
      message: "Hello Rachel",
    });

    const nearResult = await handleContact(noCompany, near.deps);

    expect(nearResult).toStrictEqual({ ok: true });
    expect(near.send.mock.calls).toEqual([[adaMail()]]);
  });

  it("names the visitor by email when no name is given and cuts a long name to 200 characters", async () => {
    const base = { email: "ada@example.com", message: "Hello Rachel" };
    const byEmail = {
      subject: "Website message from ada@example.com",
      text: "Email: ada@example.com\n\nHello Rachel",
    };
    const cases: [Record<string, string>, { subject: string; text: string }][] =
      [
        [base, byEmail],
        [{ ...base, name: "   " }, byEmail],
        [
          { ...base, name: "x".repeat(250) },
          {
            subject: "Website message from " + "x".repeat(200),
            text:
              "Name: " +
              "x".repeat(200) +
              "\nEmail: ada@example.com\n\nHello Rachel",
          },
        ],
        [
          { ...base, name: "y".repeat(200) },
          {
            subject: "Website message from " + "y".repeat(200),
            text:
              "Name: " +
              "y".repeat(200) +
              "\nEmail: ada@example.com\n\nHello Rachel",
          },
        ],
      ];

    const outcomes = [];
    for (const [fields] of cases) {
      const fake = setup();
      const result = await handleContact(form(fields), fake.deps);
      outcomes.push({ result, mails: fake.send.mock.calls });
    }

    expect(outcomes).toEqual(
      cases.map(([, mail]) => ({
        result: { ok: true },
        mails: [[adaMail(mail)]],
      })),
    );
  });

  it("refuses an invalid submission with the form's messages and sends nothing", async () => {
    const blobEmail = form({ message: "Hello Rachel" });
    blobEmail.set("email", new Blob(["ada@example.com"]));
    const cases: [FormData, ContactResult][] = [
      [
        form({ email: "", message: "" }),
        {
          ok: false,
          reason: "invalid",
          errors: { email: EMAIL_EMPTY, message: MESSAGE_EMPTY },
        },
      ],
      [
        new FormData(),
        {
          ok: false,
          reason: "invalid",
          errors: { email: EMAIL_EMPTY, message: MESSAGE_EMPTY },
        },
      ],
      [
        form({ email: "rachel@", message: "Hello Rachel" }),
        { ok: false, reason: "invalid", errors: { email: EMAIL_BAD } },
      ],
      [
        form({ email: "ada@example.com", message: "a".repeat(5001) }),
        { ok: false, reason: "invalid", errors: { message: MESSAGE_LONG } },
      ],
      [
        blobEmail,
        { ok: false, reason: "invalid", errors: { email: EMAIL_EMPTY } },
      ],
    ];

    const outcomes = [];
    for (const [data] of cases) {
      const fake = setup();
      const result = await handleContact(data, fake.deps);
      outcomes.push({
        result,
        sends: fake.send.mock.calls.length,
        takes: fake.take.mock.calls.length,
        logs: fake.log.mock.calls.length,
      });
    }

    expect(outcomes).toEqual(
      cases.map(([, result]) => ({ result, sends: 0, takes: 0, logs: 0 })),
    );
  });

  it("reports success for a filled honeypot without taking the limit or sending", async () => {
    const cases = [
      ada({ company: "Acme" }),
      ada({ company: "  " }),
      ada({ company: "Acme", email: "", message: "" }),
    ];

    const outcomes = [];
    for (const data of cases) {
      const fake = setup();
      const result = await handleContact(data, fake.deps);
      outcomes.push({
        result,
        sends: fake.send.mock.calls.length,
        takes: fake.take.mock.calls.length,
        logs: fake.log.mock.calls.length,
      });
    }

    expect(outcomes).toEqual([
      { result: { ok: true }, sends: 0, takes: 0, logs: 0 },
      { result: { ok: true }, sends: 0, takes: 0, logs: 0 },
      { result: { ok: true }, sends: 0, takes: 0, logs: 0 },
    ]);
  });

  it("refuses the sixth valid submission from one address and counts nothing else", async () => {
    const fake = setup({ limiter: createRateLimiter(() => 0) });
    const invalid = ada({ email: "" });
    const honeypot = ada({ company: "Acme" });
    for (let count = 0; count < 3; count += 1) {
      await handleContact(invalid, fake.deps);
      await handleContact(honeypot, fake.deps);
    }

    const firstFive = [];
    for (let count = 0; count < 5; count += 1) {
      firstFive.push(await handleContact(ada(), fake.deps));
    }
    const sixth = await handleContact(ada(), fake.deps);
    const sendsAfterSix = fake.send.mock.calls.length;
    const other = await handleContact(ada(), { ...fake.deps, ip: OTHER_IP });

    expect(firstFive).toEqual([
      { ok: true },
      { ok: true },
      { ok: true },
      { ok: true },
      { ok: true },
    ]);
    expect(sixth).toStrictEqual({ ok: false, reason: "rate-limited" });
    expect(sendsAfterSix).toBe(5);
    expect(other).toStrictEqual({ ok: true });
    expect(fake.send).toHaveBeenCalledTimes(6);
    expect(fake.log).not.toHaveBeenCalled();
  });

  it("reports failure and logs it when the site is not configured", async () => {
    const { send, log, deps } = setup({ config: null });

    const result = await handleContact(ada(), deps);

    expect(result).toStrictEqual({ ok: false, reason: "failed" });
    expect(send).not.toHaveBeenCalled();
    expect(log.mock.calls).toEqual([[NOT_CONFIGURED]]);
  });

  it("reports failure and logs the sender's error, without the message, when sending throws", async () => {
    const refused = setup();
    refused.send.mockRejectedValue(new Error("Invalid `from` field."));

    const refusedResult = await handleContact(ada(), refused.deps);

    expect(refusedResult).toStrictEqual({ ok: false, reason: "failed" });
    expect(refused.log.mock.calls).toEqual([
      ["Contact form: the send failed: Invalid `from` field."],
    ]);

    const odd = setup();
    odd.send.mockRejectedValue("boom");

    const oddResult = await handleContact(ada(), odd.deps);

    expect(oddResult).toStrictEqual({ ok: false, reason: "failed" });
    expect(odd.log.mock.calls).toEqual([
      ["Contact form: the send failed: boom"],
    ]);
  });
});
