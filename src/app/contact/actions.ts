"use server";

export async function sendMessage(
  _formData: FormData,
): Promise<{ ok: boolean }> {
  return await Promise.resolve({ ok: false });
}
