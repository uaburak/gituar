#!/usr/bin/env bash
# (Yedek yol) Gituar web → Vercel projesi "gituar.com". Asıl yayın: GitHub main'e push → Vercel otomatik build (kök vercel.json).
# Yerelde `vercel build` (Astro) çalışır, hazır çıktı yüklenir; Vercel'de build çalışmaz.
# Bir kez: `vercel login` ve `vercel link --project gituar.com`. Sonra web/ içinde `npm run deploy`.
set -euo pipefail
cd "$(dirname "$0")/.."
VERCEL="${VERCEL_BIN:-$HOME/.npm-global/bin/vercel}"
[ -x "$VERCEL" ] || VERCEL="npx --yes vercel"
$VERCEL build --prod --yes
$VERCEL deploy --prebuilt --prod --yes --archive=tgz
