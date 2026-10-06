import { createMiddleware, createStart } from "@tanstack/react-start";
import { transferResponseBodyOwnership } from "@tanstack/react-start/server";

// Adds a header the way many auth/session middlewares do (e.g. WorkOS AuthKit):
// by copying the response rather than mutating it.
const copyResponseMiddleware = createMiddleware({ type: "request" }).server(
  async ({ next }) => {
    const result = await next();
    if (process.env.REPRO_COPY !== "1") return result;

    const headers = new Headers(result.response.headers);
    headers.set("x-added-by-middleware", "1");
    const response = new Response(result.response.body, {
      status: result.response.status,
      statusText: result.response.statusText,
      headers,
    });
    if (process.env.REPRO_TRANSFER === "1") {
      transferResponseBodyOwnership(result.response, response);
    }
    return { ...result, response };
  },
);

export const startInstance = createStart(() => ({
  requestMiddleware: [copyResponseMiddleware],
}));
