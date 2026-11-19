"use server";

export async function sendMessage(
  formData: FormData,
): Promise<{ ok: boolean }> {
  void formData;
  return await Promise.resolve({ ok: false });
}
