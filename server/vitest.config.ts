import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";
const nodeTests = ["authVerificationReuse", "authSignedTokens"].map(
  (name) => `tests/${name}.test.ts`,
);
export default defineConfig({
  resolve: { alias: { "@": fileURLToPath(new URL(".", import.meta.url)) } },
  test: {
    restoreMocks: true,
    projects: [
      { extends: true, test: { name: "node", environment: "node", include: nodeTests } },
      {
        extends: true,
        test: {
          name: "edge",
          environment: "edge-runtime",
          include: ["tests/**/*.test.ts"],
          exclude: nodeTests,
        },
      },
    ],
  },
});
