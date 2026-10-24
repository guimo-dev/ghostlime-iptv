// Edge Function `key-escrow`: keeps the sync data key of accounts that sign in
// with Google, so they never have to type a sync password.
//
// The app calls it with the user's session token (`Authorization: Bearer <jwt>`).
// The token is verified with Supabase Auth and the user id comes only from it.
//   GET -> 200 `{ key }` (base64 of the 32-byte data key) or 404 when none is kept.
//   PUT `{ key }` -> 200 when stored; 409 when a key is already kept or the
//       account has a password profile (it stays end-to-end).
// The key is stored in `profiles.escrowed_key` encrypted with AES-256-GCM under
// the function secret KEY_ESCROW_SECRET (32 bytes, base64), with the user id as
// associated data, so a copied value does not open for another user. Keys,
// tokens and request bodies are never logged.
import { createClient } from "npm:@supabase/supabase-js@2.118.0";

const nonceLength = 12;
const keyLength = 32;

/** Answers with a JSON body and [status]. */
function reply(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** Bytes of the base64 text [text]; throws on invalid base64. */
function fromBase64(text: string): Uint8Array {
  return Uint8Array.from(atob(text), (c) => c.charCodeAt(0));
}

/** Base64 text of [bytes]. */
function toBase64(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes));
}

/** The AES-GCM key from KEY_ESCROW_SECRET, or null when it is missing or not 32 bytes. */
async function escrowKey(): Promise<CryptoKey | null> {
  const secret = Deno.env.get("KEY_ESCROW_SECRET");
  if (!secret) return null;
  let raw: Uint8Array;
  try {
    raw = fromBase64(secret);
  } catch {
    return null;
  }
  if (raw.length !== keyLength) return null;
  return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
}

/** Associated data that ties a stored value to [userId]. */
function aadFor(userId: string): Uint8Array {
  return new TextEncoder().encode(`ghostlime-key-escrow:v1:${userId}`);
}

/** base64(nonce | ciphertext | tag) of [dataKey] for [userId]. */
async function seal(secret: CryptoKey, userId: string, dataKey: Uint8Array): Promise<string> {
  const nonce = crypto.getRandomValues(new Uint8Array(nonceLength));
  const sealed = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: "AES-GCM", iv: nonce, additionalData: aadFor(userId) },
      secret,
      dataKey,
    ),
  );
  const out = new Uint8Array(nonce.length + sealed.length);
  out.set(nonce);
  out.set(sealed, nonce.length);
  return toBase64(out);
}

/** The data key in [stored] (from [seal]) for [userId]; throws if it does not open. */
async function open(secret: CryptoKey, userId: string, stored: string): Promise<Uint8Array> {
  const bytes = fromBase64(stored);
  const plain = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: bytes.slice(0, nonceLength), additionalData: aadFor(userId) },
    secret,
    bytes.slice(nonceLength),
  );
  return new Uint8Array(plain);
}

/** The 32-byte data key in a PUT body `{ key }`, or null when it is not one. */
async function keyFromBody(request: Request): Promise<Uint8Array | null> {
  try {
    const body = await request.json();
    if (typeof body?.key !== "string") return null;
    const key = fromBase64(body.key);
    return key.length === keyLength ? key : null;
  } catch {
    return null;
  }
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== "GET" && request.method !== "PUT") {
    return reply(405, { error: "method_not_allowed" });
  }

  const jwt = (request.headers.get("Authorization") ?? "")
    .replace(/^Bearer\s+/i, "")
    .trim();
  if (!jwt) return reply(401, { error: "unauthorized" });

  // SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { data, error: tokenError } = await admin.auth.getUser(jwt);
  if (tokenError || !data.user) return reply(401, { error: "unauthorized" });
  const userId = data.user.id;

  const secret = await escrowKey();
  if (!secret) return reply(500, { error: "not_configured" });

  if (request.method === "GET") {
    const { data: row, error } = await admin
      .from("profiles")
      .select("escrowed_key")
      .eq("user_id", userId)
      .maybeSingle();
    if (error) return reply(500, { error: "read_failed" });
    if (!row?.escrowed_key) return reply(404, { error: "not_found" });
    try {
      return reply(200, { key: toBase64(await open(secret, userId, row.escrowed_key)) });
    } catch {
      return reply(500, { error: "unreadable" });
    }
  }

  const dataKey = await keyFromBody(request);
  if (!dataKey) return reply(400, { error: "bad_key" });
  const escrowed = await seal(secret, userId, dataKey);

  // Only into an empty slot of a row without a password profile: a kept key
  // is never replaced, and an end-to-end account never gets one.
  const { data: updated, error: updateError } = await admin
    .from("profiles")
    .update({ escrowed_key: escrowed })
    .eq("user_id", userId)
    .is("escrowed_key", null)
    .is("wrapped_key", null)
    .select("user_id");
  if (updateError) return reply(500, { error: "write_failed" });
  if (updated.length > 0) return reply(200, { ok: true });

  // No row to fill: create it, unless one exists (kept key or password).
  const { error: insertError } = await admin
    .from("profiles")
    .insert({ user_id: userId, escrowed_key: escrowed });
  if (insertError?.code === "23505") return reply(409, { error: "already_set" });
  if (insertError) return reply(500, { error: "write_failed" });
  return reply(200, { ok: true });
});
