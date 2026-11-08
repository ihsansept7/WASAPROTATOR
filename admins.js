import { createClient } from "@supabase/supabase-js";

function clients() {
  const url = process.env.SUPABASE_URL;
  return {
    admin: createClient(url, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } }),
    anon: createClient(url, process.env.SUPABASE_ANON_KEY, { auth: { persistSession: false } })
  };
}
export default async function handler(req, res) {
  const auth = req.headers.authorization || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!token) return res.status(401).json({ error: "Login admin diperlukan." });
  const { admin, anon } = clients();
  const { data: userData, error: userErr } = await anon.auth.getUser(token);
  if (userErr || !userData.user) return res.status(401).json({ error: "Sesi tidak valid." });
  const { data: allowed } = await admin.from("admin_users").select("user_id").eq("user_id", userData.user.id).maybeSingle();
  if (!allowed) return res.status(403).json({ error: "Hanya admin terdaftar yang boleh mengelola akun." });

  if (req.method === "POST") {
    const email = String(req.body?.email || "").trim().toLowerCase();
    const password = String(req.body?.password || "");
    if (!email || password.length < 8) return res.status(400).json({ error: "Email wajib diisi dan password minimal 8 karakter." });
    const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
    if (error) return res.status(400).json({ error: error.message });
    const { error: insertErr } = await admin.from("admin_users").insert({ user_id: data.user.id, email, role: "admin" });
    if (insertErr) {
      await admin.auth.admin.deleteUser(data.user.id);
      return res.status(500).json({ error: insertErr.message });
    }
    return res.status(201).json({ user_id: data.user.id, email });
  }
  if (req.method === "PATCH") {
    const userId = String(req.body?.user_id || "");
    const email = String(req.body?.email || "").trim().toLowerCase();
    const password = String(req.body?.password || "");
    if (!userId || !email) return res.status(400).json({ error: "user_id dan email wajib diisi." });
    const update = { email };
    if (password) {
      if (password.length < 8) return res.status(400).json({ error: "Password minimal 8 karakter." });
      update.password = password;
    }
    const { data, error } = await admin.auth.admin.updateUserById(userId, update);
    if (error) return res.status(400).json({ error: error.message });
    const { error: rowErr } = await admin.from("admin_users").update({ email }).eq("user_id", userId);
    if (rowErr) return res.status(500).json({ error: rowErr.message });
    return res.status(200).json({ user_id: data.user.id, email: data.user.email });
  }
  if (req.method === "DELETE") {
    const userId = String(req.body?.user_id || "");
    if (!userId) return res.status(400).json({ error: "user_id wajib diisi." });
    if (userId === userData.user.id) return res.status(400).json({ error: "Anda tidak dapat menghapus akun sendiri saat sedang login." });
    const { count } = await admin.from("admin_users").select("*", { count: "exact", head: true });
    if ((count || 0) <= 1) return res.status(400).json({ error: "Minimal harus ada satu admin." });
    const { error } = await admin.auth.admin.deleteUser(userId);
    if (error) return res.status(400).json({ error: error.message });
    return res.status(200).json({ ok: true });
  }
  return res.status(405).json({ error: "Method not allowed." });
}
