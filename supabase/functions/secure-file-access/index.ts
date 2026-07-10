import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// CORS allowlist (Stage 0): no wildcard. Configure ALLOWED_ORIGINS as a
// comma-separated list of trusted app origins.
const ALLOWED_ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") || "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

function corsHeaders(req: Request) {
  const origin = req.headers.get("Origin") || "";
  const allow = ALLOWED_ORIGINS.includes(origin) ? origin : (ALLOWED_ORIGINS[0] || "null");
  return {
    "Access-Control-Allow-Origin": allow,
    "Vary": "Origin",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS"
  };
}

function json(body: unknown, status: number, cors: Record<string, string>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" }
  });
}

Deno.serve(async (req) => {
  const cors = corsHeaders(req);
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405, cors);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  if (!supabaseUrl || !anonKey || !serviceRoleKey) return json({ error: "SERVER_NOT_CONFIGURED" }, 500, cors);

  const authHeader = req.headers.get("Authorization") || "";
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } }
  });
  const serviceClient = createClient(supabaseUrl, serviceRoleKey);
  const body = await req.json().catch(() => ({}));
  const bucket = String(body.bucket || "");
  const path = String(body.path || "");
  const expiresIn = Math.min(Math.max(Number(body.expiresIn || 600), 60), 3600);
  if (!bucket || !path) return json({ error: "BUCKET_AND_PATH_REQUIRED" }, 400, cors);

  const { data: allowed, error: allowedError } = await userClient.rpc("can_access_storage_object", {
    p_bucket: bucket,
    p_name: path
  });
  if (allowedError) return json({ error: allowedError.message }, 400, cors);
  if (!allowed) return json({ error: "FORBIDDEN" }, 403, cors);

  const { data, error } = await serviceClient.storage.from(bucket).createSignedUrl(path, expiresIn);
  if (error) return json({ error: error.message }, 400, cors);
  return json({ ok: true, signedUrl: data.signedUrl, expiresIn }, 200, cors);
});
