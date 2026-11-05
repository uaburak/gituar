// Yayın: Firestore'dan farkları çek → iOS seed'i güncelle → web'i derle → (isteğe bağlı) Hosting'e deploy.
// Kullanım: npm run publish [-- --deploy] [--skip-pull]
import { spawnSync } from "node:child_process";
import { repoRoot } from "./_paths.mjs";

const args = process.argv.slice(2);
const run = (cmd, cmdArgs) => {
  console.log(`\n$ ${cmd} ${cmdArgs.join(" ")}`);
  const r = spawnSync(cmd, cmdArgs, { stdio: "inherit", cwd: repoRoot });
  if (r.status !== 0) process.exit(r.status ?? 1);
};

if (!args.includes("--skip-pull")) run("node", ["shared/scripts/pull-catalog.mjs"]);
run("node", ["shared/scripts/copy-seed-ios.mjs"]);
run("npm", ["run", "build", "-w", "web"]);
if (args.includes("--deploy")) run("npx", ["firebase", "deploy", "--only", "hosting"]);
console.log("\n✅ Yayın adımları tamamlandı.");
