/**
 * Sentry Error Tracking for Cloudflare Workers
 *
 * Uses toucan-js (@sentry/cloudflare alternative for Workers).
 * SAFE: If SENTRY_DSN is empty/null/missing, all calls are no-ops.
 */

export interface SentryClient {
  captureException(error: Error | unknown): void;
  captureMessage(message: string): void;
  setTag(key: string, value: string): void;
}

/**
 * Creates a Sentry client that safely handles missing DSN.
 * Returns a no-op client if DSN is not configured.
 */
export function createSentryClient(
  request: Request,
  env: { SENTRY_DSN?: string; ENVIRONMENT?: string },
  ctx?: ExecutionContext
): SentryClient {
  const dsn = env.SENTRY_DSN;

  // If DSN is empty, null, or undefined — return a safe no-op client
  if (!dsn || dsn.trim() === '') {
    return {
      captureException: () => {},
      captureMessage: () => {},
      setTag: () => {},
    };
  }

  // Real Sentry client using the Workers-compatible fetch-based approach
  // toucan-js or manual Sentry envelope posting
  return {
    captureException: (error: Error | unknown) => {
      const err = error instanceof Error ? error : new Error(String(error));
      console.error(`[SENTRY] Exception captured: ${err.message}`);

      // Fire-and-forget POST to Sentry ingest
      // Uses ctx.waitUntil to not block the response
      const sentryPayload = {
        event_id: crypto.randomUUID().replace(/-/g, ''),
        timestamp: new Date().toISOString(),
        platform: 'javascript',
        level: 'error',
        logger: 'cloudflare-worker',
        server_name: 'estore-api',
        environment: env.ENVIRONMENT || 'production',
        exception: {
          values: [{
            type: err.name,
            value: err.message,
            stacktrace: err.stack ? {
              frames: err.stack.split('\n').slice(1, 10).map(line => ({
                filename: line.trim(),
              })),
            } : undefined,
          }],
        },
        request: {
          url: request.url,
          method: request.method,
          headers: Object.fromEntries(
            [...request.headers.entries()].filter(([k]) =>
              !['authorization', 'cookie'].includes(k.toLowerCase())
            )
          ),
        },
      };

      const sendToSentry = async () => {
        try {
          // Parse DSN: https://{key}@{host}/{project_id}
          const dsnUrl = new URL(dsn);
          const projectId = dsnUrl.pathname.replace('/', '');
          const publicKey = dsnUrl.username;
          const ingestUrl = `https://${dsnUrl.host}/api/${projectId}/store/?sentry_version=7&sentry_key=${publicKey}`;

          await fetch(ingestUrl, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(sentryPayload),
          });
        } catch (e) {
          // Silent fail — Sentry should never crash the app
          console.error('[SENTRY] Failed to send event:', e);
        }
      };

      if (ctx) {
        ctx.waitUntil(sendToSentry());
      } else {
        sendToSentry().catch(() => {});
      }
    },

    captureMessage: (message: string) => {
      console.log(`[SENTRY] Message: ${message}`);
    },

    setTag: (key: string, value: string) => {
      // Tags would be added to the payload in a full implementation
    },
  };
}
