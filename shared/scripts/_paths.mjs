import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

export const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
export const snapshotPath = resolve(repoRoot, "shared/catalog/catalog.deflate");
export const iosSeedPath = resolve(repoRoot, "Gituar/Resources/catalog.deflate");
