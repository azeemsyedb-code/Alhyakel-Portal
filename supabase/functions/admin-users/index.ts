// Supabase Edge Function: admin-users
// Creates / updates / blocks / deletes portal users. Only a signed-in portal admin may call it.
// Deploy: Supabase > Edge Functions > Deploy a new function > Via Editor > name "admin-users" > paste > Deploy.
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const ROLES: Record<string, string[]> = {
  docs_role: ["manager", "staff", "viewer"],
  inv_role: ["admin", "storekeeper", "viewer"],
  hr_role: ["admin", "supervisor", "viewer"],
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

function roles(b: Record<string, unknown>) {
  const out: Record<string, string | null> = {};
  for (const [k, allowed] of Object.entries(ROLES)) {
    const v = b[k];
    out[k] = typeof v === "string" && allowed.includes(v) ? v : null;
  }
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const domain = Deno.env.get("LOGIN_DOMAIN") ?? "alhyakel.local";
    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

    // who is calling?
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: { user }, error: userErr } = await admin.auth.getUser(token);
    if (userErr || !user) return json({ error: "Login expire ho gaya. Dobara login karein." }, 401);
    const { data: me } = await admin.from("portal_users").select("is_admin, active").eq("id", user.id).maybeSingle();
    if (!me?.is_admin || !me.active) return json({ error: "Yeh kaam sirf portal admin kar sakta hai." }, 403);

    const b = await req.json();
    const id = typeof b.id === "string" ? b.id : "";

    switch (b.action) {
      case "create": {
        const username = String(b.username ?? "").trim().toLowerCase();
        const fullName = String(b.full_name ?? "").trim() || username;
        const password = String(b.password ?? "");
        if (!/^[a-z0-9._-]{3,30}$/.test(username)) return json({ error: "User ID: 3-30 chhote English huroof, number, . _ -" }, 400);
        if (password.length < 8) return json({ error: "Password kam az kam 8 characters ka ho." }, 400);
        const { data: taken } = await admin.from("portal_users").select("id").eq("username", username).maybeSingle();
        if (taken) return json({ error: `User ID '${username}' pehle se maujood hai.` }, 400);
        const { data: created, error } = await admin.auth.admin.createUser({
          email: `${username}@${domain}`, password, email_confirm: true,
          user_metadata: { username, full_name: fullName },
        });
        if (error || !created.user) return json({ error: error?.message ?? "User nahi bana." }, 400);
        const { error: insErr } = await admin.from("portal_users").insert({
          id: created.user.id, username, full_name: fullName, is_admin: !!b.is_admin, active: true, ...roles(b),
        });
        if (insErr) {
          await admin.auth.admin.deleteUser(created.user.id);   // don't leave a half-made login behind
          return json({ error: insErr.message }, 400);
        }
        return json({ ok: true, id: created.user.id });
      }
      case "update": {
        if (!id) return json({ error: "User missing." }, 400);
        if (id === user.id && !b.is_admin) return json({ error: "Aap apna admin access khud nahi hata sakte." }, 400);
        const { error } = await admin.from("portal_users").update({
          full_name: b.full_name ?? null, is_admin: !!b.is_admin, ...roles(b),
        }).eq("id", id);
        return error ? json({ error: error.message }, 400) : json({ ok: true });
      }
      case "password": {
        const password = String(b.password ?? "");
        if (password.length < 8) return json({ error: "Password kam az kam 8 characters ka ho." }, 400);
        const { error } = await admin.auth.admin.updateUserById(id, { password });
        return error ? json({ error: error.message }, 400) : json({ ok: true });
      }
      case "block": {
        if (id === user.id) return json({ error: "Aap apna account khud band nahi kar sakte." }, 400);
        const block = !!b.block;
        const { error } = await admin.auth.admin.updateUserById(id, { ban_duration: block ? "876000h" : "none" });
        if (error) return json({ error: error.message }, 400);
        await admin.from("portal_users").update({ active: !block }).eq("id", id);
        return json({ ok: true });
      }
      case "delete": {
        if (id === user.id) return json({ error: "Aap apna account khud delete nahi kar sakte." }, 400);
        const { error } = await admin.auth.admin.deleteUser(id);   // portal_users row goes with it (cascade)
        return error ? json({ error: error.message }, 400) : json({ ok: true });
      }
      default:
        return json({ error: "Unknown action." }, 400);
    }
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
