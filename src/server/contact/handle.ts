import type { ContactResult } from "../../lib/contact";
import type { ContactConfig } from "./config";
import type { RateLimiter } from "./rate-limit";
import type { MailSender } from "./sender";

export type ContactDeps = {
  ip: string;
  config: ContactConfig | null;
  sender: MailSender;
  limiter: RateLimiter;
  log: (line: string) => void;
};

export const handleContact: (
  formData: FormData,
  deps: ContactDeps,
) => Promise<ContactResult> = () =>
  Promise.resolve({ ok: false, reason: "failed" });
