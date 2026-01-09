export type RouteHandler = (req: Request) => Response | Promise<Response>;

export type Route = {
  method: string;
  path: string;
  handle: RouteHandler;
};