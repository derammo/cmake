import { defineConfig } from "vitest/config";

// the cmake build sets DERAMMO_JUNIT_FILE to collect JUnit XML from every test it runs
const junitFile = process.env["DERAMMO_JUNIT_FILE"];

export default defineConfig({
  css: {
    // avoid spurious throw/catch in success path
    postcss: {},
  },
  test: {
    include: ["src/**/*.test.ts", "test/**/*.ts"],
    exclude: ["**/node_modules/**", "test/fixtures/**", "test/support/**"],
    reporters: junitFile ? ["default", ["junit", { outputFile: junitFile }]] : ["default"],
  },
});
