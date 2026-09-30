# Pipeline Config

`/auto-process-prd` reads this file for the project-specific commands and checks it would otherwise have to guess.

## Test Command

`luacheck . && busted`

> Not set up yet. The first implementation issue should add `.luacheckrc` (declaring WoW API globals), `.busted`, and a `spec/` folder so this command runs cleanly.

## CI Check Name

`test`

> Not set up yet. The first implementation issue should add a GitHub Actions workflow with a job named `test` that runs the test command above.

## Code Review Checks

- coderabbit
- adversarial

> CodeRabbit must be installed on `jonzenor/asgard-guild-fellowship` for the `coderabbit` check to work.

## Base Branch

`main`
