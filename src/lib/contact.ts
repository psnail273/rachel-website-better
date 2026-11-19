export type ContactErrors = { email?: string; message?: string };

export type ContactResult =
  | { ok: true }
  | { ok: false; reason: "invalid"; errors: ContactErrors }
  | { ok: false; reason: "rate-limited" }
  | { ok: false; reason: "failed" };

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const EMAIL_MAX = 254;
const MESSAGE_MAX = 5000;

// The same rules for the form in the browser and for the server action.
export function validateContact(fields: {
  email: string;
  message: string;
}): ContactErrors {
  const email = fields.email.trim();
  const message = fields.message.trim();
  const errors: ContactErrors = {};
  if (email === "") errors.email = "Enter your email address.";
  else if (email.length > EMAIL_MAX || !EMAIL_PATTERN.test(email))
    errors.email = "Enter an email address like name@example.com.";
  if (message === "") errors.message = "Write a message.";
  else if (message.length > MESSAGE_MAX)
    errors.message = "Keep your message under 5,000 characters.";
  return errors;
}
