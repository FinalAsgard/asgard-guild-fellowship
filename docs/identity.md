# Identity: the people behind the characters

Asgard's Guild Fellowship turns your guild roster into **people**. It reads short markers in guild notes to work out which characters belong to the same person. It then shows who someone is in chat, in tooltips, and through `/gf who`.

Everything here works on **WoW: Forever** and **Retail**.

## The guild note convention

Identity comes from each character's **public** guild note. Officer notes aren't used.

| In the note | Meaning | Example |
| --- | --- | --- |
| `>Ref` | This character is an alt of `Ref`. | Malgen Zelwindran's note: `>Dresden` |
| `@Alias` | On a main's note: what this person wants to be called. One word. | Dresden Zelwindran's note: `@Zel` |

- **First name is enough** when it's unique in the guild: `>Dresden` links to Dresden Zelwindran. If two characters share the first name, write the full name: `>Dresden Zelwindran`.
- **Retail cross-realm guilds:** if the same name exists on two realms, add the realm without spaces: `>Thrall-Area52`.
- **Other text is kept.** `Raid lead @Zel` and `tank >Dresden` both work. A capitalized word right after `>Name` is read as a last name, so put other text before the marker.
- **The old format still works.** `main: Dresden` and `alias: Zel` (any capitalization) are read too. `disc: …` is left alone.
- **The note limit is 31 characters.** The Note Helper (below) writes notes for you and won't write one that doesn't fit.

### How a person is named

- A person is their **main** plus every alt that points at it. Characters with no marker are a person of their own.
- **Display name:** the main's `@Alias`, else the alias from their profile, else the main's first name (or full name if the first name is shared).
- **Renames are safe:** a person is tied to their main's character ID, so renaming the main keeps everything once alts' notes are updated.
- **Messy notes are handled:** an alt that points at another alt follows through to the real main. Notes that point at each other, point at someone who left, or match nobody are left unlinked and shown to officers as issues.

## What you see

- **Chat tag:** a guildmate's alt shows who they are at the start of the message: `[Guild] [Malgen Zelwindran]: [Zel] Anyone want to run a dungeon?`
  - A main gets a tag only if they have an alias.
  - It works in guild, officer, party, raid, instance and whisper chat, and only for guildmates.
  - The clickable name is untouched, so whisper, invite and report work as usual.
- **Tooltips:** hovering a guildmate (in the world, on unit frames, or in the guild roster) shows:
  - who they are and which character they're playing,
  - their main and other characters, with level, class and online status,
  - their Discord name and bio.
- **`/gf who <name>`:** look someone up by character name, first name or alias. It lists their characters (level, class, online/zone), Discord name and bio.

Slash commands: `/fellowship` and `/agf` always work. `/gf` works too unless another add-on already uses it.

| Command | What it does |
| --- | --- |
| `/gf` | Opens the main panel |
| `/gf who <name>` | Looks up a guildmate |
| `/gf notes` | Opens the Note Helper |
| `/gf roster` | Opens the Guild Roster: the whole guild grouped by person, online people first |
| `/gf status <status\|clear>` | Sets or clears what you're up for (see [Discovery](discovery.md)) |
| `/gf clear <bio\|alias> <name>` | Addon officers: clears someone's bio or profile alias |
| `/gf version` | Prints the add-on version |

Greeting guildmates who log in or join is covered in [Guild Greet](guild-greet.md). Finding guildmates to play with, and saying what you're up for, is covered in [Fellowship Discovery](discovery.md). Seeing the whole guild grouped by person is covered in [Guild Roster](roster.md). Saying what you'll help guildmates with is covered in [Helping and Mentoring](helping.md).

## Your profile

In **Settings → Asgard's Guild Fellowship → My profile** you can set:

- **Discord name** (up to 32 characters). This is **contact info only**: guildmates see it labelled as Discord. It's never used as your name, your tag, or a search term.
- **What to call me** (up to 24 characters). This is your alias if your main's note doesn't set one with `@Alias`. The note always wins.
- **About me** (up to 200 characters). A short bio shown in `/gf who` and, shortened, in tooltips.
- **I can help with**: topics you're willing to help guildmates with (see [Helping and Mentoring](helping.md)).

You can edit your profile from any of your characters. It's shared with guildmates who use the add-on, including while you're offline.

## Officer tools

**Addon officers** are, by default, the guild master's rank plus any rank that can edit officer notes. An officer can change this under **Settings → Guild settings** and press **Publish to guild**. Everyone else sees the setting read-only.

- **Identity Issues** (main panel, officers only) lists every note problem by type, with the affected characters, the note text, and a suggested fix. Problem types: ambiguous, unresolved, orphaned (main left), alt-to-alt, and circular. It updates live as notes change.
- **Note Helper** (`/gf notes`, the main panel, or **Fix in Note Helper** on an issue):
  - Link an alt to its main, or set a main's alias, by picking characters.
  - It writes the shortest unambiguous name, keeps other note text, previews the result, and refuses notes that don't fit.
  - It only offers notes you're allowed to edit: your own, or anyone's if your rank can edit public notes.
- **Clearing a profile:** `/gf clear bio <name>` or `/gf clear alias <name>` blanks an inappropriate bio or profile alias. Officers can't write new text into someone's profile, and the owner can set new content afterwards.

## Sharing between add-on users

Guildmates who run the add-on quietly share:

- identity links (so a new user immediately gets the same answers for ambiguous notes),
- profiles,
- the guild settings,
- what each person is up for ([availability](discovery.md), short-lived and never saved).

Sync uses one hidden add-on channel. It's light and rate-limited, and it can be turned off under **Settings → Sync with other add-on users**.

Shared data is trusted as passed along, with a few checks:

- A link is only accepted if it fits the guild notes as the receiver sees them.
- A profile change or availability status must come from one of that person's own characters.
- Guild settings and profile clears must come from an addon officer.

## Saved data

Settings are per profile. Everything about a guild (links, profiles, guild settings) is stored **per guild**, so characters in different guilds never mix data.
