import { validateContact, type ContactResult } from "../../lib/contact";
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

const NAME_MAX = 200;

function field(formData: FormData, name: string): string {
  const value = formData.get(name);
  return typeof value === "string" ? value : "";
}

export async function handleContact(
  formData: FormData,
  deps: ContactDeps,
): Promise<ContactResult> {
  if (field(formData, "company") !== "") return { ok: true };
  const name = field(formData, "name").trim().slice(0, NAME_MAX);
  const email = field(formData, "email").trim();
  const message = field(formData, "message").trim();
  const errors = validateContact({ email, message });
  if (errors.email !== undefined || errors.message !== undefined)
    return { ok: false, reason: "invalid", errors };
  if (!deps.limiter.take(deps.ip)) return { ok: false, reason: "rate-limited" };
  const { config } = deps;
  if (config === null) {
    deps.log("Contact form: not configured.");
    return { ok: false, reason: "failed" };
  }
  try {
    await deps.sender.send({
      from: config.from,
      to: config.to,
      replyTo: email,
      subject: `Website message from ${name === "" ? email : name}`,
      text: `${name === "" ? "" : `Name: ${name}\n`}Email: ${email}\n\n${message}`,
    });
  } catch (error) {
    deps.log(
      `Contact form: the send failed: ${error instanceof Error ? error.message : String(error)}`,
    );
    return { ok: false, reason: "failed" };
  }
  return { ok: true };
}
