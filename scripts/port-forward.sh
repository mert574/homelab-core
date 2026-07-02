#!/usr/bin/env bash
# Pick a cluster service from a menu and port-forward it. No need to remember
# namespaces, service names or ports. Dashboards open in the browser once ready.
#
#   ./scripts/port-forward.sh          # show the menu
#   ./scripts/port-forward.sh grafana  # jump straight to a target by name
#
# Ctrl-C stops the forward. Context defaults to "homelab"; override with
# KCTX=other ./scripts/port-forward.sh
set -euo pipefail

CTX="${KCTX:-homelab}"

# name | namespace | service | local:remote | url-or-hint | open(y/n) | login-secret
# {P} in the hint is replaced with the local port. login-secret is
# "ns/secret:user-key:pass-key" (any part optional) whose creds get printed.
TARGETS=(
  # dashboards (browser UIs)
  "argocd|argocd|argocd-server|8081:80|http://localhost:{P}|y|argocd/argocd-initial-admin-secret::password"
  "grafana|observability|pulse-grafana|3000:80|http://localhost:{P}|y|observability/pulse-grafana:admin-user:admin-password"
  "prometheus|observability|pulse-prometheus-server|9090:80|http://localhost:{P}|y|"
  "alertmanager|observability|pulse-prometheus-alertmanager|9093:9093|http://localhost:{P}|y|"
  "hubble|kube-system|hubble-ui|8082:80|http://localhost:{P}|y|"
  "garage|pulse|garage-web|8090:80|http://localhost:{P}|y|"
  # log/trace backends (API only, query them from Grafana)
  "loki|observability|pulse-loki|3100:3100|curl http://localhost:{P}/ready|n|"
  "tempo|observability|pulse-tempo|3200:3200|curl http://localhost:{P}/ready|n|"
  # app services (connect by hand)
  "api|pulse|api|8080:8080|curl http://localhost:{P}/|n|"
  "billing|pulse|billing|8091:8081|curl http://localhost:{P}/|n|"
  "redis|pulse|redis|6379:6379|redis-cli -p {P}|n|"
  # not in the cluster: postgres LXC, reached over ssh (ns "ssh", svc = host)
  "postgres|ssh|postgres.internal|5432:5432|psql postgresql://pulse@localhost:{P}/pulse|n|"
)

# print "user / password" for a "ns/secret:user-key:pass-key" spec
print_login() {
  local spec="$1" nssec ukey pkey ns sec user pass
  [ -n "$spec" ] || return 0
  nssec="${spec%%:*}"; spec="${spec#*:}"
  ukey="${spec%%:*}"; pkey="${spec#*:}"
  ns="${nssec%%/*}"; sec="${nssec#*/}"
  [ -n "$ukey" ] && user="$(kubectl --context "$CTX" -n "$ns" get secret "$sec" -o "jsonpath={.data.$ukey}" 2>/dev/null | base64 -d)"
  pass="$(kubectl --context "$CTX" -n "$ns" get secret "$sec" -o "jsonpath={.data.$pkey}" 2>/dev/null | base64 -d)"
  [ -n "$pass" ] || { echo "   (login secret $ns/$sec not found)"; return 0; }
  echo "   login: ${user:-admin} / $pass"
}

start() {
  local row="$1" name ns svc mapping hint open login localport
  IFS='|' read -r name ns svc mapping hint open login <<<"$row"
  localport="${mapping%%:*}"
  hint="${hint//\{P\}/$localport}"
  echo "-> $name  ($ns/$svc)"
  echo "   $hint"
  print_login "$login"
  echo "   Ctrl-C to stop."
  # postgres (and anything else) that lives outside the cluster: ssh -L tunnel.
  # svc holds the ssh host, mapping is localport:remoteport.
  if [ "$ns" = "ssh" ]; then
    exec ssh -N -L "$localport:localhost:${mapping#*:}" "$svc"
  fi
  if [ "$open" = "y" ] && command -v open >/dev/null 2>&1; then
    # open the browser once the local port answers, then hand off to kubectl
    ( for _ in $(seq 1 40); do
        if curl -s -o /dev/null "http://localhost:$localport/" 2>/dev/null; then
          open "$hint"; break
        fi
        sleep 0.5
      done ) &
  fi
  exec kubectl --context "$CTX" -n "$ns" port-forward "svc/$svc" "$mapping"
}

# direct pick by name
if [ $# -ge 1 ]; then
  for row in "${TARGETS[@]}"; do
    [ "${row%%|*}" = "$1" ] && start "$row"
  done
  echo "unknown target: $1" >&2
  echo "options: $(for r in "${TARGETS[@]}"; do printf '%s ' "${r%%|*}"; done)" >&2
  exit 1
fi

# interactive menu
echo "Port-forward a service (context: $CTX)"
labels=()
for row in "${TARGETS[@]}"; do
  IFS='|' read -r name ns svc mapping hint open <<<"$row"
  labels+=("$(printf '%-12s localhost:%-5s (%s/%s)' "$name" "${mapping%%:*}" "$ns" "$svc")")
done

PS3=$'\n''Select # (Ctrl-C to quit): '
select choice in "${labels[@]}"; do
  if [ -n "$choice" ]; then
    start "${TARGETS[$((REPLY-1))]}"
  fi
  echo "invalid choice" >&2
done
