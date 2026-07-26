import { Context, Next } from 'hono';
import type { AppEnv } from '../types';

interface JWTPayload {
  sub: string;
  tenant_id: string;
  role: string;
  iat: number;
  exp: number;
}

export const authMiddleware = async (c: Context<AppEnv>, next: Next) => {
  const authHeader = c.req.header('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return c.json({ error: 'Unauthorized', message: 'Missing or invalid Authorization header' }, 401);
  }

  const token = authHeader.slice(7);

  try {
    const parts = token.split('.');
    if (parts.length !== 3) {
      return c.json({ error: 'Unauthorized', message: 'Malformed token' }, 401);
    }

    const encoder = new TextEncoder();
    const key = await crypto.subtle.importKey(
      'raw', encoder.encode(c.env.JWT_SECRET),
      { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']
    );

    const signatureInput = `${parts[0]}.${parts[1]}`;
    const signature = base64UrlDecode(parts[2]);

    const valid = await crypto.subtle.verify('HMAC', key, signature, encoder.encode(signatureInput));
    if (!valid) {
      return c.json({ error: 'Unauthorized', message: 'Invalid token signature' }, 401);
    }

    const payload: JWTPayload = JSON.parse(
      new TextDecoder().decode(base64UrlDecode(parts[1]))
    );

    // FIX 4: Reject tokens without exp claim — tokens MUST expire
    if (!payload.exp || Date.now() / 1000 > payload.exp) {
      return c.json({ error: 'Unauthorized', message: 'Token expired' }, 401);
    }

    // FIX 4: Validate required claims exist
    if (!payload.sub || !payload.tenant_id) {
      return c.json({ error: 'Unauthorized', message: 'Token missing required claims' }, 401);
    }

    c.set('user', payload);
    await next();
  } catch (err) {
    console.error('[AUTH] Token verification failed:', err);
    return c.json({ error: 'Unauthorized', message: 'Token verification failed' }, 401);
  }
};

export async function generateJWT(
  payload: Omit<JWTPayload, 'iat' | 'exp'>,
  secret: string,
  expiresInSeconds = 86400
): Promise<string> {
  const header = { alg: 'HS256', typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const fullPayload: JWTPayload = { ...payload, iat: now, exp: now + expiresInSeconds };

  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(fullPayload));
  const signatureInput = `${encodedHeader}.${encodedPayload}`;

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw', encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );

  const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(signatureInput));
  const encodedSignature = base64UrlEncode(String.fromCharCode(...new Uint8Array(signature)));

  return `${encodedHeader}.${encodedPayload}.${encodedSignature}`;
}

function base64UrlEncode(str: string): string {
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64UrlDecode(str: string): Uint8Array {
  const base64 = str.replace(/-/g, '+').replace(/_/g, '/');
  const padded = base64 + '='.repeat((4 - base64.length % 4) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}
