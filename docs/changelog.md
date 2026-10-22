# Changelog

## 2026-10-22

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
