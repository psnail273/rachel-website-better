"use client";

import { useState, type ReactNode, type SyntheticEvent } from "react";
import type { ContactResult } from "../../lib/contact";
import { tieLast } from "../../lib/tie";

type Errors = { email?: string; message?: string };

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const CONTROL_CLASS =
  "w-full p-tight border border-line-strong bg-surface text-heading leading-[1.4] aria-invalid:border-error aria-invalid:shadow-[inset_0_0_0_1px_var(--error)]";
const LABEL_CLASS = "font-medium text-heading";
const ERROR_CLASS = "font-medium text-error type-small";
const BUTTON_CLASS =
  "type-button inline-flex h-14 w-50 max-w-full items-center justify-center justify-self-center border border-heading text-heading transition-colors duration-150 ease-[cubic-bezier(0.2,0.7,0.2,1)] hover:bg-heading hover:text-bg";

const SUCCESS_TEXT = tieLast("Thanks — Rachel will get back to you.");

function focusOnMount(element: HTMLElement | null): void {
  element?.focus();
}

function text(value: FormDataEntryValue | null): string {
  return typeof value === "string" ? value : "";
}

function validate(email: string, message: string): Errors {
  const errors: Errors = {};
  if (email === "") errors.email = "Enter your email address.";
  else if (!EMAIL_PATTERN.test(email))
    errors.email = "Enter an email address like name@example.com.";
  if (message.trim() === "") errors.message = "Write a message.";
  return errors;
}

export function ContactForm({
  sendAction,
}: {
  sendAction: (formData: FormData) => Promise<ContactResult>;
}): ReactNode {
  const [errors, setErrors] = useState<Errors>({});
  const [sent, setSent] = useState(false);

  if (sent) {
    return (
      <p
        data-lead=""
        className="type-lead outline-none"
        role="status"
        tabIndex={-1}
        ref={focusOnMount}
      >
        {SUCCESS_TEXT}
      </p>
    );
  }

  async function onSubmit(
    event: SyntheticEvent<HTMLFormElement, SubmitEvent>,
  ): Promise<void> {
    event.preventDefault();
    const form = event.currentTarget;
    const formData = new FormData(form);
    const email = text(formData.get("email"));
    const message = text(formData.get("message"));
    const next = validate(email, message);
    setErrors(next);
    if (next.email !== undefined) {
      form.querySelector<HTMLElement>("#contact-email")?.focus();
      return;
    }
    if (next.message !== undefined) {
      form.querySelector<HTMLElement>("#contact-message")?.focus();
      return;
    }
    const result = await sendAction(formData);
    if (result.ok) setSent(true);
  }

  return (
    <form
      data-form=""
      noValidate
      aria-labelledby="contact-form-heading"
      className="grid gap-flow max-w-(--measure) mx-auto text-start"
      onSubmit={(event) => {
        void onSubmit(event);
      }}
    >
      <div className="grid gap-tight">
        <label htmlFor="contact-name" className={LABEL_CLASS}>
          Name
        </label>
        <input
          id="contact-name"
          name="name"
          type="text"
          autoComplete="name"
          className={CONTROL_CLASS}
        />
      </div>
      <div className="grid gap-tight">
        <label htmlFor="contact-email" className={LABEL_CLASS}>
          Email <span className="font-normal text-muted">(required)</span>
        </label>
        <input
          id="contact-email"
          name="email"
          type="email"
          autoComplete="email"
          required
          aria-invalid={errors.email === undefined ? undefined : true}
          aria-describedby={
            errors.email === undefined ? undefined : "contact-email-error"
          }
          className={CONTROL_CLASS}
        />
        {errors.email === undefined ? null : (
          <p id="contact-email-error" className={ERROR_CLASS}>
            {errors.email}
          </p>
        )}
      </div>
      <div className="grid gap-tight">
        <label htmlFor="contact-message" className={LABEL_CLASS}>
          Message <span className="font-normal text-muted">(required)</span>
        </label>
        <textarea
          id="contact-message"
          name="message"
          rows={6}
          required
          aria-invalid={errors.message === undefined ? undefined : true}
          aria-describedby={
            errors.message === undefined ? undefined : "contact-message-error"
          }
          className={`${CONTROL_CLASS} resize-y`}
        />
        {errors.message === undefined ? null : (
          <p id="contact-message-error" className={ERROR_CLASS}>
            {errors.message}
          </p>
        )}
      </div>
      <button type="submit" className={BUTTON_CLASS}>
        Send
      </button>
    </form>
  );
}
