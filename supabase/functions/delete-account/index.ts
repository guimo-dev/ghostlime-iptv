// Edge Function `delete-account`: deletes the calling user and all their data
// (the foreign keys cascade to `profiles` and `sync_items`).
//
// The app calls it with the user's session token (`Authorization: Bearer <jwt>`).
// The token is verified with Supabase Auth and only THAT user is deleted; the
// service role key never leaves the function. Nothing sensitive is logged.
import { createClient } from "npm:@supabase/supabase-js@2.118.0";

/** Answers with a JSON body `{ error }` (or `{ ok: true }`) and [status]. */
function reply(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== "POST") return reply(405, { error: "method_not_allowed" });

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

  // profiles and sync_items go with the user (`on delete cascade` in
  // schema.sql), atomically: a failure here leaves the account whole.
  const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
  if (deleteError) return reply(500, { error: "delete_failed" });

  return reply(200, { ok: true });
});
