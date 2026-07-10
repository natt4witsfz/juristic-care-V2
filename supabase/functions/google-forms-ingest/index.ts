import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// CORS allowlist (Stage 0): no wildcard. Configure ALLOWED_ORIGINS as a
// comma-separated list. This webhook is normally called server-to-server by
// Apps Script (no Origin header), so browser CORS rarely applies here.
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
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-ingest-secret",
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

  // Fail-closed: if no ingest secret is configured, reject every request.
  const expectedSecret = Deno.env.get("GOOGLE_FORMS_INGEST_SECRET") || "";
  if (!expectedSecret) return json({ error: "SERVER_NOT_CONFIGURED" }, 500, cors);
  const providedSecret = req.headers.get("x-ingest-secret") || "";
  if (providedSecret !== expectedSecret) return json({ error: "FORBIDDEN" }, 403, cors);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  if (!supabaseUrl || !serviceRoleKey) return json({ error: "SERVER_NOT_CONFIGURED" }, 500, cors);

  const serviceClient = createClient(supabaseUrl, serviceRoleKey);
  const payload = await req.json().catch(() => ({}));
  const externalId = String(payload.external_id || payload.externalId || payload.timestamp || crypto.randomUUID());

  // NOTE (Stage 2): this direct table write will be replaced by the
  // transactional RPC `ingest_google_form_submission(...)` (Amendment 1).
  const { data: submission, error: submissionError } = await serviceClient
    .from("google_form_submissions")
    .upsert({
      external_id: externalId,
      status: "new",
      payload
    }, { onConflict: "external_id" })
    .select("*")
    .single();
  if (submissionError) return json({ error: submissionError.message }, 400, cors);

  const jobId = payload.job_id || `GF-${new Date().toISOString().slice(2, 10).replaceAll("-", "")}-${String(Date.now()).slice(-4)}`;
  const jobPayload = {
    id: jobId,
    source: "Google Form",
    raw: true,
    title: payload.title || payload.issue || payload.description || "Google Form Submission",
    roomNo: payload.roomNo || payload.room_no || payload.room || "",
    issueDescription: payload.description || payload.issue || "",
    contactName: payload.contactName || payload.contact_name || "",
    contactPhone: payload.contactPhone || payload.contact_phone || "",
    status: "open",
    priority: payload.priority || "normal",
    mainCategory: payload.mainCategory || "resident",
    category: payload.category || "building",
    date: new Date().toISOString().slice(0, 10),
    formSubmissionId: submission.id
  };

  const { error: jobError } = await serviceClient
    .from("jobs")
    .upsert({
      id: jobId,
      source: "Google Form",
      status: "open",
      payload: jobPayload
    }, { onConflict: "id" });
  if (jobError) return json({ error: jobError.message }, 400, cors);

  await serviceClient
    .from("google_form_submissions")
    .update({ status: "converted", job_id: jobId, processed_at: new Date().toISOString() })
    .eq("id", submission.id);

  await serviceClient.from("audit_logs").insert({
    actor_role: "system",
    action: "GOOGLE_FORM_INGESTED",
    detail: jobId,
    payload: { submission_id: submission.id, external_id: externalId }
  });

  return json({ ok: true, submissionId: submission.id, jobId }, 200, cors);
});
