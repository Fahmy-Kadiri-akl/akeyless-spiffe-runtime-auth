#!/usr/bin/env bash
# Entrypoint for the spiffe-agent image. Renders the agent config from
# environment variables and runs spire-agent. No config file or deploy script is
# needed; the image is self-contained and driven entirely by env.
#
# Required:
#   SPIRE_SERVER_ADDRESS  host or IP of the spire-server
#   SPIFFE_TRUST_DOMAIN   trust domain, must match the server
#   JOIN_TOKEN            one-time join token from the server
# Optional:
#   SPIRE_SERVER_PORT     default 8081
set -euo pipefail

: "${SPIRE_SERVER_ADDRESS:?SPIRE_SERVER_ADDRESS is required}"
: "${SPIFFE_TRUST_DOMAIN:?SPIFFE_TRUST_DOMAIN is required}"
: "${JOIN_TOKEN:?JOIN_TOKEN is required}"
PORT="${SPIRE_SERVER_PORT:-8081}"

# insecure_bootstrap is set for the dev self-signed trust root. For production,
# distribute the server bundle and remove this flag.
cat > /tmp/spire-agent-rendered.conf <<EOF
agent {
    data_dir          = "/opt/spire/.data/agent"
    log_level         = "INFO"
    server_address    = "${SPIRE_SERVER_ADDRESS}"
    server_port       = "${PORT}"
    socket_path       = "/tmp/spire-agent/public/api.sock"
    trust_domain      = "${SPIFFE_TRUST_DOMAIN}"
    insecure_bootstrap = true
}

plugins {
    NodeAttestor "join_token" {
        plugin_data {}
    }

    KeyManager "disk" {
        plugin_data {
            directory = "/opt/spire/.data/agent/keys"
        }
    }

    WorkloadAttestor "unix" {
        plugin_data {}
    }
}
EOF

exec spire-agent run -config /tmp/spire-agent-rendered.conf -joinToken "$JOIN_TOKEN"
