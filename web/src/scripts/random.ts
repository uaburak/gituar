import { loadIndex } from "../lib/search-client.ts";
document.getElementById("btn-random")?.addEventListener("click", async () => {
  const index = await loadIndex();
  const pick = index[Math.floor(Math.random() * index.length)];
  if (pick) location.href = pick.p;
});
