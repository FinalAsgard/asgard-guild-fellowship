# Fellowship Discovery and Availability

Discovery answers one question: **who could I play with right now?** It lists online guildmates by person, not by character. That way you notice people you'd otherwise miss:

- the friend on their max-level main who has a Warrior at your level,
- the person who just said they're up for a dungeon.

Availability lets each player say what they're up for, so the list shows who wants to play, not just who's online.

It builds on [Identity](identity.md), which provides people, display names, alts, and sync between add-on users.

Discovery doesn't do matchmaking: no auto-invites, no pings, no posts in chat. It only helps you notice opportunities.

## Saying what you're up for

Set your status in any of three ways:

- **Right-click the minimap button.** A **What are you up for?** menu shows your current status ticked. Left-click still opens and closes the main panel.
- **The main panel.** Use the **My status** dropdown at the top of Discovery.
- **The slash command.** Type `/gf status <questing|dungeons|pvp|helping|anything|busy|clear>`. With no word after it, `/gf status` tells you your current status.

| Status | Meaning |
| --- | --- |
| Questing, Dungeons, PvP, Helping, Anything | Ask me! |
| Busy | Don't suggest me; I'm hidden from guildmates' Discovery lists by default |
| Clear | No status |

How a status behaves:

- **It belongs to you, not your character.** Set it on any of your characters and it covers all of them.
- **It's shared** with guildmates who use the add-on, straight away. Anyone who logs in later gets it within a minute or so.
- **It clears itself.** A status lasts **2 hours** and ends when you log off, so nobody ever sees a stale one. Logging back in doesn't bring it back.
- **It isn't saved** on your computer. After a `/reload`, guildmates who still have your status send it back.

To keep your status to yourself, turn off **Settings → Share my availability**. It still shows for you, but nothing is sent. A status you already shared isn't recalled; it runs out as usual. Sharing also needs **Sync with other add-on users** on.

## The Discovery list

Open the main panel (`/gf`, or click the minimap button). **Discovery** is at the top, and each online guildmate gets a row:

> **Mike — Magus, Mage 60 · Up for Dungeons · Orgrimmar**
> &nbsp;&nbsp;&nbsp;&nbsp;At your level: Tanky, Warrior 34 [Tank] (offline)
> **[Whisper Magus]**

- **Who and where.** Each row shows their display name, the character they're on, what they're up for, and their zone.
- **At your level.** Any of their characters within **3 levels** of your current character is listed, even if offline. On Retail at the level cap, only other capped characters count.
- **Roles.** **[Tank]**, **[Healer]** or **[Tank/Healer]** show which classes can fill those roles. They're a hint from class only; specs aren't detected.
- **Whisper.** The button opens the chat box with a whisper already addressed to the character they're on. You type and send it yourself; the add-on never sends anything.
- **Order.** People up for something come first, then people with a character at your level, then everyone else by name. Busy people, if shown, come last.
- **Who's left out.** You and your own alts are never listed, and neither is anyone with every character offline.

The list updates while the panel is open as people log in or out, change zone, level up, or change status.

### Filters

Above the list:

| Filter | Shows |
| --- | --- |
| **Up for** | Only people with that status. Picking **Busy** shows Busy people. |
| **Can fill** | Only people with a Tank- or Healer-capable character at your level (offline alts count) |
| **Same zone as me** | Only people whose current character is in your zone |
| **Show Busy** | Include people who set Busy |

Filters are saved, so they're still set after a reload.

## Settings

Under **Settings → Asgard's Guild Fellowship → Feature toggles**:

| Setting | Default | What it does |
| --- | --- | --- |
| **Discovery level range** | 3 | How many levels above or below your character count as "at your level" (1–10) |
| **Share my availability** | On | Whether guildmates see your status |

## Sharing and trust

A status travels over the same quiet add-on channel as the rest of sync. A guildmate's add-on accepts it only if:

- it comes from one of that person's own characters (anyone may pass it along),
- it hasn't expired, and claims to last no more than 2 hours,
- that person is online in the receiver's roster.

A status from a newer version of the add-on that this version doesn't know is ignored.
