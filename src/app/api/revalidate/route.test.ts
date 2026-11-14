import { revalidatePath } from "next/cache";
import { afterEach, describe, expect, it, vi } from "vitest";
import { POST } from "./route";

vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("POST /api/revalidate", () => {
  it("revalidates every page when ON_DEMAND_REVALIDATION is 1", async () => {
    vi.stubEnv("ON_DEMAND_REVALIDATION", "1");
    const response = POST();
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ revalidated: true });
    expect(revalidatePath).toHaveBeenCalledTimes(1);
    expect(revalidatePath).toHaveBeenCalledWith("/", "layout");
  });

  it("answers 404 and revalidates nothing when ON_DEMAND_REVALIDATION is unset", () => {
    vi.stubEnv("ON_DEMAND_REVALIDATION", undefined);
    const response = POST();
    expect(response.status).toBe(404);
    expect(revalidatePath).not.toHaveBeenCalled();
  });

  it.each(["", "0", "true", "yes"])(
    "answers 404 and revalidates nothing when ON_DEMAND_REVALIDATION is %j",
    (value) => {
      vi.stubEnv("ON_DEMAND_REVALIDATION", value);
      const response = POST();
      expect(response.status).toBe(404);
      expect(revalidatePath).not.toHaveBeenCalled();
    },
  );
});
