# Changelog

## 2026-10-22

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
