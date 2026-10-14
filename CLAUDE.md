<!-- xpo:begin 1.4.0 sha256:e41789a7f757 -->
## Exponential (xpo)

This project uses `xpo` (Exponential) via the MCP server registered in `.mcp.json`.
Always use the MCP tools — never shell out to the `xpo` CLI.

Issue IDs in this project use the prefix `cs` (e.g. `cs-a1b2c3`).

### Hard Rules

1. Every code change must be backed by an xpo issue transitioned to DOING before any file is modified.
2. Never start work on a BACKLOG issue without explicit user approval to transition it.
3. Bugs discovered during implementation may be filed and fixed without approval — file the issue, link it to the current work, and fix it.
4. Before beginning any implementation task, load the `xpo` skill and follow it.
5. If an MCP tool call fails, report the error to the user. Never fall back to the CLI.

<!-- xpo:end -->

## Development practice

The product spec is `spec.md`. Each issue's spec refines it.

### Test-driven development

All work follows TDD:

1. **Tests first.** Turn the issue spec's acceptance criteria, flows and edge cases into tests before
   writing any implementation.
2. **Red.** Run the tests and confirm they fail for the expected reason. A test that passes before
   the implementation exists tests nothing.
3. **Green.** Write the simplest implementation that makes the tests pass.
4. **Refactor.** Clean up with the tests green.

Put logic in `ColorsipCore` (Swift Testing, `swift test` in `Packages/ColorsipCore`) so it can be
tested this way. Keep the app target a thin layer over it. If a behavior can't be covered by an
automated test (for example screen capture or event taps), say so in the completion comment and
describe how it was verified by hand.
