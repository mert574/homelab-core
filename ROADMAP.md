# Roadmap

## Recovery and backups

- Automate encrypted, off-box backups for Postgres, Garage, Vaultwarden, and the
  configuration needed to rebuild the host.
- Add restore drills using disposable guests and synthetic data. Verify database
  contents, object checksums, and application startup after restoration.
- Document recovery from a lost host or disk, including age-key recovery and
  the order in which services must be restored.

## Reusable site configuration

- Move host addresses, domains, guest resources, and SSH public keys into a shared
  site configuration consumed by OpenTofu, NixOS, and cluster manifests.
- Provide an example site with dummy secrets so another user can validate the
  configuration without the private homelab key.
- Check for duplicate addresses, overlapping guest IDs, and inconsistent service
  endpoints before provisioning.

## Provisioning and rollback tests

- Exercise bootstrap scripts against command stubs in CI, covering missing
  prerequisites, interrupted provisioning, and repeated runs.
- Add a disposable Proxmox test environment for guest creation, configuration,
  service health checks, and cleanup.
- Verify that a failed deployment preserves the previous working configuration
  and document how to roll back each layer.

## Operations

- Add alerts for backup failures, low disk space, certificate/tunnel failures,
  and unavailable services.
- Test secret rotation for database credentials, tunnel credentials, and CI
  access without rebuilding unrelated guests.
- Pin remaining mutable container images and add a documented update process
  with validation and rollback checks.
