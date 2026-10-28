// Squad Tasks — Edge Function واحدة (الصقها كما هي في Supabase > Edge Functions)
// الأسرار المطلوبة (Secrets): ADMIN_CODE, ADMIN_AUTH_PASSWORD, CODE_PEPPER
// المتغيرات التالية يوفرها Supabase تلقائيًا: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const EMAIL_DOMAIN = "squad-tasks.example.com";
const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // 32 حرفًا بدون الحروف المتشابهة
const MAX_FAILED = 8; // محاولات فاشلة لكل IP خلال 15 دقيقة

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const noSession = { persistSession: false, autoRefreshToken: false };
const db = createClient(SUPABASE_URL, SERVICE_KEY, { auth: noSession });
const anonClient = () => createClient(SUPABASE_URL, ANON_KEY, { auth: noSession });

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

// ---------- أدوات التشفير ----------
const enc = new TextEncoder();

function hex(buf: ArrayBuffer | Uint8Array) {
  const u = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  return [...u].map((b) => b.toString(16).padStart(2, "0")).join("");
}
async function sha256(s: string) {
  return hex(await crypto.subtle.digest("SHA-256", enc.encode(s)));
}
async function hmac(key: string, msg: string) {
  const k = await crypto.subtle.importKey(
    "raw", enc.encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  return hex(await crypto.subtle.sign("HMAC", k, enc.encode(msg)));
}
async function safeEqual(a: string, b: string) {
  const [x, y] = await Promise.all([sha256(a), sha256(b)]);
  let d = 0;
  for (let i = 0; i < x.length; i++) d |= x.charCodeAt(i) ^ y.charCodeAt(i);
  return d === 0;
}
const normalize = (s: string) => s.toUpperCase().replace(/[^A-Z0-9]/g, "");
const randomSecret = () => hex(crypto.getRandomValues(new Uint8Array(32)));

function randomCode() {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  const chars = [...bytes].map((b) => ALPHABET[b & 31]); // 256 يقبل القسمة على 32 فلا انحياز
  return [0, 4, 8, 12].map((i) => chars.slice(i, i + 4).join("")).join("-");
}

// ---------- تحديد المحاولات ----------
async function clientKey(req: Request) {
  const ip = (req.headers.get("x-forwarded-for") ?? "unknown").split(",")[0].trim();
  return (await sha256(ip + (Deno.env.get("CODE_PEPPER") ?? ""))).slice(0, 32);
}
async function tooMany(kind: string, key: string) {
  const since = new Date(Date.now() - 15 * 60 * 1000).toISOString();
  const { count } = await db.from("login_attempts")
    .select("id", { count: "exact", head: true })
    .eq("kind", kind).eq("identifier", key).eq("success", false).gte("created_at", since);
  return (count ?? 0) >= MAX_FAILED;
}
async function record(kind: string, key: string, success: boolean) {
  await db.from("login_attempts").insert({ kind, identifier: key, success });
}
async function audit(actor: string, action: string, kind: string, id: string, details = {}) {
  await db.from("audit_log").insert({
    actor_id: actor, action, target_kind: kind, target_id: id, details,
  });
}

// ---------- مساعدات ----------
async function signIn(email: string, password: string) {
  const { data, error } = await anonClient().auth.signInWithPassword({ email, password });
  if (error || !data.session) throw new Error("signin_failed");
  return data.session.refresh_token;
}

async function issueCode(playerId: string): Promise<string | null> {
  const pepper = Deno.env.get("CODE_PEPPER") ?? "";
  for (let i = 0; i < 5; i++) {
    const code = randomCode();
    const hash = await hmac(pepper, normalize(code));
    const { error } = await db.from("player_access_codes").insert({
      player_id: playerId, code_hash: hash,
    });
    if (!error) return code;
    if (error.code !== "23505") return null; // غير تكرار الكود: فشل حقيقي
  }
  return null;
}

async function killAccess(playerId: string) {
  await db.from("player_access_codes")
    .update({ revoked_at: new Date().toISOString() })
    .eq("player_id", playerId).is("revoked_at", null);
  await db.rpc("revoke_player_sessions", { p_player_id: playerId });
}

async function requireAdmin(req: Request): Promise<string | null> {
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return null;
  const { data, error } = await db.auth.getUser(auth.slice(7));
  if (error || !data.user) return null;
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    auth: noSession, global: { headers: { Authorization: auth } },
  });
  const { data: ok } = await userClient.rpc("is_admin"); // يتحقق من الدور والجلسة الحيّة
  return ok === true ? data.user.id : null;
}

async function getPlayer(id: unknown) {
  if (typeof id !== "string") return null;
  const { data } = await db.from("profiles").select("id, display_name, role")
    .eq("id", id).eq("role", "player").maybeSingle();
  return data;
}

// ---------- الإجراءات ----------
async function adminLogin(req: Request, body: Record<string, unknown>) {
  const key = await clientKey(req);
  if (await tooMany("admin", key)) return json({ error: "too_many_attempts" }, 429);

  const expected = normalize(Deno.env.get("ADMIN_CODE") ?? "");
  const pass = Deno.env.get("ADMIN_AUTH_PASSWORD") ?? "";
  if (!expected || pass.length < 16) return json({ error: "server_misconfigured" }, 500);

  const code = normalize(String(body.code ?? ""));
  const ok = code.length > 0 && await safeEqual(code, expected);
  await record("admin", key, ok);
  if (!ok) return json({ error: "invalid_code" }, 401);

  const { data: existing } = await db.from("profiles").select("id").eq("role", "admin").maybeSingle();
  let email = `admin@${EMAIL_DOMAIN}`;
  if (existing) {
    const { data, error } = await db.auth.admin.updateUserById(existing.id, { password: pass });
    if (error || !data.user?.email) return json({ error: "server_error" }, 500);
    email = data.user.email;
  } else {
    const { data, error } = await db.auth.admin.createUser({
      email, password: pass, email_confirm: true,
    });
    if (error || !data.user) return json({ error: "server_error" }, 500);
    const { error: pe } = await db.from("profiles").insert({
      id: data.user.id, display_name: "الأدمن", role: "admin",
    });
    if (pe) {
      await db.auth.admin.deleteUser(data.user.id);
      return json({ error: "server_error" }, 500);
    }
  }
  return json({ refresh_token: await signIn(email, pass) });
}

async function playerLogin(req: Request, body: Record<string, unknown>) {
  const key = await clientKey(req);
  if (await tooMany("player", key)) return json({ error: "too_many_attempts" }, 429);

  const pepper = Deno.env.get("CODE_PEPPER") ?? "";
  if (pepper.length < 16) return json({ error: "server_misconfigured" }, 500);

  const code = normalize(String(body.code ?? ""));
  const fail = async () => { await record("player", key, false); return json({ error: "invalid_code" }, 401); };
  if (code.length !== 16) return await fail();

  const hash = await hmac(pepper, code);
  const { data: row } = await db.from("player_access_codes")
    .select("id, player_id, expires_at, profiles!inner(is_active, role)")
    .eq("code_hash", hash).is("revoked_at", null).maybeSingle();
  // deno-lint-ignore no-explicit-any
  const prof = (row as any)?.profiles;
  const p = Array.isArray(prof) ? prof[0] : prof;
  if (!row || !p || !p.is_active || p.role !== "player") return await fail();
  if (row.expires_at && new Date(row.expires_at) <= new Date()) return await fail();

  const password = randomSecret();
  const { data: u, error } = await db.auth.admin.updateUserById(row.player_id, { password });
  if (error || !u.user?.email) return json({ error: "server_error" }, 500);

  const refresh = await signIn(u.user.email, password);
  await db.from("player_access_codes").update({ last_used_at: new Date().toISOString() }).eq("id", row.id);
  await record("player", key, true);
  return json({ refresh_token: refresh });
}

async function createPlayer(adminId: string, body: Record<string, unknown>) {
  const name = String(body.name ?? "").trim();
  if (name.length < 2 || name.length > 40) return json({ error: "invalid_name" }, 400);
  const avatar = body.avatar_path == null ? null : String(body.avatar_path);
  if (avatar !== null && !/^players\/[0-9a-f-]{36}\.(jpg|png|webp)$/.test(avatar)) {
    return json({ error: "invalid_avatar" }, 400);
  }

  const { data, error } = await db.auth.admin.createUser({
    email: `p-${crypto.randomUUID()}@${EMAIL_DOMAIN}`,
    password: randomSecret(),
    email_confirm: true,
  });
  if (error || !data.user) return json({ error: "server_error" }, 500);
  const id = data.user.id;

  const { error: pe } = await db.from("profiles").insert({
    id, display_name: name, avatar_path: avatar, role: "player",
  });
  if (pe) {
    await db.auth.admin.deleteUser(id);
    return json({ error: "server_error" }, 500);
  }
  const code = await issueCode(id);
  if (!code) {
    await db.auth.admin.deleteUser(id); // يحذف البروفايل تلقائيًا (cascade)
    return json({ error: "server_error" }, 500);
  }
  await audit(adminId, "create_player", "player", id, { name });
  return json({ player_id: id, code });
}

async function regenerateCode(adminId: string, body: Record<string, unknown>) {
  const player = await getPlayer(body.player_id);
  if (!player) return json({ error: "not_found" }, 404);
  await killAccess(player.id);
  const code = await issueCode(player.id);
  if (!code) return json({ error: "server_error" }, 500);
  await audit(adminId, "regenerate_code", "player", player.id);
  return json({ code });
}

async function revokeCode(adminId: string, body: Record<string, unknown>) {
  const player = await getPlayer(body.player_id);
  if (!player) return json({ error: "not_found" }, 404);
  await killAccess(player.id);
  await audit(adminId, "revoke_code", "player", player.id);
  return json({ ok: true });
}

async function setActive(adminId: string, body: Record<string, unknown>) {
  const player = await getPlayer(body.player_id);
  if (!player || typeof body.is_active !== "boolean") return json({ error: "not_found" }, 404);
  await db.from("profiles").update({ is_active: body.is_active }).eq("id", player.id);
  if (!body.is_active) await db.rpc("revoke_player_sessions", { p_player_id: player.id });
  await audit(adminId, body.is_active ? "activate_player" : "deactivate_player", "player", player.id);
  return json({ ok: true });
}

// ---------- الموجّه ----------
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "bad_request" }, 400); }

  try {
    switch (body.action) {
      case "admin_login": return await adminLogin(req, body);
      case "player_login": return await playerLogin(req, body);
      case "create_player":
      case "regenerate_code":
      case "revoke_code":
      case "set_active": {
        const adminId = await requireAdmin(req);
        if (!adminId) return json({ error: "forbidden" }, 403);
        if (body.action === "create_player") return await createPlayer(adminId, body);
        if (body.action === "regenerate_code") return await regenerateCode(adminId, body);
        if (body.action === "revoke_code") return await revokeCode(adminId, body);
        return await setActive(adminId, body);
      }
      default: return json({ error: "unknown_action" }, 400);
    }
  } catch (e) {
    console.error(e);
    return json({ error: "server_error" }, 500);
  }
});
