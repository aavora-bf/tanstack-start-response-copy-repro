#!/usr/bin/env bash
# Builds once, then serves the production build under each combination and
# requests the SSR page.
set -uo pipefail
cd "$(dirname "$0")"
PORT=${PORT:-3123}

[[ ${SKIP_BUILD:-} == 1 ]] || NODE_ENV=production pnpm -s build >/dev/null 2>&1 || { echo "build failed"; exit 1; }

echo "@tanstack/start-server-core $(node -p "require('./$(dirname "$(find node_modules/.pnpm -path '*start-server-core/package.json' | head -1)")/package.json').version")"
echo

run() {
  local label=$1; shift
  env NODE_ENV=production "$@" PORT=$PORT node .output/server/index.mjs >server.log 2>&1 &
  local pid=$!
  for _ in $(seq 50); do curl -s -o /dev/null "http://localhost:$PORT/__ready" && break; sleep 0.1; done

  local out code
  out=$(curl -sS -o /dev/null -w '%{http_code}' "http://localhost:$PORT/" 2>&1)
  code=$?
  kill $pid 2>/dev/null; wait $pid 2>/dev/null

  if [[ $code == 0 ]]; then
    printf '%-58s HTTP %s\n' "$label" "$out"
  else
    printf '%-58s FAILED (curl exit %s: %s)\n' "$label" "$code" "$(head -1 <<<"${out#curl: }")"
  fi
  grep -v -e 'Listening on' -e 'Stopping server' server.log | sed 's/^/    server: /'
  return 0
}

run "1. copy in middleware"                            REPRO_COPY=1
run "2. patched Response, no copy"                     REPRO_PATCH_RESPONSE=1
run "3. patched Response + copy in middleware"         REPRO_PATCH_RESPONSE=1 REPRO_COPY=1
run "4. patched Response + copy + transferOwnership"   REPRO_PATCH_RESPONSE=1 REPRO_COPY=1 REPRO_TRANSFER=1
rm -f server.log
