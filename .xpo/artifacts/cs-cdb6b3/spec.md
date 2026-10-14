## What

Add a root `Makefile` that gives contributors discoverable shortcuts for the project's existing build and test workflows.

## Why

The repository currently requires contributors to remember or look up the underlying Swift commands. A small Makefile provides a stable, self-documenting entry point without changing the build system itself.

## How

- Inspect the repository's existing build/test configuration after the issue worktree is created.
- Add a root `Makefile` with a default help target and thin targets for the canonical build and test commands already used by the project.
- Mark non-file targets as phony and keep command output/help concise.
- Do not add new dependencies or duplicate build logic.

## Acceptance Criteria

- Running `make` prints the available targets and a short description of each.
- A build target invokes the repository's canonical build command.
- A test target invokes the repository's canonical automated test command.
- Target commands propagate failures with a non-zero exit status.
- The Makefile itself is validated, and the project's tests pass.

## Assumptions

- The Makefile should be a thin convenience layer, not replace Swift Package Manager or Xcode configuration.
- The initial target set should stay minimal: help, build, and test, with additional targets only if the repository already has an obvious canonical workflow that belongs alongside them.

## Open Questions

None.