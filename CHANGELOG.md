# Changelog

All notable changes to this deployment stack are documented here. See
`../veiraseal` for the application's own release notes.

## [Unreleased]

### Added
- `Makefile`: `deploy` target — the one command for the whole deploy
  operation (backup, pull `IMAGE_TAG`, recreate, wait for healthy), so the
  steps don't have to be assembled by hand or by a CI/CD job. `upgrade` is
  kept as an alias of `deploy`.
- README: "Alternative master-key sealers" section — how to switch
  `veira-init`/`veira` from the default `-keyfile` to AWS KMS, GCP KMS,
  Azure Key Vault, PKCS#11, TPM, age or Shamir (including Shamir's
  always-sealed-at-startup, manual-`veira unseal -share`-per-holder
  behaviour, which has no unattended-restart story by design).
- README: "Configuring LDAP, Kerberos, e2ee and dynamic secrets" section
  pointing at `../veiraseal/docs/api.md` — these are post-init HTTP
  API/CLI operations, not Compose/env-var options, so there was nothing
  to add to `.env.example` or `docker-compose.yml` for them.
- Initial Compose stack: `veira-init` (one-shot vault creation) + `veira`
  (long-running server), bound to `127.0.0.1:8200` by default.
- `nginx.conf.example` for TLS termination in front of the vault.
- `backup.sh` — on-demand encrypted snapshot into `./backup/`.
- `upgrade.sh` — backup-then-pull-then-recreate, fails safe (never touches
  the running container if the backup step fails).
- `Makefile` with `init`/`up`/`down`/`backup`/`upgrade`/`logs`/`ps` targets.
- `check.sh` — validates `backup.sh`/`upgrade.sh` syntax and
  `docker-compose.yml`, no Docker daemon needed (`make check`).
- `deploy.lock` guard (flock) in `backup.sh`/`upgrade.sh` — refuses to run
  a second deploy operation concurrently instead of racing the same
  `./data` bind mount (e.g. a cron backup firing mid-upgrade).
- `docker-compose.monitoring.yml` — optional Prometheus + Grafana overlay
  scraping the server's `/metrics` endpoint (Extended+ licence), with a
  provisioned "Veira Seal — Overview" dashboard. `make monitoring-up` /
  `make monitoring-down`.
