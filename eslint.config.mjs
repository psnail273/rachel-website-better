import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";
import tseslint from "typescript-eslint";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  // typescript-eslint's strict type-aware rules (ARCHITECTURE.md's lint: tags,
  // which the arch step checks are on), as the factory's skeleton has them.
  tseslint.configs.strictTypeChecked,
  {
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
  },
  {
    files: ["**/*.{js,mjs,cjs}"],
    extends: [tseslint.configs.disableTypeChecked],
  },
  // R11: type discipline in src/: no type assertions (`as`, `<T>`), no
  // non-null assertions, and a switch on a union handles every member.
  {
    files: ["src/**/*.{ts,tsx,mts,cts}"],
    rules: {
      "@typescript-eslint/consistent-type-assertions": [
        "error",
        { assertionStyle: "never" },
      ],
      "@typescript-eslint/no-non-null-assertion": "error",
      "@typescript-eslint/switch-exhaustiveness-check": "error",
    },
  },
  // R12: components outside app/_components/ stay pure: no effects, no raw HTML,
  // no bare fetch. Tests are exempt.
  {
    files: ["src/**/*.tsx"],
    ignores: ["src/app/_components/**", "**/*.test.tsx"],
    rules: {
      "no-restricted-syntax": [
        "error",
        {
          selector: "ImportSpecifier[imported.name='useEffect']",
          message: "R12: no useEffect outside src/app/_components/.",
        },
        {
          selector: "MemberExpression[property.name='useEffect']",
          message: "R12: no useEffect outside src/app/_components/.",
        },
        {
          selector:
            "CallExpression[callee.type='Identifier'][callee.name='fetch']",
          message: "R12: no bare fetch() in a component; fetch in src/server/.",
        },
      ],
      "react/no-danger": "error",
    },
  },
  // R13: no warning comments: fix it now, or file an issue.
  {
    rules: {
      "no-warning-comments": [
        "error",
        {
          terms: [
            "todo",
            "todos",
            "hack",
            "hacks",
            "fixme",
            "fixmes",
            "workaround",
            "workarounds",
          ],
          location: "anywhere",
        },
      ],
    },
  },
  // Override default ignores of eslint-config-next.
  globalIgnores([
    // Default ignores of eslint-config-next:
    ".next/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
  ]),
]);

export default eslintConfig;
