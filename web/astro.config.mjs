import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";
import { fileURLToPath } from "node:url";
import { sitemapLastmod } from "./sitemap-lastmod.mjs";
import { excludedFromSitemap } from "./src/lib/catalog-rules.mjs";

// Canlı adres: gituar.com (Firebase Hosting özel alan adı); koc-chords.web.app ikincil adres.
const site = process.env.PUBLIC_SITE_URL ?? "https://gituar.com";

// `noindex` basılan sayfalar (Base.astro) sitemap'e de girmez; robots.txt ile uyumlu tutulur.
const NOINDEX_PATHS = /^https?:\/\/[^/]+\/(ara|giris|repertuarlarim|repertuar|admin|og|404)\/$/;

export default defineConfig({
  site,
  output: "static",
  trailingSlash: "always",
  build: { format: "directory", inlineStylesheets: "auto" },
  integrations: [
    sitemap({
      filter: (page) => !NOINDEX_PATHS.test(page) && !excludedFromSitemap(new URL(page).pathname),
      // ~17 bin URL: sitemap-index.xml + 5.000'lik alt haritalar (sitemap-0.xml, sitemap-1.xml …)
      entryLimit: 5000,
      serialize: (item) => {
        const lastmod = sitemapLastmod(item.url);
        return lastmod ? { ...item, lastmod } : item;
      },
    }),
  ],
  vite: {
    resolve: {
      alias: { "@shared": fileURLToPath(new URL("../shared/src", import.meta.url)) },
    },
    server: { fs: { allow: [fileURLToPath(new URL("..", import.meta.url))] } },
  },
});
