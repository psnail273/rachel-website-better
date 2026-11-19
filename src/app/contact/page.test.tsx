// @vitest-environment happy-dom
import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
} from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { siteConfig } from "@/lib/site-config";
import { sendMessage } from "./actions";
import ContactPage, { metadata } from "./page";

vi.mock("./actions", () => ({ sendMessage: vi.fn() }));

const send = vi.mocked(sendMessage);

const NBSP = "\u00a0";
const EMAIL_EMPTY = "Enter your email address.";
const EMAIL_BAD = "Enter an email address like name@example.com.";
const MESSAGE_EMPTY = "Write a message.";

const INPUT_CLASSES =
  "w-full p-tight border border-line-strong bg-surface text-heading leading-[1.4] aria-invalid:border-error aria-invalid:shadow-[inset_0_0_0_1px_var(--error)]";
const BUTTON_CLASSES =
  "border border-heading duration-150 ease-[cubic-bezier(0.2,0.7,0.2,1)] h-14 hover:bg-heading hover:text-bg inline-flex items-center justify-center justify-self-center max-w-full text-heading transition-colors type-button w-50";

beforeEach(() => {
  send.mockReset();
});

afterEach(() => {
  cleanup();
});

function must<T>(value: T | null | undefined): T {
  if (value === null || value === undefined) {
    expect.fail("expected a value, got " + String(value));
  }
  return value;
}

function classes(el: Element): string[] {
  return Array.from(el.classList).sort();
}

function cls(list: string): string {
  return list.split(" ").sort().join(" ");
}

function attrs(el: Element): Record<string, string> {
  const out: Record<string, string> = {};
  for (const a of Array.from(el.attributes)) {
    out[a.name] = a.name === "class" ? cls(a.value) : a.value;
  }
  return out;
}

function pick(selector: string): Element {
  return must(document.querySelector(selector));
}

function nameInput(): HTMLInputElement {
  return must(document.querySelector<HTMLInputElement>("#contact-name"));
}

function emailInput(): HTMLInputElement {
  return must(document.querySelector<HTMLInputElement>("#contact-email"));
}

function messageInput(): HTMLTextAreaElement {
  return must(document.querySelector<HTMLTextAreaElement>("#contact-message"));
}

function fill(el: Element, value: string): void {
  fireEvent.change(el, { target: { value } });
}

function submit(): void {
  fireEvent.click(must(document.querySelector("button")));
}

function errorIds(): string[] {
  return Array.from(document.querySelectorAll("[id$='-error']"), (e) => e.id);
}

function errorTexts(): string[] {
  return Array.from(
    document.querySelectorAll("[id$='-error']"),
    (e) => e.textContent,
  );
}

function describedBy(el: Element): string | null {
  return el.getAttribute("aria-describedby");
}

function invalid(el: Element): string | null {
  return el.getAttribute("aria-invalid");
}

function formWrapper(): Element {
  return must(pick("#contact-form-heading").parentElement);
}

describe("ContactPage", () => {
  it("shows the Contact h1 first in one centred column, then the statements and the Send a message heading", () => {
    const { container } = render(<ContactPage />);

    expect(container.children).toHaveLength(1);
    const section = must(container.children[0]);
    expect(section.tagName).toBe("SECTION");
    expect(attrs(section)).toEqual({
      "data-section": "",
      "aria-labelledby": "contact-heading",
    });
    expect(section.children).toHaveLength(1);
    const center = must(section.children[0]);
    expect(center.tagName).toBe("DIV");
    expect(attrs(center)).toEqual({ "data-center": "" });

    expect(center.children).toHaveLength(2);
    const h1 = must(center.children[0]);
    expect(h1.tagName).toBe("H1");
    expect(attrs(h1)).toEqual({
      "data-heading": "1",
      id: "contact-heading",
      class: "type-h1",
    });
    expect(h1.textContent).toBe("Contact");
    const block = must(center.children[1]);
    expect(block.tagName).toBe("DIV");
    expect(attrs(block)).toEqual({ "data-stack": "block" });

    expect(block.children).toHaveLength(2);
    const flow = must(block.children[0]);
    expect(flow.tagName).toBe("DIV");
    expect(attrs(flow)).toEqual({ "data-stack": "flow" });
    expect(flow.children).toHaveLength(2);
    const leads = Array.from(flow.children);
    expect(leads.map((p) => p.tagName)).toEqual(["P", "P"]);
    expect(leads.map(attrs)).toEqual([
      { "data-lead": "", class: "type-lead" },
      { "data-lead": "", class: "type-lead" },
    ]);

    const wrapper = must(block.children[1]);
    expect(wrapper.tagName).toBe("DIV");
    expect(attrs(wrapper)).toEqual({});
    expect(wrapper.children).toHaveLength(2);
    const h2 = must(wrapper.children[0]);
    expect(h2.tagName).toBe("H2");
    expect(attrs(h2)).toEqual({
      "data-heading": "2",
      id: "contact-form-heading",
      class: "type-h2",
    });
    expect(h2.textContent).toBe(`Send${NBSP}a message`);
    expect(must(wrapper.children[1]).tagName).toBe("FORM");

    expect(container.querySelectorAll("h1")).toHaveLength(1);
    expect(container.querySelectorAll("h2")).toHaveLength(1);
  });

  it("ties the statements' last words and links Wellness Alliance in a new tab and the email by mailto", () => {
    const { container } = render(<ContactPage />);
    const leads = Array.from(container.querySelectorAll("[data-lead]"));
    const links = Array.from(container.querySelectorAll("a"));

    expect(leads.map((p) => p.textContent)).toEqual([
      `For therapy, please reach out through Wellness${NBSP}Alliance.`,
      `For performances, workshops or anything else, email me${NBSP}directly.`,
    ]);
    expect(links).toHaveLength(2);
    expect(links.map(attrs)).toEqual([
      {
        href: "https://wellnessalliancestl.com/rsiegel",
        target: "_blank",
        rel: "noopener noreferrer",
      },
      { href: "mailto:rachel@example.com" },
    ]);
    expect(links.map((a) => a.textContent)).toEqual([
      `Wellness${NBSP}Alliance`,
      `email me${NBSP}directly`,
    ]);
    expect(leads[0]?.contains(links[0] ?? null)).toBe(true);
    expect(leads[1]?.contains(links[1] ?? null)).toBe(true);
    expect(links[0]?.getAttribute("href")).toBe(siteConfig.wellnessAllianceUrl);
    expect(links[1]?.getAttribute("href")).toBe(`mailto:${siteConfig.email}`);
  });

  it("has its own title and description, and no Upcoming strip", () => {
    const { container } = render(<ContactPage />);

    expect(metadata).toStrictEqual({
      title: "Contact",
      description:
        "How to reach Rachel Siegel: therapy inquiries through Wellness Alliance, and email for performances, workshops and anything else.",
    });
    expect(container.querySelectorAll("section")).toHaveLength(1);
    expect(container.textContent).not.toMatch(/upcoming/i);
  });

  it("names the form by its heading and gives it Name, Email (required) and Message (required) fields and a Send button", () => {
    render(<ContactPage />);
    const form = pick("form");

    expect(attrs(form)).toEqual({
      "data-form": "",
      novalidate: "",
      "aria-labelledby": "contact-form-heading",
      class: cls("grid gap-flow max-w-(--measure) mx-auto text-start"),
    });
    expect(form.children).toHaveLength(4);
    const fields = Array.from(form.children).slice(0, 3);
    expect(fields.map((f) => f.tagName)).toEqual(["DIV", "DIV", "DIV"]);
    expect(fields.map(attrs)).toEqual([
      { class: cls("grid gap-tight") },
      { class: cls("grid gap-tight") },
      { class: cls("grid gap-tight") },
    ]);
    expect(fields.map((f) => f.children.length)).toEqual([2, 2, 2]);

    const labels = fields.map((f) => must(f.children[0]));
    const controls = fields.map((f) => must(f.children[1]));
    expect(labels.map((l) => l.tagName)).toEqual(["LABEL", "LABEL", "LABEL"]);
    expect(labels.map((l) => l.textContent)).toEqual([
      "Name",
      "Email (required)",
      "Message (required)",
    ]);
    expect(labels.map(attrs)).toEqual([
      { for: "contact-name", class: cls("font-medium text-heading") },
      { for: "contact-email", class: cls("font-medium text-heading") },
      { for: "contact-message", class: cls("font-medium text-heading") },
    ]);
    expect(labels.map((l) => l.children.length)).toEqual([0, 1, 1]);
    const spans = [must(labels[1]?.children[0]), must(labels[2]?.children[0])];
    expect(spans.map((s) => s.tagName)).toEqual(["SPAN", "SPAN"]);
    expect(spans.map(classes)).toEqual([
      ["font-normal", "text-muted"],
      ["font-normal", "text-muted"],
    ]);
    expect(spans.map((s) => s.textContent)).toEqual([
      "(required)",
      "(required)",
    ]);
    expect(labels.slice(1).map((l) => l.firstChild?.textContent)).toEqual([
      "Email ",
      "Message ",
    ]);

    expect(controls.map((c) => c.tagName)).toEqual([
      "INPUT",
      "INPUT",
      "TEXTAREA",
    ]);
    expect(controls.map(attrs)).toEqual([
      {
        id: "contact-name",
        name: "name",
        type: "text",
        autocomplete: "name",
        class: cls(INPUT_CLASSES),
      },
      {
        id: "contact-email",
        name: "email",
        type: "email",
        autocomplete: "email",
        required: "",
        class: cls(INPUT_CLASSES),
      },
      {
        id: "contact-message",
        name: "message",
        rows: "6",
        required: "",
        class: cls(INPUT_CLASSES + " resize-y"),
      },
    ]);

    const button = must(form.children[3]);
    expect(button.tagName).toBe("BUTTON");
    expect(attrs(button)).toEqual({
      type: "submit",
      class: cls(BUTTON_CLASSES),
    });
    expect(button.textContent).toBe("Send");
  });

  it("marks an empty email with its message and moves focus to it", () => {
    render(<ContactPage />);
    fill(messageInput(), "Hello Rachel");

    submit();

    expect(invalid(emailInput())).toBe("true");
    expect(describedBy(emailInput())).toBe("contact-email-error");
    const field = must(emailInput().parentElement);
    expect(field.children).toHaveLength(3);
    expect(must(field.children[0]).tagName).toBe("LABEL");
    expect(field.children[1]).toBe(emailInput());
    const error = must(field.children[2]);
    expect(error.tagName).toBe("P");
    expect(attrs(error)).toEqual({
      id: "contact-email-error",
      class: cls("font-medium text-error type-small"),
    });
    expect(error.textContent).toBe(EMAIL_EMPTY);
    expect(document.activeElement).toBe(emailInput());
    expect(invalid(nameInput())).toBeNull();
    expect(invalid(messageInput())).toBeNull();
    expect(describedBy(nameInput())).toBeNull();
    expect(describedBy(messageInput())).toBeNull();
    expect(nameInput().parentElement?.children).toHaveLength(2);
    expect(messageInput().parentElement?.children).toHaveLength(2);
    expect(errorIds()).toEqual(["contact-email-error"]);
    expect(send).not.toHaveBeenCalled();
  });

  it("rejects an email that misses a part and accepts a whole one", () => {
    const bad = [
      "rachel@",
      "rachel@example",
      "@example.com",
      "rachel@exa mple.com",
    ];
    const seen: unknown[] = [];
    for (const value of bad) {
      render(<ContactPage />);
      fill(emailInput(), value);
      fill(messageInput(), "Hello Rachel");
      submit();
      seen.push({
        value,
        invalid: invalid(emailInput()),
        describedBy: describedBy(emailInput()),
        text: document.getElementById("contact-email-error")?.textContent,
        focused: document.activeElement === emailInput(),
        calls: send.mock.calls.length,
      });
      cleanup();
    }
    expect(seen).toEqual(
      bad.map((value) => ({
        value,
        invalid: "true",
        describedBy: "contact-email-error",
        text: EMAIL_BAD,
        focused: true,
        calls: 0,
      })),
    );

    render(<ContactPage />);
    fill(emailInput(), "rachel@");
    fireEvent.blur(emailInput());
    expect(invalid(emailInput())).toBeNull();
    expect(describedBy(emailInput())).toBeNull();
    expect(document.getElementById("contact-email-error")).toBeNull();
    fill(messageInput(), "Hello Rachel");
    submit();
    expect(document.getElementById("contact-email-error")?.textContent).toBe(
      EMAIL_BAD,
    );
    cleanup();

    send.mockResolvedValue({ ok: false });
    const good = ["rachel@example.com", "r@e.co"];
    const accepted: unknown[] = [];
    for (const value of good) {
      send.mockClear();
      render(<ContactPage />);
      fill(emailInput(), value);
      fill(messageInput(), "Hello Rachel");
      submit();
      accepted.push({
        value,
        invalid: invalid(emailInput()),
        describedBy: describedBy(emailInput()),
        error: document.getElementById("contact-email-error"),
        calls: send.mock.calls.length,
      });
      cleanup();
    }
    expect(accepted).toEqual(
      good.map((value) => ({
        value,
        invalid: null,
        describedBy: null,
        error: null,
        calls: 1,
      })),
    );
  });

  it("asks for a message when it is empty or only spaces", () => {
    const seen: unknown[] = [];
    const values = ["", "   "];
    for (const value of values) {
      render(<ContactPage />);
      fill(emailInput(), "rachel@example.com");
      fill(messageInput(), value);
      submit();
      const field = messageInput().parentElement;
      const error = field?.children[2];
      seen.push({
        invalid: invalid(messageInput()),
        describedBy: describedBy(messageInput()),
        children: field?.children.length,
        order: [field?.children[0]?.tagName, field?.children[1]?.tagName],
        error: error ? attrs(error) : null,
        tag: error?.tagName,
        text: error?.textContent,
        focused: document.activeElement === messageInput(),
        emailInvalid: invalid(emailInput()),
        calls: send.mock.calls.length,
      });
      cleanup();
    }
    const expected = {
      invalid: "true",
      describedBy: "contact-message-error",
      children: 3,
      order: ["LABEL", "TEXTAREA"],
      error: {
        id: "contact-message-error",
        class: cls("font-medium text-error type-small"),
      },
      tag: "P",
      text: MESSAGE_EMPTY,
      focused: true,
      emailInvalid: null,
      calls: 0,
    };
    expect(seen).toEqual([expected, expected]);
  });

  it("shows both messages and focuses the email when both required fields are empty", () => {
    render(<ContactPage />);

    submit();

    expect(invalid(emailInput())).toBe("true");
    expect(invalid(messageInput())).toBe("true");
    expect(describedBy(emailInput())).toBe("contact-email-error");
    expect(describedBy(messageInput())).toBe("contact-message-error");
    expect(errorTexts()).toEqual([EMAIL_EMPTY, MESSAGE_EMPTY]);
    expect(document.activeElement).toBe(emailInput());
    expect(invalid(nameInput())).toBeNull();
    expect(send).not.toHaveBeenCalled();
  });

  it("clears the errors on a valid submit and sends the three fields to the action", () => {
    send.mockResolvedValue({ ok: false });
    render(<ContactPage />);
    submit();
    expect(errorIds()).toHaveLength(2);

    fill(nameInput(), "Ada Lovelace");
    fill(emailInput(), "ada@example.com");
    fill(messageInput(), "Hello Rachel");
    submit();

    expect(errorIds()).toEqual([]);
    const controls = [nameInput(), emailInput(), messageInput()];
    expect(controls.map(invalid)).toEqual([null, null, null]);
    expect(controls.map(describedBy)).toEqual([null, null, null]);
    expect(send).toHaveBeenCalledTimes(1);
    const args = must(send.mock.calls[0]);
    expect(args).toHaveLength(1);
    expect(Array.from(must(args[0]).entries())).toEqual([
      ["name", "Ada Lovelace"],
      ["email", "ada@example.com"],
      ["message", "Hello Rachel"],
    ]);
  });

  it("keeps the form and its values when the action reports failure", async () => {
    send.mockResolvedValue({ ok: false });
    render(<ContactPage />);
    fill(nameInput(), "Ada Lovelace");
    fill(emailInput(), "ada@example.com");
    fill(messageInput(), "Hello Rachel");
    const before = formWrapper().outerHTML;

    submit();
    await act(async () => {
      await send.mock.results[0]?.value;
    });

    expect(send).toHaveBeenCalledTimes(1);
    expect(formWrapper().outerHTML).toBe(before);
    expect(
      [nameInput(), emailInput(), messageInput()].map((c) => c.value),
    ).toEqual(["Ada Lovelace", "ada@example.com", "Hello Rachel"]);
    expect(document.querySelector("[role='status']")).toBeNull();
  });

  it("replaces the form with a focused status Lead when the action reports success", async () => {
    send.mockResolvedValue({ ok: true });
    render(<ContactPage />);
    fill(nameInput(), "Ada Lovelace");
    fill(emailInput(), "ada@example.com");
    fill(messageInput(), "Hello Rachel");
    const wrapper = formWrapper();

    submit();
    const status = await screen.findByRole("status");

    expect(document.querySelector("form")).toBeNull();
    expect(wrapper.children).toHaveLength(2);
    const h2 = must(wrapper.children[0]);
    expect(h2.tagName).toBe("H2");
    expect(h2.textContent).toBe(`Send${NBSP}a message`);
    expect(wrapper.children[1]).toBe(status);
    expect(status.tagName).toBe("P");
    expect(attrs(status)).toEqual({
      "data-lead": "",
      class: cls("outline-none type-lead"),
      role: "status",
      tabindex: "-1",
    });
    expect(status.textContent).toBe(
      `Thanks \u2014 Rachel will get back to${NBSP}you.`,
    );
    expect(document.activeElement).toBe(status);
  });
});
