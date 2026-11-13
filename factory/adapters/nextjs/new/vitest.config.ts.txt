import { defineConfig } from "vitest/config";

export default defineConfig({
  resolve: { tsconfigPaths: true },
  test: {
    include: ["**/*.test.ts", "**/*.test.tsx"],
    exclude: [
      "**/node_modules/**",
      ".next/**",
      ".stryker-tmp/**",
      "factory/**",
      "tools/**",
      "scenarios/**",
    ],
  },
});
