import { defineConfig } from "astro/config";
import cloudflare from "@astrojs/cloudflare";
import { fileURLToPath } from "node:url";

// Canlı adres: gituar.com. Sayfalar istek anında üretilir (Cloudflare Worker); şarkılar Gituar API'sinden (D1) gelir.
// Değişmeyen sayfalar (rehberler, yasal sayfalar, giriş…) `export const prerender = true` ile derlemede hazırlanır.
// Site haritası: src/pages/sitemap-index.xml.ts ve parçaları /sitemap-N.xml (middleware'de, istek anında).
const site = process.env.PUBLIC_SITE_URL ?? "https://gituar.com";

export default defineConfig({
  site,
  output: "server",
  adapter: cloudflare({ imageService: "passthrough" }),
  trailingSlash: "always",
  build: { format: "directory", inlineStylesheets: "auto" },
  vite: {
    resolve: {
      alias: [
        // Paylaşılan katalog yardımcılarının Node'a bağlı olmayan kopyası (Worker'da dosya sistemi yok)
        { find: "@shared/catalog", replacement: fileURLToPath(new URL("./src/lib/paths.ts", import.meta.url)) },
        { find: "@shared", replacement: fileURLToPath(new URL("../shared/src", import.meta.url)) },
      ],
    },
    server: { fs: { allow: [fileURLToPath(new URL("..", import.meta.url))] } },
  },
});
