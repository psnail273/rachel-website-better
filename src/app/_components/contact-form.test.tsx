// @vitest-environment happy-dom
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
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
  it("rejects an email with other text before or after the whole address", async () => {
    const action = vi.fn(() => Promise.resolve({ ok: true }));
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
      vi.fn(() => Promise.resolve({ ok: true })),
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
});
