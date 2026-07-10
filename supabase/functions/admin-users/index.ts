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

function loginIdToEmail(loginId = "") {
  const normalized = String(loginId)
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return `${normalized || "user"}@auth.juristic.local`;
}

// Server-side temporary password (Stage 0): replaces the hard-coded "1234".
function generateTempPassword(length = 12) {
  const letters = "ABCDEFGHJKMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz";
  const digits = "23456789";
  const all = letters + digits;
  const buf = new Uint32Array(length);
  crypto.getRandomValues(buf);
  const out: string[] = [
    letters[buf[0] % letters.length],
    digits[buf[1] % digits.length]
  ];
  for (let i = 2; i < length; i++) out.push(all[buf[i] % all.length]);
  return out.sort(() => (crypto.getRandomValues(new Uint32Array(1))[0] % 2 ? 1 : -1)).join("");
}

Deno.serve(async (req) => {
  const cors = corsHeaders(req);
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405, cors);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  if (!supabaseUrl || !serviceRoleKey) return json({ error: "SERVER_NOT_CONFIGURED" }, 500, cors);

  const authHeader = req.headers.get("Authorization") || "";
  const userClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY") || "", {
    global: { headers: { Authorization: authHeader } }
  });
  const serviceClient = createClient(supabaseUrl, serviceRoleKey);

  const { data: caller, error: callerError } = await userClient
    .from("app_users")
    .select("id, app_role, is_co_admin")
    .eq("is_active", true)
    .maybeSingle();
  if (callerError) return json({ error: callerError.message }, 400, cors);
  if (!caller || (caller.app_role !== "admin" && !caller.is_co_admin)) return json({ error: "FORBIDDEN" }, 403, cors);

  const body = await req.json().catch(() => ({}));
  const action = body.action || "create";
  const user = body.user || {};
  const loginId = String(user.login_id || user.loginId || body.loginId || "").trim().toUpperCase();
  // Generate a secure temporary password unless an explicit one is supplied.
  const providedPassword = String(body.password || user.password || "").trim();
  const password = providedPassword || generateTempPassword();
  const generated = !providedPassword;
  if (!loginId) return json({ error: "LOGIN_ID_REQUIRED" }, 400, cors);

  if (action === "create") {
    const email = loginIdToEmail(loginId);
    const { data: authUser, error: authError } = await serviceClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { login_id: loginId, must_change_password: true }
    });
    if (authError) return json({ error: authError.message }, 400, cors);

    const record = {
      auth_user_id: authUser.user.id,
      login_id: loginId,
      display_name: user.display_name || user.displayName || loginId,
      en_name: user.en_name || user.enName || user.display_name || loginId,
      first_name: user.first_name || user.firstName || "",
      last_name: user.last_name || user.lastName || "",
      nickname: user.nickname || user.nickName || "",
      position: user.position || "",
      phone: user.phone || "",
      app_role: user.app_role || user.role || "resident",
      department: user.department || "resident",
      role_key: user.role_key || user.roleKey || "",
      is_co_admin: !!(user.is_co_admin || user.isCoAdmin),
      assign_l1: !!(user.assign_l1 || user.assignL1),
      assign_l2: !!(user.assign_l2 || user.assignL2),
      can_assign: !!(user.can_assign || user.canAssign),
      permissions: user.permissions || {}
    };
    const { data, error } = await serviceClient.from("app_users").insert(record).select("*").single();
    if (error) return json({ error: error.message }, 400, cors);
    // Return the temp password only when generated so the admin can relay it once.
    return json({ ok: true, user: data, ...(generated ? { tempPassword: password } : {}) }, 200, cors);
  }

  if (action === "reset-password") {
    const email = loginIdToEmail(loginId);
    const { data: list, error: listError } = await serviceClient.auth.admin.listUsers();
    if (listError) return json({ error: listError.message }, 400, cors);
    const target = list.users.find((item) => item.email?.toLowerCase() === email);
    if (!target) return json({ error: "USER_NOT_FOUND" }, 404, cors);
    const { error } = await serviceClient.auth.admin.updateUserById(target.id, { password });
    if (error) return json({ error: error.message }, 400, cors);
    return json({ ok: true, ...(generated ? { tempPassword: password } : {}) }, 200, cors);
  }

  return json({ error: "UNKNOWN_ACTION" }, 400, cors);
});
