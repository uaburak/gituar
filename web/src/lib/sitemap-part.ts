import type { APIRoute } from "astro";
import { sitemapEntries, SITEMAP_CHUNK } from "./sitemap.ts";

export const sitemapPart = (part: number): APIRoute => ({ site }) => {
  const base = (site?.href ?? "https://gituar.com/").replace(/\/$/, "");
  const entries = sitemapEntries(base).slice(part * SITEMAP_CHUNK, (part + 1) * SITEMAP_CHUNK);
  if (!Number.isInteger(part) || part < 0 || (part > 0 && entries.length === 0)) return new Response("Not found", { status: 404 });
  const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;");
  const body = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${
    entries.map((e) => `<url><loc>${esc(e.loc)}</loc>${e.lastmod ? `<lastmod>${e.lastmod}</lastmod>` : ""}</url>`).join("")
  }</urlset>`;
  return new Response(body, { headers: { "Content-Type": "application/xml; charset=utf-8", "Cache-Control": "public, max-age=300" } });
};
