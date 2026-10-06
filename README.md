# TanStack Start: copying the page Response in middleware drops the connection

Since `@tanstack/start-server-core` 1.169.36 (`@tanstack/react-start` 1.168.55, TanStack/router#8204), a request middleware that returns a copy of the page response can kill the SSR stream. The server closes the socket without writing a status line and logs nothing.

It happens when the copy's body is not the same object as the original, i.e. `new Response(stream).body !== stream`. Natively the two are the same object, so a plain copy works. Any library that wraps the global `Response` and pipes stream bodies breaks that identity. Start then sees the copy as a replacement and disposes the page's SSR stream.

## Run it

Node 24, pnpm.

```sh
pnpm install
pnpm repro
```

`repro.sh` builds once, serves the production build (nitro `node-server`) under four configurations and requests `/` with curl:

```
@tanstack/start-server-core 1.169.39

1. copy in middleware                                      HTTP 200
2. patched Response, no copy                               HTTP 200
3. patched Response + copy in middleware                   FAILED (curl exit 52: (52) Empty reply from server)
4. patched Response + copy + transferOwnership             HTTP 200
```

| Env var | Effect |
| --- | --- |
| `REPRO_COPY=1` | `src/start.ts` middleware returns `new Response(result.response.body, …)` with an extra header |
| `REPRO_TRANSFER=1` | that middleware also calls `transferResponseBodyOwnership(result.response, copy)` |
| `REPRO_PATCH_RESPONSE=1` | `src/server.ts` wraps the global `Response` in a Proxy that pipes stream bodies through a `TransformStream` |

Case 3 is the bug. Cases 1 and 2 show neither ingredient fails alone. Case 4 shows `transferResponseBodyOwnership` avoids it, but the middleware author has to know to call it.

In dev the same case fails differently. Run `REPRO_PATCH_RESPONSE=1 REPRO_COPY=1 pnpm dev`, then `curl -i localhost:3000/`. Vite answers 500 with `socket hang up`.

## Regression

With `@tanstack/react-start` 1.168.54 and `@tanstack/react-router` 1.170.36 (`start-server-core` 1.169.35), case 3 returns 200. That version has no `transferResponseBodyOwnership`, so delete its import and call in `src/start.ts` before building. With 1.168.55 and 1.170.37 (`start-server-core` 1.169.36), case 3 fails.

## Where it happens

1. `createStartHandler`: the middleware's response fails `inheritsResponseOwnership` because its body is a different stream and nothing registered it with `transferResponseBodyOwnership`.
2. `disposeResponseOwnership(current, "middleware response replaced")` disposes the SSR stream response, which runs the router's SSR cleanup.
3. The SSR stream transform errors ("SSR stream transform aborted by router SSR cleanup"). The copy's body was piped from that stream, so it errors too.
4. srvx's node adapter fails reading the body and destroys the socket before the status line is flushed.

Server function and server route responses are not affected, because they have no SSR stream to dispose.

## In the wild

- [WorkOS AuthKit for TanStack Start](https://github.com/workos/authkit-tanstack-start) copies the response this way whenever it has a cookie to set, such as after refreshing the session.
- [varlock](https://github.com/dmno-dev/varlock)'s leak prevention (`patchGlobalResponse`) wraps `Response` and pipes stream bodies through a scanner.

Together, every page load failed once the access token expired. Behind an AWS ALB that surfaced as a 502 with nothing in the application logs.
