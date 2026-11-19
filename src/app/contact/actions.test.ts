import { describe, expect, it } from "vitest";
import { sendMessage } from "./actions";

describe("sendMessage", () => {
  it("reports failure until sending is built", async () => {
    const filled = new FormData();
    filled.set("name", "Ada Lovelace");
    filled.set("email", "ada@example.com");
    filled.set("message", "Hello Rachel");
    const actions = await import("./actions");

    await expect(sendMessage(filled)).resolves.toStrictEqual({ ok: false });
    await expect(sendMessage(new FormData())).resolves.toStrictEqual({
      ok: false,
    });
    expect(Object.keys(actions).sort()).toEqual(["sendMessage"]);
  });
});
