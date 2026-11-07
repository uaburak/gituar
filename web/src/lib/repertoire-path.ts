// Herkese açık repertuar adresleri: /repertuar/{kullanıcı adı}/{repertuar slug'ı}/
// Kullanıcı adları tekil olduğu, slug da sahibin repertuarları arasında tekil tutulduğu için adres çakışmaz
// ("Sahne" iki kez varsa ikincisi "sahne-2"). Bu alanları henüz almamış eski kayıtlar ?id= ile açılır.
import { slugify } from "@shared/turkish";

export interface RepertoireLink { id: string; ownerUsername?: string; slug?: string }

export function repertoirePath(r: RepertoireLink): string {
  return r.ownerUsername && r.slug
    ? `/repertuar/${encodeURIComponent(r.ownerUsername)}/${encodeURIComponent(r.slug)}/`
    : `/repertuar/?id=${encodeURIComponent(r.id)}`;
}

/** Ada göre slug; `taken` içinde varsa -2, -3 … eklenir ve sonuç `taken`'a eklenir. */
export function uniqueSlug(name: string, taken: Set<string>): string {
  const base = slugify(name);
  let slug = base;
  for (let n = 2; taken.has(slug); n++) slug = `${base}-${n}`;
  taken.add(slug);
  return slug;
}
