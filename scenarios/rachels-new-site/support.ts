// Shared by the Scenarios of "Rachel's new site". Declares no test.
import { expect, type Locator, type Page } from "@playwright/test";

// tabTo: press Tab, as a keyboard visitor does, until the target has focus.
export async function tabTo(page: Page, target: Locator, most = 40) {
  for (let i = 0; i < most; i++) {
    await page.keyboard.press("Tab");
    if (await target.evaluate((el) => el === document.activeElement)) return;
  }
  await expect(target, `Tab reaches it within ${most} presses`).toBeFocused();
}
