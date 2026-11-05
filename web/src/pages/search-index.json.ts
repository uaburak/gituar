import type { APIRoute } from "astro";
import { searchIndex } from "../lib/catalog.ts";

export const GET: APIRoute = () =>
  new Response(JSON.stringify(searchIndex()), { headers: { "Content-Type": "application/json; charset=utf-8" } });
