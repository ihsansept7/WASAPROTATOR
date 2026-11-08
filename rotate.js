import { createClient } from "@supabase/supabase-js";

export default async function handler(req, res) {
  if (req.method !== "GET") return res.status(405).send("Method not allowed");
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return res.status(500).send("Server configuration is incomplete.");
  const db = createClient(url, key, { auth: { persistSession: false } });
  const project = String(req.query.project || "").trim();
  if (!project) return res.status(400).send("Project tidak ditemukan.");
  const { data, error } = await db.rpc("allocate_whatsapp_lead", {
    p_project_slug: project,
    p_campaign: String(req.query.utm_campaign || req.query.campaign || "").slice(0,250),
    p_source: String(req.query.utm_source || "").slice(0,100),
    p_medium: String(req.query.utm_medium || "").slice(0,100),
    p_content: String(req.query.utm_content || "").slice(0,250),
    p_term: String(req.query.utm_term || "").slice(0,250),
    p_fbclid: String(req.query.fbclid || "").slice(0,500)
  });
  if (error) return res.status(404).send("Rotator gagal: " + error.message);
  const lead = Array.isArray(data) ? data[0] : data;
  if (!lead || !lead.phone) return res.status(404).send("Project belum memiliki sales aktif.");
  const text = encodeURIComponent(lead.message || `Halo, saya tertarik dengan ${lead.project_name}. Mohon informasi lebih lanjut.`);
  return res.redirect(302, `https://wa.me/${lead.phone}?text=${text}`);
}
