// @vitest-environment happy-dom
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { ContactForm } from "./contact-form";

const EMAIL_ERROR = "Enter an email address like name@example.com.";

afterEach(() => {
  cleanup();
});

function fill(email: string, action: () => Promise<{ ok: boolean }>): void {
  render(<ContactForm sendAction={action} />);
  fireEvent.change(screen.getByLabelText(/^Email/), {
    target: { value: email },
  });
  fireEvent.change(screen.getByLabelText(/^Message/), {
    target: { value: "Hello" },
  });
}

describe("ContactForm", () => {
  it.each(["x y@z.co", "a@b.co c"])(
    "rejects an email with other text before or after the whole address",
    async (email) => {
      const action = vi.fn(() => Promise.resolve({ ok: true }));
      fill(email, action);
      fireEvent.submit(screen.getByRole("button", { name: "Send" }));
      expect(await screen.findByText(EMAIL_ERROR)).toBeDefined();
      expect(action).not.toHaveBeenCalled();
    },
  );

  it("cancels the browser's own submit", () => {
    fill(
      "a@b.co",
      vi.fn(() => Promise.resolve({ ok: true })),
    );
    expect(fireEvent.submit(screen.getByRole("button", { name: "Send" }))).toBe(
      false,
    );
  });
});
