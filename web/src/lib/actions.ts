// Popülerlik: kişi × şarkı × işlem başına tek puan (API tekilleştirir). Giriş yoksa cihaz kimliği kullanılır.
import { API_URL } from "./site.ts";

function deviceId(): string {
  try {
    let id = localStorage.getItem("gituar-device");
    if (!id) { id = crypto.randomUUID(); localStorage.setItem("gituar-device", id); }
    return id;
  } catch {
    return "";
  }
}

/** view: sayfa açılışı (geri alınmaz). favorite/repertoire: active=false ile puan geri alınır; giriş gerekir. */
export async function trackAction(songId: string, action: "view" | "favorite" | "repertoire", opts: { token?: string; active?: boolean } = {}): Promise<void> {
  try {
    await fetch(`${API_URL}/v1/actions`, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...(opts.token ? { Authorization: `Bearer ${opts.token}` } : {}) },
      body: JSON.stringify({ songId, action, active: opts.active ?? true, deviceId: deviceId() }),
      keepalive: true,
    });
  } catch {}
}
