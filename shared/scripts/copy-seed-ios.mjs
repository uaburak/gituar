// catalog.deflate'i iOS paketine kopyalar (Gituar/Resources/catalog.deflate). Her sürümden önce çalıştırılır.
import { copyFileSync, mkdirSync, statSync } from "node:fs";
import { dirname } from "node:path";
import { iosSeedPath, snapshotPath } from "./_paths.mjs";

mkdirSync(dirname(iosSeedPath), { recursive: true });
copyFileSync(snapshotPath, iosSeedPath);
console.log(`✅ iOS seed güncellendi: ${iosSeedPath} (${Math.round(statSync(iosSeedPath).size / 1024)} KB)`);
