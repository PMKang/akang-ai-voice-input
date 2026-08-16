import type { D1Migration } from "cloudflare:test";

declare global {
  namespace Cloudflare {
    interface Env {
      TEST_MIGRATIONS: D1Migration[];
    }
  }
  interface Env {
    TEST_MIGRATIONS: D1Migration[];
  }
}

export {};
