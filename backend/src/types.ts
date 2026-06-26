import type { Env as WorkerEnv } from './index';

/**
 * Hono context variables set by middleware.
 * This type enables type-safe `c.get()` and `c.set()` calls.
 */
export interface AppVariables {
  user: {
    sub: string;
    tenant_id: string;
    role: string;
    iat: number;
    exp: number;
  };
  tenant_id: string;
  user_id: string;
  user_role: string;
}

/**
 * Combined Hono environment type used across all routes.
 */
export type AppEnv = {
  Bindings: WorkerEnv;
  Variables: AppVariables;
};
