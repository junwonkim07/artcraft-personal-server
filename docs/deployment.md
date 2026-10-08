# Choose a deployment target

Run the same private ArtCraft stack on the host you prefer. The selector does not create a paid server or change an existing installation until you explicitly use `--apply`.

| Target | Installation option | Verification |
| --- | --- | --- |
| Vultr | Ubuntu installer or generated cloud-init | Core stack tested on a Vultr Ubuntu 24.04 VPS; new installer checked without provisioning |
| Hetzner Cloud | Ubuntu installer or generated cloud-init | Configuration and selector checks; no Hetzner instance provisioned |
| Hetzner Dedicated / Server Auction | Ubuntu installer after OS installation | Configuration and selector checks; no dedicated hardware test |
| Other VPS / own machine | Ubuntu installer | Ubuntu 24.04 x86_64 only for this installer |
| Vercel | Architecture guidance only | No full-stack deployment preset |
| Neon | Migration guidance only | No PostgreSQL support in the current application |

## Interactive installer

Create an **Ubuntu 24.04 x86_64** server with an SSH key and at least 4 vCPU, 8 GB RAM plus 8 GB swap, and 40 GB free disk. Allow SSH in your provider firewall. Use the [Ubuntu guide](ko/install.md) to configure SSH and swap; ARM hosts and Rescue environments are not supported by this installer.

SSH to that server, then:

```bash
git clone https://github.com/junwonkim07/artcraft-personal-server.git
cd artcraft-personal-server
./scripts/deploy.sh
```

Choose a target to see the plan. To install the selected target:

```bash
# Example: run ON your Hetzner server, not on your laptop.
sudo ./scripts/deploy.sh --provider hetzner-cloud --apply --install-docker
```

Supported full-stack provider names: `vultr`, `hetzner-cloud`, `hetzner-auction`, `ubuntu`. Provider selection changes setup guidance; all four deliberately use the same portable Compose stack and storage layout.

The installer checks the OS, optionally installs Docker from its official apt repository, raises the Elasticsearch kernel setting if needed, creates secrets only when absent, builds the images, starts the services, and checks health and storage access. It refuses partial secret configurations. Existing Docker installations are reused; missing Compose or conflicting packages require manual correction. It does not format disks, configure RAID, change SSH, or open internet-facing application ports.

On your computer, keep this running:

```bash
ssh -N -L 4201:127.0.0.1:4201 YOUR_SSH_USER@YOUR_SERVER
```

Open **http://localhost:4201** and create an account. Accounts belong to this installation; your hosted ArtCraft login is separate.

## Cloud-init: Hetzner Cloud and Vultr

Generate a startup configuration locally using a **published commit** from this repository. A fork must update the repository URL in the renderer before use.

```bash
git pull --ff-only
./scripts/cloud-init.sh hetzner-cloud "$(git rev-parse HEAD)" > cloud-init.yml
# For Vultr, replace hetzner-cloud with vultr.
```

Review the generated file, then paste it into the provider's cloud-init/user-data field when creating the server. Choose Ubuntu 24.04 x86_64, select your SSH key and firewall, and review the provider's charges before creating it. This repository does not submit a purchase for you.

The file installs prerequisites, creates 8 GB swap, checks out the exact template commit, and runs the installer in `/opt/artcraft-personal-server`. Secrets are generated on the server rather than embedded in user data. The first build may take an hour; do not interrupt it just because SSH is already available.

```bash
sudo cloud-init status --wait
sudo tail -f /var/log/artcraft-deploy.log
# If provisioning failed before the installer:
sudo tail -n 100 /var/log/cloud-init-output.log
```

To retry after resolving a build or network failure:

```bash
cd /opt/artcraft-personal-server
sudo ./scripts/deploy.sh --provider hetzner-cloud --apply --install-docker
```

Existing credentials are preserved. Cloud-init does not add a non-root user or harden SSH for you: complete the SSH setup in the [Ubuntu guide](ko/install.md), verifying key access before disabling password/root login.

## Hetzner Dedicated / Server Auction

Auction servers use **Robot / Rescue / installimage**, rather than the Hetzner Cloud user-data flow. Install Ubuntu 24.04 on the hardware first, then reboot into the installed OS and use:

```bash
sudo ./scripts/deploy.sh --provider hetzner-auction --apply --install-docker
```

OS installation and disk/RAID choices are separate from ArtCraft. Follow [Hetzner's installimage guide](https://docs.hetzner.com/robot/dedicated-server/operating-systems/installimage/) and [Auction FAQ](https://docs.hetzner.com/robot/general/server-auction-faqs/). Reinstalling an OS can erase disks; this template never invokes installimage. Cloud-init output from this repository is not an Auction provisioning script.

## Vercel: a different deployment architecture

Vercel now supports [container images in Functions (Beta)](https://vercel.com/docs/functions/container-images), but this is not a persistent Docker Compose host. The current stack includes a long-running Rust API, MySQL, Redis, Elasticsearch and MinIO with local persistent volumes. Vercel's [function constraints](https://vercel.com/docs/functions/limitations) also matter for media uploads and background work.

A future Vercel split would require:

- A separately hosted frontend or API container, with external MySQL, Redis, Elasticsearch and S3-compatible storage.
- Public HTTPS routing, explicit trusted origins, session-cookie review and browser-facing media URLs. The existing localhost development CORS setup is not a public deployment preset.
- Migrations and background processes outside request execution, plus upload-size and lifecycle testing.

The selector explains this and exits without modifying anything. We do **not** provide a misleading “Deploy to Vercel” button that deploys an unusable frontend. Use a supported Ubuntu target for the complete working stack today.

## Neon: PostgreSQL migration required

[Neon is PostgreSQL](https://neon.com/docs/reference/compatibility). The upstream ArtCraft backend uses MySQL-specific drivers, queries and migrations. A Neon connection string cannot replace `MYSQL_URL`.

A future Neon implementation needs a database-driver and SQL/migration port, a tested [MySQL data migration](https://neon.com/docs/import/migrate-mysql), and regression tests for accounts, roles, sessions and media metadata. Redis, search and file storage still need separate services. Selecting `neon` explains this limitation and exits without changing the current database.

## Moving an existing installation

Provider selection installs a new server; it is **not** a migration command. Back up the old server, copy the backup securely to the new server, and use the [restore guide](ko/backup-restore.md). Verify accounts and media on the destination before changing your tunnel or retiring the old host. Do not generate new credentials for an existing database volume.

## Validation

Run `bash tests/deployment-selection.sh` to check supported plans, unsupported targets, and cloud-init commit validation without cloud credentials or host mutations. Generated cloud-init is also schema-checked during development. Full provisioning on Hetzner and Vercel/Neon migrations have **not** been tested.

Official provider references were reviewed on 2026-10-08; see the Vercel, Neon and Auction documentation linked above.
