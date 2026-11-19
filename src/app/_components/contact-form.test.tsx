// @vitest-environment happy-dom
import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { ContactResult } from "@/lib/contact";
import { ContactForm } from "./contact-form";

type Action = (formData: FormData) => Promise<ContactResult>;

const EMAIL_ERROR = "Enter an email address like name@example.com.";
const EMAIL_EMPTY = "Enter your email address.";
const MESSAGE_EMPTY = "Write a message.";
const MESSAGE_LONG = "Keep your message under 5,000 characters.";
const FAILED =
  "Your message couldn\u2019t be sent. Please try again, or email Rachel\u00a0directly.";
const LIMITED =
  "Too many messages. Please try again later, or email Rachel\u00a0directly.";

const BUTTON_CLASS =
  "border border-heading duration-150 ease-[cubic-bezier(0.2,0.7,0.2,1)] h-14 hover:bg-heading hover:text-bg inline-flex items-center justify-center justify-self-center max-w-full text-heading transition-colors type-button w-50";
const ALERT_CLASS = "font-medium text-center text-error type-small";

afterEach(() => {
  cleanup();
});

function attrs(el: Element): Record<string, string> {
  const out: Record<string, string> = {};
  for (const a of Array.from(el.attributes)) {
    out[a.name] =
      a.name === "class" ? a.value.split(" ").sort().join(" ") : a.value;
  }
  return out;
}

function deferred(): {
  promise: Promise<ContactResult>;
  resolve: (result: ContactResult) => void;
} {
  let resolve: (result: ContactResult) => void = () => undefined;
  const promise = new Promise<ContactResult>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

function must<T>(value: T | null | undefined): T {
  if (value === null || value === undefined) {
    expect.fail("expected a value, got " + String(value));
  }
  return value;
}

function form(): HTMLFormElement {
  return must(document.querySelector("form"));
}

function sendButton(): HTMLButtonElement {
  return must(document.querySelector("button"));
}

function emailControl(): HTMLInputElement {
  return must(document.querySelector<HTMLInputElement>("#contact-email"));
}

function messageControl(): HTMLTextAreaElement {
  return must(document.querySelector<HTMLTextAreaElement>("#contact-message"));
}

function values(): string[] {
  return [
    must(document.querySelector<HTMLInputElement>("#contact-name")).value,
    emailControl().value,
    messageControl().value,
  ];
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
  fireEvent.click(sendButton());
}

function errorTexts(): (string | null)[] {
  return Array.from(
    document.querySelectorAll("[id$='-error']"),
    (el) => el.textContent,
  );
}

async function alertElement(): Promise<Element> {
  return waitFor(() => must(document.querySelector("[role='alert']")));
}

function expectFailureAlert(alert: Element, text: string): void {
  expect(alert.tagName).toBe("P");
  expect(attrs(alert)).toEqual({ role: "alert", class: ALERT_CLASS });
  expect(alert.textContent).toBe(text);
  expect(alert.children).toHaveLength(1);
  const link = must(alert.children[0]);
  expect(link.tagName).toBe("A");
  expect(attrs(link)).toEqual({ href: "mailto:rachel@example.com" });
  expect(link.textContent).toBe("email Rachel\u00a0directly");
}

function fill(email: string, action: Action): void {
  render(<ContactForm sendAction={action} />);
  fireEvent.change(screen.getByLabelText(/^Email/), {
    target: { value: email },
  });
  fireEvent.change(screen.getByLabelText(/^Message/), {
    target: { value: "Hello" },
  });
}

describe("ContactForm", () => {
  it("rejects an email with other text before or after the whole address", async () => {
    const action = vi.fn<Action>(() => Promise.resolve({ ok: true }));
    fill("x y@z.co", action);
    const send = screen.getByRole("button", { name: "Send" });
    fireEvent.submit(send);
    expect(await screen.findByText(EMAIL_ERROR)).toBeDefined();
    expect(action).not.toHaveBeenCalled();

    fireEvent.change(screen.getByLabelText(/^Email/), {
      target: { value: "a@b.co c" },
    });
    fireEvent.submit(send);
    expect(await screen.findByText(EMAIL_ERROR)).toBeDefined();
    expect(action).not.toHaveBeenCalled();

    fireEvent.change(screen.getByLabelText(/^Email/), {
      target: { value: "a@b.co" },
    });
    fireEvent.submit(send);
    await waitFor(() => {
      expect(action).toHaveBeenCalledTimes(1);
    });
  });

  it("cancels the browser's own submit", () => {
    fill(
      "",
      vi.fn<Action>(() => Promise.resolve({ ok: true })),
    );
    const send = screen.getByRole("button", { name: "Send" });
    expect(fireEvent.submit(send)).toBe(false);

    fireEvent.change(screen.getByLabelText(/^Email/), {
      target: { value: "a@b.co" },
    });
    fireEvent.change(screen.getByLabelText(/^Message/), {
      target: { value: "Hello" },
    });
    expect(fireEvent.submit(send)).toBe(false);
  });

  it("disables Send and reads Sending until the action settles", async () => {
    const pending = deferred();
    const action = vi.fn<Action>(() => pending.promise);
    render(<ContactForm sendAction={action} />);
    fillAda();

    submit();

    expect(attrs(sendButton())).toEqual({
      type: "submit",
      disabled: "",
      class: BUTTON_CLASS,
    });
    expect(sendButton().textContent).toBe("Sending\u2026");
    expect(action).toHaveBeenCalledTimes(1);

    await act(async () => {
      pending.resolve({ ok: false, reason: "failed" });
      await pending.promise;
    });

    expect(attrs(sendButton())).toEqual({
      type: "submit",
      class: BUTTON_CLASS,
    });
    expect(sendButton().textContent).toBe("Send");

    cleanup();
    const unused = vi.fn<Action>(() => Promise.resolve({ ok: true }));
    render(<ContactForm sendAction={unused} />);
    fillAda();
    fireEvent.change(screen.getByLabelText(/^Email/), {
      target: { value: "" },
    });

    submit();

    expect(attrs(sendButton())).toEqual({
      type: "submit",
      class: BUTTON_CLASS,
    });
    expect(sendButton().textContent).toBe("Send");
  });

  it("shows the failure alert under Send with a mailto link and keeps the values", async () => {
    const action = vi.fn<Action>(() =>
      Promise.resolve({ ok: false, reason: "failed" }),
    );
    render(<ContactForm sendAction={action} />);
    fillAda();

    submit();
    const alert = await alertElement();

    expectFailureAlert(alert, FAILED);
    expect(Array.from(form().children, (child) => child.tagName)).toEqual([
      "DIV",
      "DIV",
      "DIV",
      "INPUT",
      "BUTTON",
      "P",
    ]);
    expect(form().lastElementChild).toBe(alert);
    expect(values()).toEqual([
      "Ada Lovelace",
      "ada@example.com",
      "Hello Rachel",
    ]);
    expect(document.querySelector("[role='status']")).toBeNull();
    expect(sendButton().textContent).toBe("Send");
    expect(sendButton().hasAttribute("disabled")).toBe(false);

    cleanup();
    const rejecting = vi.fn<Action>(() => Promise.reject(new Error("offline")));
    render(<ContactForm sendAction={rejecting} />);
    fillAda();

    submit();
    const offline = await alertElement();

    expectFailureAlert(offline, FAILED);
    expect(values()).toEqual([
      "Ada Lovelace",
      "ada@example.com",
      "Hello Rachel",
    ]);
    expect(attrs(sendButton())).toEqual({
      type: "submit",
      class: BUTTON_CLASS,
    });
    expect(sendButton().textContent).toBe("Send");
  });

  it("shows the rate-limit alert with a mailto link", async () => {
    const action = vi.fn<Action>(() =>
      Promise.resolve({ ok: false, reason: "rate-limited" }),
    );
    render(<ContactForm sendAction={action} />);
    fillAda();

    submit();
    const alert = await alertElement();

    expectFailureAlert(alert, LIMITED);
    expect(form().lastElementChild).toBe(alert);
  });

  it("clears the alert on the next submit", async () => {
    const action = vi.fn<Action>(() =>
      Promise.resolve({ ok: false, reason: "failed" }),
    );
    render(<ContactForm sendAction={action} />);
    fillAda();
    submit();
    await alertElement();

    fireEvent.change(screen.getByLabelText(/^Email/), {
      target: { value: "" },
    });
    submit();

    expect(document.querySelector("[role='alert']")).toBeNull();
    expect(document.getElementById("contact-email-error")?.textContent).toBe(
      EMAIL_EMPTY,
    );

    cleanup();
    const pending = deferred();
    const second = vi
      .fn<Action>()
      .mockResolvedValueOnce({ ok: false, reason: "failed" })
      .mockReturnValueOnce(pending.promise);
    render(<ContactForm sendAction={second} />);
    fillAda();
    submit();
    await alertElement();

    submit();

    expect(document.querySelector("[role='alert']")).toBeNull();
    expect(second).toHaveBeenCalledTimes(2);
  });

  it("shows the server's field errors and focuses the first invalid field", async () => {
    const action = vi.fn<Action>(() =>
      Promise.resolve({
        ok: false,
        reason: "invalid",
        errors: { email: EMAIL_ERROR, message: MESSAGE_EMPTY },
      }),
    );
    render(<ContactForm sendAction={action} />);
    fillAda();

    submit();
    await waitFor(() => {
      expect(emailControl().getAttribute("aria-invalid")).toBe("true");
    });

    expect(emailControl().getAttribute("aria-describedby")).toBe(
      "contact-email-error",
    );
    expect(messageControl().getAttribute("aria-invalid")).toBe("true");
    expect(messageControl().getAttribute("aria-describedby")).toBe(
      "contact-message-error",
    );
    expect(errorTexts()).toEqual([EMAIL_ERROR, MESSAGE_EMPTY]);
    expect(document.activeElement).toBe(emailControl());
    expect(document.querySelector("[role='alert']")).toBeNull();
    expect(document.querySelector("[role='status']")).toBeNull();
    expect(sendButton().textContent).toBe("Send");
    expect(sendButton().hasAttribute("disabled")).toBe(false);

    cleanup();
    const long = vi.fn<Action>(() =>
      Promise.resolve({
        ok: false,
        reason: "invalid",
        errors: { message: MESSAGE_LONG },
      }),
    );
    render(<ContactForm sendAction={long} />);
    fillAda();

    submit();
    await waitFor(() => {
      expect(messageControl().getAttribute("aria-invalid")).toBe("true");
    });

    expect(errorTexts()).toEqual([MESSAGE_LONG]);
    expect(document.activeElement).toBe(messageControl());
    expect(emailControl().hasAttribute("aria-invalid")).toBe(false);
  });

  it("refuses a message over 5,000 characters before calling the action", () => {
    const action = vi.fn<Action>(() => Promise.resolve({ ok: true }));
    render(<ContactForm sendAction={action} />);
    fillAda();
    fireEvent.change(messageControl(), { target: { value: "a".repeat(5001) } });

    submit();

    expect(messageControl().getAttribute("aria-invalid")).toBe("true");
    expect(messageControl().getAttribute("aria-describedby")).toBe(
      "contact-message-error",
    );
    expect(document.getElementById("contact-message-error")?.textContent).toBe(
      MESSAGE_LONG,
    );
    expect(document.activeElement).toBe(messageControl());
    expect(action).not.toHaveBeenCalled();

    cleanup();
    const near = vi.fn<Action>(() =>
      Promise.resolve({ ok: false, reason: "failed" }),
    );
    render(<ContactForm sendAction={near} />);
    fillAda();
    fireEvent.change(messageControl(), { target: { value: "a".repeat(5000) } });

    submit();

    expect(near).toHaveBeenCalledTimes(1);
    expect(document.getElementById("contact-message-error")).toBeNull();
  });
});
