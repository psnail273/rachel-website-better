export type ContactErrors = { email?: string; message?: string };

export type ContactResult =
  | { ok: true }
  | { ok: false; reason: "invalid"; errors: ContactErrors }
  | { ok: false; reason: "rate-limited" }
  | { ok: false; reason: "failed" };

export const validateContact: (fields: {
  email: string;
  message: string;
}) => ContactErrors = () => ({});
