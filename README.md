# Asgard's Guild Fellowship

A World of Warcraft add-on that helps guild members know each other, recognize each other, find each other, and actually play together. It turns a roster of characters into a community of people.

> Early development. See [`ai/VISION.md`](ai/VISION.md) for the product vision and the open `prd` issues for what's being built.

## Supported clients

| Client | Manifest | Interface |
| --- | --- | --- |
| World of Warcraft: Forever | `AsgardsGuildFellowship_Camelot.toc` | `16000`, `16001` |
| World of Warcraft Retail | `AsgardsGuildFellowship_Mainline.toc` | `120100` |

Classic clients are not supported.

## Development

Tests use [busted](https://lunarmodules.github.io/busted/), and linting uses [luacheck](https://github.com/lunarmodules/luacheck), both on Lua 5.1 (the WoW Lua version):

```sh
luacheck . && busted
```

On macOS, one way to install them:

```sh
brew install luajit luarocks
luarocks --lua-version=5.1 --lua-dir="$(brew --prefix luajit)" --local install busted
luarocks --lua-version=5.1 --lua-dir="$(brew --prefix luajit)" --local install luacheck
export PATH="$HOME/.luarocks/bin:$PATH"
```

CI runs the same command (the `test` check) on every pull request, and builds the release package.

Tests load add-on files through a small WoW API stub harness (`spec/support/wow.lua`). It stubs only the APIs the add-on calls, so add a stub there when new code calls a new API. `spec/support/fake_libs.lua` stands in for the embedded libraries.

Embedded libraries (Ace3, LibDeflate, LibDataBroker, LibDBIcon) are vendored in `Libs/` at pinned versions, so a plain checkout loads in game. See [`Libs/README.md`](Libs/README.md). Feature screens go through the internal UI layer (`Core/UI.lua`), never AceGUI directly.

To update a client's interface version, run `tools/set-interface.sh <forever|retail> <interface>`.

## Releases

Publishing a GitHub release tagged `vX.Y.Z` builds the add-on, versions it from the tag, and attaches the zip to the release. Once the CurseForge project exists, it also uploads to CurseForge. See [`docs/packaging.md`](docs/packaging.md).

## License

MIT. See [LICENSE](LICENSE).
