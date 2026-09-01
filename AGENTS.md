Say true things. State uncertainty plainly.

=nixit= is intentionally small:

- Implementation lives here.
- Ticket orchestration and evidence live in the orphan =.tickets/= worktree
  on =codex/tickets=. Use =bin/tickets= and read =docs/tickets.org= first.
- Build artifacts must stay untracked.
- A repository flake may declare development and smoke-tool dependencies.
- Do not add host package installation, VM lifecycle management, secrets, or
  agent toolchain provisioning to this repo.

Prefer explicit inputs over ambient host state. If a command depends on Nixpkgs,
make the selected source visible.
