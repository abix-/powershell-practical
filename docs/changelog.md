# Changelog

## 2026-10-22

- Added a read-only RouterOS inventory diagnostic and live acceptance script.
  Uses strict SSH host verification, retains allowlisted fields only, and
  records missing tables as unverified. Live router identity and required
  discovery tables passed. Inventory data stays outside the repository;
  device security and firmware remediation require separate verification.
