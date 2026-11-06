// Gituar API Worker. Wecra'nın Worker'larından ve "designer" veritabanından tamamen ayrı.
import { bindings, defineConfig } from "cf/config";

import * as entrypoint from "./src/index.ts" with { type: "cf-worker" };

export default defineConfig({
  worker: {
    name: "gituar-api",
    entrypoint,
    compatibilityDate: "2026-11-06",
    workersDev: true,
    env: {
      DB: bindings.d1({ id: "da6f555c-b3cc-4fe0-970f-32b016631330", name: "gituar" }),
      FIREBASE_PROJECT_ID: bindings.text("koc-chords"),
      ALLOWED_ORIGINS: bindings.text("https://gituar.com,http://localhost:3000,http://localhost:4321"),
    },
  },
});
