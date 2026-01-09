import { readdir } from "node:fs/promises";
import { resolve, join, basename } from "node:path";
import { pathToFileURL } from "node:url";
import type { Route } from "./routes/types";

const port = Number(process.env.API_PORT ?? "8787");

const routes = await loadRoutes();
const routeMap = new Map<string, Route>();

for (const route of routes) {
  const key = routeKey(route.method, route.path);
  if (routeMap.has(key)) {
    throw new Error(`[api] duplicate route ${key}`);
  }
  routeMap.set(key, route);
}

const server = Bun.serve({
  port,
  async fetch(req) {
    const url = new URL(req.url);
    const key = routeKey(req.method, url.pathname);
    const route = routeMap.get(key);
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

async function loadRoutes(): Promise<Route[]> {
  const routesDir = resolve(import.meta.dir, "routes");
  const files: string[] = [];
  await collectRouteFiles(routesDir, files);
  files.sort();

  const loaded: Route[] = [];
  for (const filePath of files) {
    if (basename(filePath) === "types.ts") continue;
    const mod = await import(pathToFileURL(filePath).href);
    if (!mod.route) continue;
    const route = mod.route as Route;
    validateRoute(route, filePath);
    loaded.push({
      method: route.method.toUpperCase(),
      path: route.path,
      handle: route.handle,
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
