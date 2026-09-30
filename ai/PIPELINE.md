# Pipeline Config

`/auto-process-prd` reads this file for the project-specific commands and checks it would otherwise have to guess.

## Test Command

`luacheck . && busted`

> Lua 5.1 tooling. Locally, busted and luacheck live in `~/.luarocks/bin` (see README → Development); make sure it's on `PATH`.

## CI Check Name

`test`

> The `test` job in `.github/workflows/test.yml`. The same workflow also runs a **Release package** job that builds and validates the zip.

## Code Review Checks

- coderabbit
- adversarial

> CodeRabbit must be installed on `jonzenor/asgard-guild-fellowship` for the `coderabbit` check to work.

## Base Branch

`main`
