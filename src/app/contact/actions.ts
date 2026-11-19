"use server";

import type { ContactResult } from "../../lib/contact";

export async function sendMessage(formData: FormData): Promise<ContactResult> {
  await Promise.resolve(formData);
  return { ok: false, reason: "failed" };
}
