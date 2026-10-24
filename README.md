# :P-NF — Prototype Network Fabric

**Alpha release** · Modular OpenVPN infrastructure for **Ubuntu Server 26.04**.

PNF provides an installer-driven VPN gateway stack built around containerized OpenWrt instances, a web-based certificate authority, and IPVS load balancing for TCP and UDP. Supporting services include Unbound DNS, optional DynDNS via ddclient, and container monitoring through Dozzle.

> [!WARNING]
> **Alpha software.** PNF is under active development and is not yet a hardened, production-ready distribution. Review all scripts, network exposure, certificate handling, and firewall rules before deployment. Create a VM snapshot and an off-host backup first.

## Features

- **OpenVPN gateways:** eight containerized OpenWrt backends (four TCP and four UDP).
- **Load balancing:** Linux IPVS for TCP and UDP, with IPv4 and IPv6 support.
- **Web CA:** browser-based certificate authority for CA and client management, plus server certificate export.
- **DNS:** Unbound integration.
- **Dynamic DNS:** optional ddclient module; provider credentials must be configured separately.
- **Monitoring:** optional Dozzle web UI for Docker container status, logs, and manual actions.
- **Modular scripts:** separate build and shutdown scripts for individual components.

## Architecture

```text
Ubuntu Server 26.04
│
├── install.sh                 Main installer
├── config/                    PNF configuration
├── web_ca/                    Web CA and server certificate export
├── openwrt_gw/                OpenWrt VPN gateways, Unbound, IPVS
├── dozzle/                    Optional Docker monitoring UI
├── ddclient/                  Optional DynDNS service
├── backup.sh                  Home-directory archive helper
├── build.sh                   Project-level helper (if present)
└── down.sh                    Project-level helper (if present)
```

### Traffic and services

```text
VPN clients
    │
    ▼
Host IPVS (TCP/UDP, IPv4/IPv6)
    │
    ├── OpenWrt TCP gateways × 4
    └── OpenWrt UDP gateways × 4
              │
              └── VPN and DNS services

Web CA ──► server_export/ ──► VPN gateway configuration
Dozzle ──► Docker status and logs

ddclient ──► optional public IP / DynDNS updates
```

PNF uses **IPVS for both TCP and UDP**; HAProxy is not part of the current IPVS-only setup.

## Requirements

- Ubuntu Server **26.04** (the installer checks the OS version).
- Root access (`sudo`) and working APT repositories.
- Internet connectivity for system packages and container images.
- A working system clock and RTC; the installer synchronizes the system clock from the RTC before its initial APT update.
- Kernel support for IPVS, connection tracking, TUN, and Jool.
- Sufficient CPU, memory, and disk space for the OpenWrt containers and supporting services.
- A prepared OpenWrt root filesystem at `openwrt_gw/image/openwrt-x86-64-generic-rootfs.tar.gz`.

The installer installs its required packages, including Docker, Docker Compose v2, OpenVPN, IPVS tools, and Jool. A reboot may be required after system updates.

## Installation

> [!IMPORTANT]
> Review the installer and module configuration before running it. Installation changes system packages, kernel module settings, Docker services, and networking.

1. Copy or clone the project into your user's home directory.
2. Confirm that the OpenWrt root filesystem archive exists at the path listed above.
3. Start the installer:

   ```bash
   cd ~
   sudo bash ./install.sh
   ```

4. If the installer requests a reboot, reboot and run the command again.
5. When prompted, open the **Web CA** interface, create the CA, and ensure the server certificates have been exported. Return to the installer to continue validation.
6. The installer configures the IPVS-only mode and builds the OpenWrt/Unbound/IPVS stack. It then starts the auxiliary UI and DynDNS services if their Compose configurations are present.

### Web interfaces

| Service | Default URL | Purpose |
| --- | --- | --- |
| Web CA | `http://<SERVER-IP>:8080` | CA, certificates, and client management |
| Dozzle | `http://<SERVER-IP>:8081` | Docker status and logs |

Do not expose these interfaces directly to the public Internet without appropriate access controls and network restrictions.

## Certificate management

The Web CA maintains the certificate authority and generates the server credentials. The server export directory is expected to contain:

```text
web_ca/server_export/
├── ca.crt
├── server.crt
├── server.key
├── dh.pem
└── tls-crypt.key
```

The installer checks for these files and validates the CA/server certificates and matching server private key before continuing. **Protect `server.key`, CA private keys, and backups**: these are sensitive credentials.

Depending on the Web CA scripts installed, a server export may also run automatically after CA creation or on Web CA startup. The manual export remains available as a fallback.

## Optional services

### Dozzle

Dozzle is a lightweight interface for observing Docker containers and viewing logs. If configured with Docker actions, it can also start, stop, or restart containers.

```bash
cd ~/dozzle
bash ./build.sh   # If present
# or: docker compose up -d
```

Stop it with `bash ./down.sh` (if present) or `docker compose down`.

> [!CAUTION]
> Access to the Docker socket can grant powerful control over the host, even when the socket is mounted read-only. Restrict Dozzle to a trusted administration network and configure authentication as appropriate.

### ddclient

The `ddclient/` module provides optional dynamic DNS updates. Edit `ddclient/ddclient.conf` for your provider and hostname. Commented-out example credentials are **not active configuration**; a container can still emit warnings or restart until configured correctly.

```bash
cd ~/ddclient
docker compose up -d
```

Do not commit real DynDNS passwords or tokens to Git.

## Day-to-day operations

Inspect running containers:

```bash
docker ps
docker compose -f ~/dozzle/docker-compose.yml ps
```

Inspect the installation log:

```bash
sudo tail -n 100 /var/log/pnf-install.log
```

Start or stop individual modules using their local `build.sh` / `down.sh` scripts where available. Avoid removing Docker volumes or CA data unless you intend to destroy the associated state.

### Docker without `sudo`

The installer may add the invoking administrative user to the `docker` group. Re-login or run `newgrp docker` to activate the membership.

> [!WARNING]
> Membership in the Docker group is effectively equivalent to root-level access. Grant it only to trusted administrators.

## Backups

`backup.sh` creates a compressed archive of visible files and directories from the project home directory, including `backup.sh` itself. Dotfiles and hidden directories are excluded.

```bash
sudo ~/backup.sh
```

By default, the archive is written under `/tmp/pnf-backups/`. **Copy it off the VM before reverting a snapshot**: `/tmp` is not a durable external backup location. Also consider whether excluding hidden files is appropriate for your disaster-recovery needs.

## Status and limitations

- **Release stage:** Alpha.
- **Target OS:** Ubuntu Server 26.04.
- **Load balancer:** IPVS-only, TCP and UDP.
- **Installation:** interactive Web CA setup is required for a fresh deployment.
- **Security:** firewall rules, UI access, Docker permissions, and secret storage require administrator review.
- **Validation:** successful installation and VPN functionality depend on the host kernel, network configuration, and OpenWrt image.

## Contributing

Issues, reproducible bug reports, and improvements are welcome. When reporting an installer problem, include the relevant log excerpt, Ubuntu version, kernel version, and affected module. **Redact credentials, private keys, and public IP information you do not wish to share.**

## License

No license is specified in this README. Add a `LICENSE` file to define the project's usage and contribution terms.
