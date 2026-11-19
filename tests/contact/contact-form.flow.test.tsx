// @vitest-environment happy-dom
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { ContactForm } from "@/app/_components/contact-form";
import { handleContact, type ContactDeps } from "@/server/contact/handle";
import { createRateLimiter } from "@/server/contact/rate-limit";
import type { MailSender } from "@/server/contact/sender";

const CONFIG = {
  apiKey: "re_test_key",
  to: "rachel@example.com",
  from: "Rachel Siegel website <website@example.com>",
};

const ADA_MAIL = {
  from: "Rachel Siegel website <website@example.com>",
  to: "rachel@example.com",
  replyTo: "ada@example.com",
  subject: "Website message from Ada Lovelace",
  text: "Name: Ada Lovelace\nEmail: ada@example.com\n\nHello Rachel",
};

const SUCCESS = "Thanks \u2014 Rachel will get back to\u00a0you.";
const FAILED =
  "Your message couldn\u2019t be sent. Please try again, or email Rachel\u00a0directly.";
const LIMITED =
  "Too many messages. Please try again later, or email Rachel\u00a0directly.";

afterEach(() => {
  cleanup();
});

function setup(over: Partial<ContactDeps> = {}): {
  send: ReturnType<typeof vi.fn<MailSender["send"]>>;
  log: ReturnType<typeof vi.fn<(line: string) => void>>;
  deps: ContactDeps;
} {
  const send = vi.fn<MailSender["send"]>(() => Promise.resolve());
  const log = vi.fn<(line: string) => void>();
  const deps: ContactDeps = {
    ip: "203.0.113.9",
    config: CONFIG,
    sender: { send },
    limiter: createRateLimiter(() => 0),
    log,
    ...over,
  };
  return { send, log, deps };
}

function show(deps: ContactDeps): void {
  render(
    <ContactForm sendAction={(formData) => handleContact(formData, deps)} />,
  );
}

function fillAda(): void {
  fireEvent.change(screen.getByLabelText("Name"), {
    target: { value: "Ada Lovelace" },
  });
  fireEvent.change(screen.getByLabelText(/^Email/), {
    target: { value: "ada@example.com" },
  });
  fireEvent.change(screen.getByLabelText(/^Message/), {
    target: { value: "Hello Rachel" },
  });
}

function submit(): void {
  const button = document.querySelector("button");
  if (button === null) expect.fail("no Send button");
  fireEvent.click(button);
}

async function appears(selector: string): Promise<Element> {
  return waitFor(() => {
    const found = document.querySelector(selector);
    if (found === null) expect.fail("nothing matches " + selector);
    return found;
  });
}

function values(): string[] {
  return ["#contact-name", "#contact-email", "#contact-message"].map(
    (selector) => {
      const control = document.querySelector<
        HTMLInputElement | HTMLTextAreaElement
      >(selector);
      if (control === null) expect.fail("no control " + selector);
      return control.value;
    },
  );
}

describe("ContactForm with handleContact", () => {
  it("sends one mail with the visitor's details and shows the success Lead", async () => {
    const { send, log, deps } = setup();
    show(deps);
    fillAda();

    submit();
    const status = await appears("[role='status']");

    expect(status.textContent).toBe(SUCCESS);
    expect(send.mock.calls).toEqual([[ADA_MAIL]]);
    expect(log).not.toHaveBeenCalled();
    expect(document.querySelector("form")).toBeNull();
    expect(document.querySelector("[role='alert']")).toBeNull();
  });

  it("keeps the values and shows the failure alert when the sender throws or the site is not configured", async () => {
    const thrown = setup();
    thrown.send.mockRejectedValue(
      new Error("Unable to fetch data. The request could not be resolved."),
    );
    show(thrown.deps);
    fillAda();

    submit();
    const alert = await appears("[role='alert']");

    expect(alert.textContent).toBe(FAILED);
    expect(values()).toEqual([
      "Ada Lovelace",
      "ada@example.com",
      "Hello Rachel",
    ]);
    expect(document.querySelector("[role='status']")).toBeNull();
    expect(thrown.log.mock.calls).toEqual([
      [
        "Contact form: the send failed: Unable to fetch data. The request could not be resolved.",
      ],
    ]);

    cleanup();
    const unconfigured = setup({ config: null });
    show(unconfigured.deps);
    fillAda();

    submit();
    const unconfiguredAlert = await appears("[role='alert']");

    expect(unconfiguredAlert.textContent).toBe(FAILED);
    expect(values()).toEqual([
      "Ada Lovelace",
      "ada@example.com",
      "Hello Rachel",
    ]);
    expect(document.querySelector("[role='status']")).toBeNull();
    expect(unconfigured.send).not.toHaveBeenCalled();
    expect(unconfigured.log.mock.calls).toEqual([
      ["Contact form: not configured."],
    ]);
  });

  it("shows the rate-limit alert on the sixth message from one address", async () => {
    const { send, deps } = setup();
    const leads: (string | null)[] = [];
    for (let count = 0; count < 5; count += 1) {
      show(deps);
      fillAda();
      submit();
      const status = await appears("[role='status']");
      leads.push(status.textContent);
      cleanup();
    }

    show(deps);
    fillAda();
    submit();
    const alert = await appears("[role='alert']");

    expect(leads).toEqual([SUCCESS, SUCCESS, SUCCESS, SUCCESS, SUCCESS]);
    expect(alert.textContent).toBe(LIMITED);
    expect(send).toHaveBeenCalledTimes(5);
    expect(values()).toEqual([
      "Ada Lovelace",
      "ada@example.com",
      "Hello Rachel",
    ]);
  });
});
