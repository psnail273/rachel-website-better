export type ContactConfig = { apiKey: string; to: string; from: string };

export const parseContactConfig: (
  env: Readonly<Record<string, string | undefined>>,
) => ContactConfig | null = () => null;
