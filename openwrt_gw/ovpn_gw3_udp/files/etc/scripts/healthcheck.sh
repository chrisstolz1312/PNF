#!/bin/sh

# PNF OpenWrt Gateway Healthcheck
# Prüft HTTP Alive sowie OpenVPN-Port 1194 auf IPv4 und IPv6.

set -u

PORT="${IPVS_PORT:-1194}"
PROTO="${IPVS_PROT:-}"

fail() {
    echo "UNHEALTHY: $*" >&2
    exit 1
}

# --------------------------------------------------
# 1. HTTP Alive
# --------------------------------------------------

check_alive() {
    response="$(wget -q -T 3 -O - http://127.0.0.1:7000/ 2>/dev/null)" ||
        fail "HTTP Alive auf 127.0.0.1:7000 nicht erreichbar"

    [ "$response" = "I AM ALIVE" ] ||
        fail "HTTP Alive liefert unerwarteten Inhalt"

    echo "OK: HTTP Alive"
}

# --------------------------------------------------
# 2. Listener in /proc/net prüfen
# --------------------------------------------------

check_listener() {
    family="$1"
    protocol="$2"

    case "$protocol:$family" in
        tcp:4) table="/proc/net/tcp" ;;
        tcp:6) table="/proc/net/tcp6" ;;
        udp:4) table="/proc/net/udp" ;;
        udp:6) table="/proc/net/udp6" ;;
        *) fail "Ungültiges Protokoll oder IP-Familie" ;;
    esac

    [ -r "$table" ] ||
        fail "$table nicht lesbar"

    port_hex="$(printf '%04X' "$PORT")"

    awk -v port="$port_hex" -v protocol="$protocol" '
        NR == 1 { next }

        {
            split($2, address, ":")
            local_port = toupper(address[2])

            # TCP: 0A = LISTEN
            # UDP: 07 = unconnected/bound
            if (local_port == port) {
                if (protocol == "tcp" && $4 == "0A")
                    found = 1

                if (protocol == "udp" && $4 == "07")
                    found = 1
            }
        }

        END {
            exit(found ? 0 : 1)
        }
    ' "$table" ||
        fail "OpenVPN $protocol IPv$family Port $PORT nicht gebunden"

    echo "OK: OpenVPN $protocol IPv$family Port $PORT"
}

# --------------------------------------------------
# 3. Hauptprogramm
# --------------------------------------------------

case "$PROTO" in
    tcp|udp)
        ;;
    *)
        fail "IPVS_PROT muss tcp oder udp sein"
        ;;
esac

case "$PORT" in
    ''|*[!0-9]*)
        fail "Ungültiger IPVS_PORT"
        ;;
esac

[ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] ||
    fail "Port außerhalb des gültigen Bereichs"

check_alive
check_listener 4 "$PROTO"
check_listener 6 "$PROTO"

echo "HEALTHY: Alle Prüfungen erfolgreich"
exit 0
