import { readdir } from "node:fs/promises";
import { resolve, join, basename } from "node:path";
import { pathToFileURL } from "node:url";
import type { Route } from "./routes/types";
import { initStorage } from "./storage";

const port = Number(process.env.API_PORT ?? "8787");

await initStorage();

const routes = await loadRoutes();

const server = Bun.serve({
  port,
  async fetch(req) {
    const url = new URL(req.url);
    const route = matchRoute(routes, req.method, url.pathname);
    if (!route) {
      return new Response("Not Found", { status: 404 });
    }
    return route.handle(req);
  },
});

console.log(`[api] listening on http://127.0.0.1:${server.port}`);

function routeKey(method: string, path: string) {
  return `${method.toUpperCase()} ${path}`;
}

function matchRoute(routes: LoadedRoute[], method: string, pathname: string) {
  const upperMethod = method.toUpperCase();
  for (const route of routes) {
    if (route.method !== upperMethod) continue;
    if (route.match(pathname)) return route;
  }
  return null;
}

type LoadedRoute = Route & { match: (pathname: string) => boolean };

async function loadRoutes(): Promise<LoadedRoute[]> {
  const routesDir = resolve(import.meta.dir, "routes");
  const files: string[] = [];
  await collectRouteFiles(routesDir, files);
  files.sort();

  const loaded: LoadedRoute[] = [];
  const seen = new Set<string>();
  for (const filePath of files) {
    if (basename(filePath) === "types.ts") continue;
    const mod = await import(pathToFileURL(filePath).href);
    if (!mod.route) continue;
    const route = mod.route as Route;
    validateRoute(route, filePath);
    const normalizedMethod = route.method.toUpperCase();
    const key = routeKey(normalizedMethod, route.path);
    if (seen.has(key)) {
      throw new Error(`[api] duplicate route ${key}`);
    }
    seen.add(key);
    loaded.push({
      method: normalizedMethod,
      path: route.path,
      handle: route.handle,
      match: buildMatcher(route.path),
    });
  }

  return loaded;
}

async function collectRouteFiles(dir: string, files: string[]) {
  const entries = await readdir(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) {
      await collectRouteFiles(fullPath, files);
      continue;
    }
    if (!entry.isFile()) continue;
    if (!fullPath.endsWith(".ts")) continue;
    files.push(fullPath);
  }
}

function validateRoute(route: Route, filePath: string) {
  if (!route || typeof route !== "object") {
    throw new Error(`[api] invalid route export in ${filePath}`);
  }
  if (typeof route.method !== "string" || !route.method.trim()) {
    throw new Error(`[api] route missing method in ${filePath}`);
  }
  if (typeof route.path !== "string" || !route.path.startsWith("/")) {
    throw new Error(`[api] route missing path in ${filePath}`);
  }
  if (typeof route.handle !== "function") {
    throw new Error(`[api] route missing handle in ${filePath}`);
  }
}

function buildMatcher(path: string) {
  const parts = path.split("/").filter(Boolean);
  return (pathname: string) => {
    const pathParts = pathname.split("/").filter(Boolean);
    if (pathParts.length !== parts.length) return false;
    for (let i = 0; i < parts.length; i += 1) {
      const expected = parts[i];
      const actual = pathParts[i];
      if (!expected || !actual) return false;
      if (expected.startsWith(":")) continue;
      if (expected !== actual) return false;
    }
    return true;
  };
}
