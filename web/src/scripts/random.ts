import { newestSongs } from "../lib/search-client.ts";
document.getElementById("btn-random")?.addEventListener("click", async () => {
  const list = await newestSongs(100);
  const pick = list[Math.floor(Math.random() * list.length)];
  if (pick) location.href = pick.p;
});
