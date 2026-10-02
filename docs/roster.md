# Guild Roster

The game's own roster lists **characters**: Dresden, Shiro, Malgen, Bob, Bobadin, Bobmage… The **Guild Roster** lists **people**, so in a guild full of alts you can see at a glance:

- who is online,
- which character they're on,
- what else they play.

It builds on [Identity](identity.md) (people, aliases, alts) and shows what people are up for from [Availability](discovery.md).

## Opening it

- Type `/gf roster`, or
- click **Open Guild Roster** in the main panel (`/gf` or the minimap button).

## What it shows

The header counts the whole guild: **12 of 40 people online (15 characters)**. Then each person gets an entry:

> **Final · online as Shiro (Elwynn Forest) · Up for Dungeons**
> &nbsp;&nbsp;&nbsp;&nbsp;Dresden — Mage 60 (main, offline) · Malgen — Warrior 20 (offline) · Shiro — Paladin 34
> **[Whisper Shiro]**
>
> **Bob · offline**
> &nbsp;&nbsp;&nbsp;&nbsp;Bob — Hunter 60 (main) · Bobadin — Paladin 45

- **Headline:**
  - the person's display name (their alias, if they have one)
  - which character they're on and where, or *offline*
  - what they're up for, if they've set a status
- **Characters:** every character they have, with the main first and marked **(main)**, plus class and level. For someone who's online, the characters they *aren't* on are marked **(offline)**, so you can tell which one they're playing.
- **Order:** online people first, then alphabetical. Offline people are greyed.
- **Whisper:** online people other than you get a button. It opens the chat box with a whisper already addressed to the character they're on. You type and send it yourself; the add-on never sends anything.

The roster updates while it's open as people log in or out, switch characters, change zone, level up, set a status, or as guild notes change.

## Finding people

- **Search (name or alias):** type a character's name, a first name, a full `Name-Realm`, or an alias, then press **Enter**. It matches the same way as `/gf who`, so it's not case-sensitive and quotes and extra spaces are ignored. If nobody matches, a **Clear search** button brings everyone back. The search is cleared when you reload.
- **Show offline people:** untick it to see only who's online. It's on by default and remembered between sessions. The header count always covers the whole guild.

## Notes

- The roster doesn't change anything, and it doesn't use any extra sync. It shows what the guild roster, guild notes, and shared statuses already say.
- Use the [Note Helper](identity.md#officer-tools) (`/gf notes`) to fix who belongs to whom.
