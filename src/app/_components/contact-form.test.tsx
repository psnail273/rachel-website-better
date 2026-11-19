// @vitest-environment happy-dom
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { ContactForm } from "./contact-form";

const EMAIL_ERROR = "Enter an email address like name@example.com.";

afterEach(() => {
  cleanup();
});

function fill(email: string): HTMLFormElement {
  const { container } = render(
    <ContactForm sendAction={vi.fn(() => Promise.resolve({ ok: true }))} />,
  );
  fireEvent.change(container.querySelector("#contact-email") as HTMLElement, {
    target: { value: email },
  });
  fireEvent.change(container.querySelector("#contact-message") as HTMLElement, {
    target: { value: "Hello" },
  });
  return container.querySelector("form") as HTMLFormElement;
}

describe("ContactForm", () => {
  it.each(["x y@z.co", "a@b.co c"])(
    "rejects an email with other text before or after the whole address",
    async (email) => {
      const action = vi.fn(() => Promise.resolve({ ok: true }));
      const { container } = render(<ContactForm sendAction={action} />);
      fireEvent.change(
        container.querySelector("#contact-email") as HTMLElement,
        { target: { value: email } },
      );
      fireEvent.change(
        container.querySelector("#contact-message") as HTMLElement,
        { target: { value: "Hello" } },
      );
      fireEvent.submit(container.querySelector("form") as HTMLFormElement);
      expect(await screen.findByText(EMAIL_ERROR)).toBeDefined();
      expect(action).not.toHaveBeenCalled();
    },
  );

  it("cancels the browser's own submit", () => {
    const form = fill("a@b.co");
    expect(fireEvent.submit(form)).toBe(false);
  });
});
