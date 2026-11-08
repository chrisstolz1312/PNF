# PNF — Prototype Network Fabric

**Self-hosted OpenVPN infrastructure with Docker, OpenWrt, IPv4/IPv6 and IPVS load balancing.**

PNF is an open-source project for building a modular OpenVPN environment on a Linux server. It combines **eight containerized OpenWrt VPN gateways** (four TCP and four UDP) with Linux IPVS load balancing, a browser-based certificate authority, Unbound DNS, and operational tools.

Designed for homelabs, networking experiments and administrators who want to explore a multi-gateway OpenVPN deployment rather than a single VPN container.

**Supported installer targets:** Debian 13 (Trixie) and Ubuntu Server 26.04, on x86-64 (amd64).

> [!WARNING]
> **Alpha software — not production-ready.** PNF changes host networking, firewall rules and kernel settings, and uses privileged containers. Review the code and network exposure before running it. Create a verified VM snapshot and an off-host backup first. The installer requires explicit snapshot confirmation.

## Features

| Component | Description |
| --- | --- |
| OpenVPN | Eight OpenWrt-based gateways: four TCP and four UDP |
| Load balancing | Linux IPVS for TCP and UDP, using least-connections (`lc`) scheduling |
| Dual-stack networking | IPv4 and IPv6 gateway backends; NAT66 and Jool host setup |
| Certificate management | Web-based CA with server certificate export |
| DNS | Unbound integration |
| Host filtering | UFW rules to isolate the VPN Docker bridge from host services |
| Monitoring | Dozzle for Docker container status and logs |
| Dynamic DNS | Optional `ddclient` service |
| Deployment | Separate installers for Debian 13 and Ubuntu Server 26.04 |

## Architecture

```text
                      OpenVPN clients
                      IPv4 and IPv6
                            |
                      TCP/UDP :1194
                            |
                     Linux IPVS (lc)
                       /          \
                      /            \
          TCP OpenWrt gateways   UDP OpenWrt gateways
               gw1–gw4              gw1–gw4
                      \            /
                       Docker bridge
                            |
                  VPN routing / DNS

 Web CA -------- server certificate export --------> OpenVPN gateways
 Unbound ------- DNS services
 Dozzle -------- Docker monitoring
 ddclient ------ optional Dynamic DNS
```

The IPVS configuration defines four backends per protocol, on a dual-stack Docker network. IPVS handles **both TCP and UDP**; HAProxy is not part of the current IPVS-only deployment.

### Repository layout

```text
PNF/
├── install_debian_13.sh       Debian 13 installer
├── install_ubuntu_26.sh       Ubuntu Server 26.04 installer
├── build.sh                   Project build/start helper
├── down.sh                    Project shutdown helper
├── backup.sh                  Archive backup helper
├── config/                    PNF configuration
├── scripts/                   Kernel, NAT66 and UFW host setup
├── web_ca/                    Certificate authority and exports
├── openwrt_gw/
│   ├── ovpn_gw1_tcp/ ... ovpn_gw4_tcp/
│   ├── ovpn_gw1_udp/ ... ovpn_gw4_udp/
│   ├── ipvs/                 IPVS configuration and service
│   ├── unbound/              DNS service
│   └── build.sh              Gateway, DNS and IPVS deployment
├── dozzle/                    Container monitoring
└── ddclient/                  Optional Dynamic DNS
```

## Requirements

- **Debian 13** or **Ubuntu Server 26.04**, x86-64 (amd64), with systemd.
- Root access via `sudo`, internet access and working APT repositories.
- A compatible Linux kernel and package repositories providing Docker, Docker Compose v2, IPVS, TUN, Jool and their dependencies.
- Enough CPU, RAM and storage for eight OpenWrt gateways and the supporting services.
- The OpenWrt root filesystem archive at:

  ```text
  openwrt_gw/image/openwrt-x86-64-generic-rootfs.tar.gz
  ```

- A verified VM snapshot taken **on the hypervisor** before installation.

The installer installs host dependencies and checks required components. Depending on the system update, a reboot may be necessary before continuing.

## Installation

> [!IMPORTANT]
> Read the installer and the host configuration scripts before running them. The installation updates packages and changes host networking, firewall configuration and Docker services.

Clone the repository:

```bash
git clone https://github.com/chrisstolz1312/PNF.git
cd PNF
```

Verify that the OpenWrt root filesystem archive exists at the path listed above. Then run **one** installer, depending on the operating system.

**Debian 13:**

```bash
sudo bash ./install_debian_13.sh
```

**Ubuntu Server 26.04:**

```bash
sudo bash ./install_ubuntu_26.sh
```

The installation workflow:

1. Requests confirmation of a verified hypervisor snapshot before modifying packages.
2. Updates the host and installs required dependencies.
3. Configures kernel modules, NAT66 and UFW using the scripts in `scripts/`.
4. Starts the Web CA and waits for you to create the CA and export the server credentials.
5. Validates the certificate files and the server certificate/private-key match.
6. Configures IPVS for TCP and UDP, builds and starts the OpenWrt gateways, Unbound and IPVS.
7. Starts Dozzle and the optional `ddclient` module if configured.

If the installer reports that a reboot is required, reboot and rerun the same installer.

### Web interfaces

| Service | Address | Purpose |
| --- | --- | --- |
| Web CA | `http://<SERVER-IP>:8080` | Certificate authority and certificate management |
| Dozzle | `http://<SERVER-IP>:8081` | Container monitoring and logs |

These are **HTTP** interfaces. Do not expose them directly to the public internet. Restrict access to a trusted administration network and use suitable authentication and transport protection where applicable.

## Networking and security

### VPN and load balancing

The IPVS service listens on **port 1194**, for both TCP and UDP, on the host's detected IPv4 and IPv6 addresses. Its configuration uses the **least-connections** scheduler and forwards traffic to four TCP or four UDP OpenWrt backends.

OpenWrt containers have dedicated IPv4 and IPv6 addresses on the `openwrt_openvpn` Docker network. The gateway definitions also contain Docker port mappings for individual instances; these are separate from the IPVS frontend.

### Host firewall

The host setup includes `scripts/30_configure_ufw.sh`, which applies a deny rule for incoming traffic on the `br-openvpn` bridge. **This does not constitute a default-deny firewall for all host interfaces**: the current script sets default incoming, outgoing and routed policies to allow. Review and adapt these rules to your deployment before exposing the server.

### Privileged containers

Some components require elevated Docker privileges, host networking capabilities or access to `/dev/net/tun`. Review the Compose files and protect access to the Docker daemon. Membership in the Docker group effectively grants root-level control over the host.

## Certificate management

The Web CA is responsible for CA and server credentials. The installer expects these exported files:

```text
web_ca/server_export/
├── ca.crt
├── server.crt
├── server.key
├── dh.pem
└── tls-crypt.key
```

During installation, PNF checks that the files exist, that the certificates are valid at the time of checking, and that the server certificate matches the server private key.

**Never commit private keys, CA secrets, provider tokens or generated credentials.** Protect exported keys and backups, and review `.gitignore` before publishing changes.

## Healthchecks and monitoring

The gateway Compose configuration is being extended with Docker healthchecks. The intended checks cover:

- An HTTP alive response (`I AM ALIVE`) on port **7000** inside each gateway.
- A TCP or UDP listener on port **1194**, for both IPv4 and IPv6, according to the gateway type.

> [!NOTE]
> Healthcheck changes are under validation. Confirm that all eight gateway containers report `healthy` after a clean deployment before treating the feature as verified. A socket/listener check does **not** prove that a VPN client can authenticate or pass traffic. Docker's `restart: unless-stopped` does not automatically restart a container solely because its health status becomes `unhealthy`.

Inspect the running containers:

```bash
sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
```

Inspect a gateway health status, once the healthcheck-enabled image is deployed:

```bash
sudo docker inspect openwrt_gw1_tcp --format '{{json .State.Health}}'
```

Dozzle provides a web interface for observing container logs and status. Restrict access to it, particularly if it has Docker socket access or container-control permissions.

## Logs and troubleshooting

**Debian installer log:**

```bash
sudo tail -n 100 /var/log/pnf-install-debian.log
```

**Ubuntu installer log:**

```bash
sudo tail -n 100 /var/log/pnf-install-ubuntu.log
```

Inspect a specific container:

```bash
sudo docker logs --tail 100 openwrt_gw1_tcp
```

Check IPVS rules and backend statistics:

```bash
sudo ipvsadm -Ln
sudo ipvsadm -Ln --stats
```

For installation issues, include the operating system, kernel version, affected component and relevant redacted log excerpts in a bug report.

## Optional services

### Dynamic DNS (`ddclient`)

The `ddclient/` module can update a DNS hostname when the public IP address changes. Configure your provider and credentials in the module's configuration before relying on it.

```bash
cd ddclient
docker compose up -d
```

Do not commit provider passwords or API tokens.

### Dozzle

Dozzle is started by the installer. It can also be managed from its module directory:

```bash
cd dozzle
docker compose ps
```

## Backups

The repository includes `backup.sh`, which archives the **visible files and directories under the directory containing the script**. Hidden files and directories are excluded. By default, the archive is written to `/tmp/pnf-backups/`.

```bash
sudo bash ./backup.sh
```

**Important:** `/tmp` is not an off-host backup location. Copy the archive outside the VM before reverting snapshots or reinstalling. Check that the archive contains everything needed for recovery, especially any hidden configuration or externally stored data.

## Project status and limitations

- **Development stage:** Alpha.
- **Platforms:** Debian 13 and Ubuntu Server 26.04 on amd64, subject to host kernel and package availability.
- **Deployment:** Interactive Web CA initialization is required for a fresh installation.
- **Networking:** IPVS-only load balancing for TCP and UDP; dual-stack operation depends on the host and upstream network.
- **Security:** Host firewall rules, UI exposure, privileged containers and secret storage require administrator review.
- **Validation:** A successful build is not a substitute for end-to-end client connection, DNS, routing, IPv4 and IPv6 tests.

## Contributing

Issues, reproducible bug reports, documentation improvements and pull requests are welcome. Please include the operating system, kernel version, steps to reproduce and relevant logs. **Redact private keys, credentials and other sensitive data.**

## License

PNF is distributed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**. See [`LICENSE`](LICENSE).
