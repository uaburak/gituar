/// <reference types="astro/client" />

interface ImportMetaEnv {
  readonly PUBLIC_FIREBASE_API_KEY?: string;
  readonly PUBLIC_FIREBASE_AUTH_DOMAIN?: string;
  readonly PUBLIC_FIREBASE_PROJECT_ID?: string;
  readonly PUBLIC_FIREBASE_APP_ID?: string;
  readonly PUBLIC_ADSENSE_CLIENT?: string;
  readonly PUBLIC_SITE_URL?: string;
  readonly PUBLIC_GSC_VERIFICATION?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
