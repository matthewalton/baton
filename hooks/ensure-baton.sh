#!/bin/bash
# SessionStart hook: make sure Baton (and therefore its MCP endpoint) is running.
# Baton *is* the server, so the endpoint is only live while the app is open.
# Must never block or fail the session — always exits 0.

endpoint_up() {
  # Any HTTP response counts (a GET may legitimately return 405); we only care
  # that something is listening.
  curl -s -o /dev/null --max-time 1 http://127.0.0.1:8321/mcp
}

endpoint_up && exit 0

# -g: launch without stealing focus from the terminal.
if ! open -g -a Baton 2>/dev/null; then
  echo "Baton is not installed (couldn't find Baton.app), so the baton MCP tools will be unavailable. Install it: https://github.com/matthewalton/baton#-getting-started"
  exit 0
fi

for _ in 1 2 3 4 5 6 7 8 9 10; do
  sleep 0.3
  endpoint_up && exit 0
done

echo "Baton.app was launched but its MCP endpoint (http://127.0.0.1:8321/mcp) isn't responding yet; baton MCP tools may fail until it finishes starting."
exit 0
