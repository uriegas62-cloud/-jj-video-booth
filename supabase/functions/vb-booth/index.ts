// J&J Video Booth — booth-side API.
// actions:
//   prepare  {slug, upload_key, code}                         -> signed upload URLs for photo + video
//   complete {slug, upload_key, code, has_photo, has_video, video_seconds}
//   email    {slug, upload_key, code, email}                  -> sends the guest their links via Resend
// Secrets: RESEND_API_KEY (required for email), BOOTH_FROM_EMAIL, BOOTH_GALLERY_URL
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const BUCKET = "vb-media";
const GALLERY = Deno.env.get("BOOTH_GALLERY_URL") ?? "https://jj-video-booth.netlify.app";
const FROM = Deno.env.get("BOOTH_FROM_EMAIL") ?? "J&J Photo Booth <booth@jandjworkshop.com>";
const CODE_RE = /^[A-Z2-9]{6,10}$/;

async function eventFor(slug: string, key: string) {
  const { data } = await db.from("vb_events").select("id, title, honoree").eq("slug", slug).eq("upload_key", key).eq("active", true).maybeSingle();
  return data;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  let b: Record<string, any>;
  try { b = await req.json(); } catch { return json({ error: "bad json" }, 400); }

  const code = String(b.code ?? "").toUpperCase();
  if (!CODE_RE.test(code)) return json({ error: "bad code" }, 400);
  const ev = await eventFor(String(b.slug ?? ""), String(b.upload_key ?? ""));
  if (!ev) return json({ error: "unknown event or upload key" }, 403);

  const photoPath = `${ev.id}/${code}/photo.jpg`;
  const videoPath = `${ev.id}/${code}/video.mp4`;

  if (b.action === "prepare") {
    const { data: existing } = await db.from("vb_sessions").select("event_id").eq("code", code).maybeSingle();
    if (existing && existing.event_id !== ev.id) return json({ error: "code taken" }, 409);
    if (!existing) {
      const { error } = await db.from("vb_sessions").insert({ event_id: ev.id, code });
      if (error) return json({ error: error.message }, 500);
    }
    const p = await db.storage.from(BUCKET).createSignedUploadUrl(photoPath, { upsert: true });
    const v = await db.storage.from(BUCKET).createSignedUploadUrl(videoPath, { upsert: true });
    if (p.error || v.error) return json({ error: (p.error ?? v.error)!.message }, 500);
    return json({ photo_upload_url: p.data.signedUrl, video_upload_url: v.data.signedUrl });
  }

  if (b.action === "complete") {
    const { error } = await db.from("vb_sessions").update({
      photo_path: b.has_photo ? photoPath : null,
      video_path: b.has_video ? videoPath : null,
      video_seconds: Number.isFinite(b.video_seconds) ? Math.round(b.video_seconds) : null,
    }).eq("code", code).eq("event_id", ev.id);
    if (error) return json({ error: error.message }, 500);
    return json({ ok: true, link: `${GALLERY}/?s=${code}` });
  }

  if (b.action === "email") {
    const email = String(b.email ?? "").trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: "bad email" }, 400);
    const { data: s } = await db.from("vb_sessions").select("id, emails_sent, photo_path").eq("code", code).eq("event_id", ev.id).maybeSingle();
    if (!s) return json({ error: "session not uploaded yet" }, 404);
    if (s.emails_sent >= 5) return json({ error: "email limit reached" }, 429);
    const key = Deno.env.get("RESEND_API_KEY");
    if (!key) return json({ error: "RESEND_API_KEY not set" }, 500);

    const link = `${GALLERY}/?s=${code}`;
    const photoUrl = s.photo_path ? db.storage.from(BUCKET).getPublicUrl(s.photo_path).data.publicUrl : "";
    const esc = (t: string) => t.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
    const html = `
<div style="font-family:Georgia,serif;background:#0e0a08;color:#f3e9d8;padding:28px;text-align:center">
  <h1 style="font-weight:normal;margin:0 0 6px">${esc(ev.title)}</h1>
  <p style="margin:0 0 20px;color:#c9a96e">Thanks for celebrating ${esc(ev.honoree)}!</p>
  ${photoUrl ? `<img src="${photoUrl}" alt="Your booth photo" style="max-width:320px;width:100%;border-radius:6px">` : ""}
  <p style="margin:24px 0">
    <a href="${link}" style="background:#c9a96e;color:#0e0a08;padding:14px 26px;border-radius:30px;text-decoration:none;font-family:Arial,sans-serif;font-weight:bold">See &amp; download your photo and video</a>
  </p>
  <p style="font-size:12px;color:#8a7a66;font-family:Arial,sans-serif">J&amp;J Workshop Photo Booth · jandjworkshop.com</p>
</div>`;
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from: FROM, to: [email], subject: `Your photo booth pics from ${ev.title}`, html }),
    });
    if (!r.ok) return json({ error: `resend: ${await r.text()}` }, 502);
    await db.from("vb_sessions").update({ guest_email: email, emails_sent: s.emails_sent + 1 }).eq("id", s.id);
    return json({ ok: true });
  }

  return json({ error: "unknown action" }, 400);
});
