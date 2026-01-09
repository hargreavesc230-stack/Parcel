import type { Route } from "./types";

export const route: Route = {
  method: "GET",
  path: "/health",
  handle() {
    return new Response("ok", { status: 200 });
  },
};
