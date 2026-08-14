#!/bin/bash
# keepalived health check: return 0 when caddy accepts TCP on :80 and :443.
for port in 80 443; do
  /usr/bin/timeout 2 /bin/bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null || exit 1
done
exit 0
