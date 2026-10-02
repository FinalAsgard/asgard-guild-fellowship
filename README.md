# Asgard's Guild Fellowship

A World of Warcraft add-on that helps guild members know each other, recognize each other, find each other, and actually play together. It turns a roster of characters into a community of people.

> Early development. See [`ai/VISION.md`](ai/VISION.md) for the product vision and the open `prd` issues for what's being built.

## Features

**Identity.** Short guild-note markers (`>Main` on alts, `@Alias` on mains) let the add-on group characters into people. It then shows who's who in chat tags, tooltips, and `/gf who`. It also includes:

- synced profiles (Discord contact, alias, bio),
- an Identity Issues view and Note Helper for officers,
- quiet sync between add-on users.

See [`docs/identity.md`](docs/identity.md) for the note convention and how to use it.

**Guild Greet.** When guildmates come online or someone joins the guild, a small prompt offers to greet them. One click posts a varied, personal greeting. It greets people rather than alts, combines arrivals into one line, and lets at most two add-on users greet the same person. Off by default. See [`docs/guild-greet.md`](docs/guild-greet.md).

**Fellowship Discovery.** The main panel lists online guildmates you could play with. It includes alts within a few levels of yours, even offline ones, with tank and healer hints, filters, and a one-click whisper. Everyone can say what they're up for (questing, dungeons, PvP, helping, anything, busy) from the minimap button's right-click or `/gf status`. Statuses are shared with guildmates and clear themselves after 2 hours or at logoff. See [`docs/discovery.md`](docs/discovery.md).

**Guild Roster.** `/gf roster` shows the whole guild grouped by person: who's online and on which character, every alt with class and level, aliases and statuses. It has search and a show-offline toggle. See [`docs/roster.md`](docs/roster.md).

**Helping and Mentoring.** Members tick what they're willing to help with (new players, class questions, tanking, healing, quests, dungeons, PvP, professions, mentoring). Guildmates find them with a **Can help with** filter in the Guild Roster and Discovery. See [`docs/helping.md`](docs/helping.md).

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
