# Veira Seal — deploy

Everything needed to run your own Veira Seal instance: a Docker Compose
stack, a reverse-proxy example, and backup/upgrade scripts. This is a
generic secrets-vault deployment — it stores secrets for whatever projects
you point it at, not just Codeveira (a paid Codeveira licence happens to
unlock the paid Veira Seal tiers at no extra cost; see the main
[`../veiraseal`](../veiraseal) README's Licensing section).

## Requirements

- Docker Engine 24+ and the `docker compose` plugin (v2).
- A place to write two files outside of git: the master key file and the
  one-time recovery key. Losing both means the vault's data cannot be
  recovered — there is no backdoor, by design.

Before changing anything here, `make check` (or `./check.sh`) validates
`backup.sh`/`upgrade.sh` syntax and `docker-compose.yml` — no Docker
daemon required, just the CLI.

## Quick start

```sh
cp .env.example .env
$EDITOR .env   # set VEIRA_ADMIN_PASSWORD

make init      # creates the vault, prints the recovery key ONCE — save it offline
make up        # starts the server on 127.0.0.1:8200
make ps        # check it's healthy
```

Without `make`, the same three steps are:

```sh
mkdir -p data backup
chmod 777 data   # image runs as a fixed distroless nonroot UID (65532)
docker compose run --rm veira-init
docker compose up -d veira
docker compose ps
```

By default the port is bound to `127.0.0.1` only. Put a reverse proxy in
front for real TLS and a public hostname — see
[`nginx.conf.example`](nginx.conf.example) — or change the `ports:` line in
`docker-compose.yml` if you're terminating TLS elsewhere (a load balancer,
Cloudflare, etc).

## Alternative master-key sealers

The stack ships with the simplest option: a file-based master key
(`-keyfile` / `VEIRA_KEYFILE`), created once by `veira-init` and read by
`veira` on every start. Veira Seal also supports six other sealers — AWS
KMS, GCP KMS, Azure Key Vault, PKCS#11 (HSM/SoftHSM), a TPM 2.0 chip, age,
and Shamir secret-sharing (no key file at all; a quorum of printed shares
unseals the vault) — see the main [`../veiraseal`](../veiraseal) README's
CLI reference for the full flag list and `docs/api.md` for how each one
behaves operationally.

Switching sealers means changing **both** services, differently, because
the image is distroless (no shell) and `veira-init`'s `command:` is a
literal argument list while `veira`'s `server serve` is purely env-var
driven (`CMD ["server", "serve"]` in the Dockerfile — nothing to override
there):

- `veira-init`: edit `command:` in `docker-compose.yml` (or add a
  `docker-compose.override.yml` layering one on top), replacing
  `-keyfile /data/veira.key` with the new sealer's flags. For example, AWS
  KMS:

  ```yaml
  command: ["server", "init", "-db", "/data/veira.db",
            "-kms-ciphertext-file", "/data/veira.kms",
            "-kms-key-id", "alias/veiraseal", "-admin", "admin"]
  ```

  or Shamir (5 shares, 3 needed to unseal — printed once to the
  `docker compose run` output, nowhere else):

  ```yaml
  command: ["server", "init", "-db", "/data/veira.db",
            "-shamir", "-shares", "5", "-threshold", "3", "-admin", "admin"]
  ```

- `veira`: drop `VEIRA_KEYFILE` from `environment:` and set the matching
  variable instead (`VEIRA_KMS_CIPHERTEXT_FILE` + `VEIRA_KMS_KEY_ID` for
  the KMS example above, or `VEIRA_SHAMIR=1` for Shamir). Shamir is the one
  exception to "starts up unsealed": there's no key material on disk at
  all, so `veira` always comes up sealed and stays that way until each
  share-holder separately runs `veira unseal -share -addr <url>` (one
  invocation per share, up to the `-threshold` set at init) — there is no
  way to automate this at container start, by design. Fine for a vault
  you unseal by hand after every restart; plan around that before putting
  Shamir behind `restart: unless-stopped` in production.

KMS/GCP KMS/Azure Key Vault/PKCS#11/TPM each need their own credentials or
device access (cloud IAM role, `/dev/tpmrm0` passed through with
`devices:`, a PKCS#11 module mounted into the container, etc.) — that
wiring is specific to your infrastructure and out of scope for this
generic Compose file; the per-sealer flag docs in `../veiraseal`'s CLI
reference list exactly what each one needs.

## Configuring LDAP, Kerberos, e2ee and dynamic secrets

A few newer capabilities are **not** container-startup options at all —
they're configured through the HTTP API (or the `veira` CLI against a
running server) *after* the vault is initialized and unsealed, the same
way you'd create a user or a project:

- LDAP/FreeIPA directory login and group sync — `PUT /v1/ldap`
- Kerberos SSO — `PUT /v1/kerberos`
- End-to-end encryption recipients — the `.../e2ee` endpoints
- Dynamic secrets connectors (MongoDB/MySQL/Cassandra/Elasticsearch/PKI) —
  their own `/v1/.../connectors` endpoints

See `../veiraseal/docs/api.md` for the exact request/response shape of
each. There's nothing to add to `.env` or `docker-compose.yml` for these —
once `veira` is up, point `curl`/the CLI/Terraform provider at it like any
other admin operation.

## Where things live

```
./data/veira.db     the encrypted database (bind-mounted into the container)
./data/veira.key     the master key file — back this up separately from ./data
./backup/            timestamped snapshots from backup.sh / make backup
```

`veira.key` and the recovery key printed by `make init` are the only two
things that can unseal the vault. Keep at least one of them somewhere that
isn't this server (a password manager, an offline drive) — a disk failure
that takes `./data` with it also takes the key file.

## Updating

```sh
make upgrade   # backs up, then pulls IMAGE_TAG from .env and recreates the container
```

Or pin a specific version:

```sh
./upgrade.sh 0.2.0
```

`upgrade.sh` refuses to pull/recreate if the backup step fails, so a bad
upgrade never costs you your last good snapshot.

To roll back, set `IMAGE_TAG` in `.env` back to the previous tag and
`make up` — the on-disk format is stable across patch/minor versions
within a major version (see `../veiraseal/DECISIONS.md` upstream, if you
have access to it, or the release notes for the tag you're rolling back to).

See [`CHANGELOG.md`](CHANGELOG.md) for what changed in this deployment
stack itself (Compose file, scripts, Makefile) across versions.

## Backup & restore

```sh
make backup                 # snapshot -> ./backup/veira-<timestamp>.db
```

To restore: stop the stack, replace `./data/veira.db` with a snapshot from
`./backup/`, then `make up` with the original `./data/veira.key` (or the
recovery key, via `veira server backup`'s companion `UnsealWithRecovery`
path documented in the main README) still in place. Backups are encrypted
ciphertext-only — a stolen backup file is useless without the key.

## Monitoring (optional)

A ready-made Prometheus + Grafana stack, merged on top of the base compose
file:

```bash
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d
```

One-time setup: set `GRAFANA_ADMIN_PASSWORD` in `.env`, and make sure your
licence is Extended tier or higher — `/metrics` is a paid feature (see
`../veiraseal/docs/api.md`'s Metrics section); on Free/Standard the scrape
just gets a `403` and every panel stays empty.

Grafana comes up at `:3001` (`admin` / `GRAFANA_ADMIN_PASSWORD`) with the
**Veira Seal — Overview** dashboard already provisioned — no manual
datasource or import step. It covers vault seal state, user/project counts,
licence info, and HTTP request/auth-failure/rate-limit rates. Prometheus
itself is exposed at `:9090` for ad-hoc queries.

Unlike a typical scraped app, no token or credential file is needed:
`/metrics` is gated by the licence check alone, so the plain
`monitoring/prometheus.yml` scrape config just works.

## Security notes

- Never put `VEIRA_ADMIN_PASSWORD`, the master key, or the recovery key
  into `.env` beyond the one-time init step above — `.env` is read by
  `docker compose` on every command and is easy to accidentally commit or
  log. The admin password in `.env` is only read once, by `veira-init`.
- Set `VEIRA_TRUST_PROXY=1` in `.env` **only** if the nginx (or equivalent)
  in front of this container is the sole path to it — otherwise a client
  can spoof its own IP in the audit log and dodge the rate limiter via
  `X-Forwarded-For`.
- The container ships as a distroless, non-root, shell-less image on
  purpose; everything above works through Compose/env vars, never through
  `docker exec sh` into the container.
