"use server";

export async function sendMessage(
  formData: FormData,
): Promise<{ ok: boolean }> {
  return await Promise.reject(
    new Error(`sendMessage is not built: ${typeof formData}`),
  );
}
