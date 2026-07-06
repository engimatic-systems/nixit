Say true things. State uncertainty plainly.

=nixboxes= is intentionally small:

- Implementation lives here.
- Ticket orchestration and evidence live in =sys=.
- Build artifacts must stay untracked.
- Do not add host package installation, VM lifecycle management, secrets, or
  agent toolchain provisioning to this repo.

Prefer explicit inputs over ambient host state. If a command depends on Nixpkgs,
make the selected source visible.
