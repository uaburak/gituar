export const SITE_NAME = "Gituar";
export const APP_STORE_ID = "6764865998";
export const APP_STORE_URL = `https://apps.apple.com/tr/app/id${APP_STORE_ID}`;
export const PRO_PRICE_TL = "99,99";
export const FIREBASE_CONFIG = {
  apiKey: import.meta.env.PUBLIC_FIREBASE_API_KEY ?? "",
  authDomain: import.meta.env.PUBLIC_FIREBASE_AUTH_DOMAIN ?? "koc-chords.firebaseapp.com",
  projectId: import.meta.env.PUBLIC_FIREBASE_PROJECT_ID ?? "koc-chords",
  appId: import.meta.env.PUBLIC_FIREBASE_APP_ID ?? "",
};
export const ADSENSE_CLIENT = import.meta.env.PUBLIC_ADSENSE_CLIENT ?? "";
/** AdSense reklam birimi kimlikleri (data-ad-slot). Boş olan yer için reklam basılmaz, yer tutucu da gösterilmez. */
export const ADSENSE_SLOTS: Record<string, string> = {
  side: import.meta.env.PUBLIC_ADSENSE_SLOT_SIDE ?? "",
  rect: import.meta.env.PUBLIC_ADSENSE_SLOT_RECT ?? "",
  inline: import.meta.env.PUBLIC_ADSENSE_SLOT_INLINE ?? "",
  sticky: import.meta.env.PUBLIC_ADSENSE_SLOT_STICKY ?? "",
  leaderboard: import.meta.env.PUBLIC_ADSENSE_SLOT_LEADERBOARD ?? "",
};

/** Şarkı API'si (Cloudflare Worker + D1). Bütün şarkılar buradan okunur. */
export const API_URL = (import.meta.env.PUBLIC_API_URL ?? "https://gituar-api.burak-kc-sp.workers.dev").replace(/\/$/, "");
