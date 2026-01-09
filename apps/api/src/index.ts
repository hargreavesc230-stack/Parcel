const port = Number(process.env.API_PORT ?? "8787");

const server = Bun.serve({
  port,
  fetch(req) {
    const url = new URL(req.url);

    if (req.method === "GET" && url.pathname === "/health") {
      return new Response("ok", { status: 200 });
    }

    return new Response("Not Found", { status: 404 });
  },
});

console.log(`[api] listening on http://127.0.0.1:${server.port}`);
