// @vitest-environment happy-dom
import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { SiteFooter } from "./site-footer";

afterEach(() => {
  cleanup();
  vi.useRealTimers();
});

describe("SiteFooter", () => {
  it("shows the copyright line for the current year", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2031-06-15T12:00:00Z"));
    render(await SiteFooter());
    const first = screen.queryAllByRole("contentinfo");
    expect(first).toHaveLength(1);
    expect(first[0].textContent).toBe("© 2031 Rachel Siegel");

    cleanup();
    vi.setSystemTime(new Date("2027-03-01T12:00:00Z"));
    render(await SiteFooter());
    const second = screen.queryAllByRole("contentinfo");
    expect(second).toHaveLength(1);
    expect(second[0].textContent).toBe("© 2027 Rachel Siegel");
  });
});
