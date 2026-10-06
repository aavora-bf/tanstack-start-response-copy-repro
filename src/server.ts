import handler, { createServerEntry } from "@tanstack/react-start/server-entry";

// Stand-in for any library that wraps the global Response and pipes stream
// bodies, e.g. varlock's leak prevention (`patchGlobalResponse`). After this,
// `new Response(stream).body !== stream`.
if (process.env.REPRO_PATCH_RESPONSE === "1") {
  globalThis.Response = new Proxy(globalThis.Response, {
    construct(target, [body, init]) {
      if (body instanceof ReadableStream) {
        body = body.pipeThrough(new TransformStream());
      }
      return Reflect.construct(target, [body, init]);
    },
  });
}

export default createServerEntry({
  fetch(request) {
    return handler.fetch(request);
  },
});
