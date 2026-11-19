"use server";

import { headers } from "next/headers";
import type { ContactResult } from "../../lib/contact";
import { parseContactConfig } from "../../server/contact/config";
import { handleContact } from "../../server/contact/handle";
import { clientIp, createRateLimiter } from "../../server/contact/rate-limit";
import { createResendSender } from "../../server/contact/sender";

const limiter = createRateLimiter(() => Date.now());

export async function sendMessage(formData: FormData): Promise<ContactResult> {
  const requestHeaders = await headers();
  const config = parseContactConfig(process.env);
  return handleContact(formData, {
    ip: clientIp(requestHeaders),
    config,
    sender: createResendSender(config === null ? "" : config.apiKey),
    limiter,
    log: (line) => {
      console.error(line);
    },
  });
}
