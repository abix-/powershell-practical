# Changelog

## 2026-10-22

- Added official patch-artifact staging with Node SHA256/Authenticode and PyPI
  wheel hashes; verifies portable fixed Node against the fifteen-host matrix
  without installing runtimes. Added read-only OpenAI app package/update metadata
  and official MSIX candidate inspection, keeping installed and detached-runtime
  conclusions separate from candidate availability.

- Added targeted Plex/PHP/runtime inventory, Python package metadata without
  executing Python, and public-host trust checks for installed curl clients and
  isolated Node bundled defaults. Includes fourteen incident chains and a valid
  control, explicit unknown results and private evidence with hashes. No runtime
  installation, trust-store change or stopped-WSL startup.

- Added read-only Windows update readiness: build, public ESU license status,
  services/policy, disk space, restart indicators, history and offered/hidden
  update searches. No update installation, activation or reboot operations.
- Added exact OneLog release firewall rule/filter backup and a data-only
  restriction proposal with inverse parameters. Captures adapted NetSecurity
  aliases and excludes debug/test rules; no firewall writes are invoked.

- Added read-only event-log coverage evidence for historical investigations:
  live retention bounds, standard EVTX archives and existing shadow copies.
  Missing history remains an explicit gap instead of a clean result.

- Separated Windows account/audit changes, authentication failures and remote
  logins into independent bounded queries. Added selected time bounds, package
  and service firewall conditions, and a focused elevated collection mode.

- Added Windows trust evidence using public certificate metadata and all
  eMudhra intermediate/cross-sign chain decisions without importing certificates
  or reading private keys. Preserves explicit distrust separately from other
  chain failures; application runtime validation remains a separate check.

- Added read-only Windows security triage with bounded structured events,
  explicit visibility gaps, account/startup/network metadata and executable
  hashes/signatures. Evidence stays private and existing reports are preserved.
- Extended router discovery with opt-in security evidence. Explicit field
  reads preserve account logs and persistence metadata without reading script
  bodies, event actions or secrets. Compromise flags are observations only.

- Added read-only updater status to distinguish downloads from an installed
  upgrade. Verified installed RouterOS and package versions after the
  operator's update; RouterBOOT is checked separately.

- Extended router inventory with RouterBOOT versions and free storage/memory
  for upgrade preparation, without retaining board serial numbers.

- Added a read-only RouterOS inventory diagnostic and live acceptance script.
  Uses strict SSH host verification, retains allowlisted fields only, and
  records missing tables as unverified. Live router identity and required
  discovery tables passed. Inventory data stays outside the repository;
  device security and firmware remediation require separate verification.
