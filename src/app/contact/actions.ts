"use server";

export async function sendMessage(
  formData: FormData,
): Promise<{ ok: boolean }> {
  await Promise.resolve(formData);
  return { ok: false };
}
