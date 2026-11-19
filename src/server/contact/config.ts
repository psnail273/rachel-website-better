export type ContactConfig = { apiKey: string; to: string; from: string };

function value(
  env: Readonly<Record<string, string | undefined>>,
  name: string,
): string {
  return (env[name] ?? "").trim();
}

// The one place that reads the contact form's environment variables.
export function parseContactConfig(
  env: Readonly<Record<string, string | undefined>>,
): ContactConfig | null {
  const apiKey = value(env, "RESEND_API_KEY");
  const to = value(env, "CONTACT_TO_EMAIL");
  const from = value(env, "CONTACT_FROM_EMAIL");
  if (apiKey === "" || to === "" || from === "") return null;
  return { apiKey, to, from };
}
