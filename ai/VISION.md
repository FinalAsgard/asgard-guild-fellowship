# Guild Fellowship — Product Vision

> Captured 2026-09-29 as input for detailed product planning. This describes **vision, goals, and candidate capabilities**, not an implementation plan. Nothing here is an architectural decision, technical requirement, priority, or finalized feature list. Explore, question, refine, add to, or remove during planning.

## Platform

- World of Warcraft addon, built from the ground up.
- Targets **World of Warcraft: Forever** first, and must also be compatible with **Retail**.
- **No Classic support.**
- Intended to help many guilds, not just our own.
- It will be a large addon, so it must be well organized and as efficient as possible.

## Central Idea

> **Guild Fellowship should help guild members know each other, recognize each other, find each other, and actually play together.**

Most guild-management addons focus on raiding, loot, attendance, or administration. Guild Fellowship focuses on **people and community** first, while still giving guild officers useful tools.

## People, Not Just Characters

WoW presents a guild as a collection of characters. Guild Fellowship should show the **people behind those characters**.

A guild member may have:

- A main character.
- Multiple alts.
- An alias or preferred name.
- Different classes, roles, levels, and professions across those characters.

Example:

**Final**
- Dresden — Mage — Main
- Shiro — Paladin
- Malgen — Hunter

Our guild currently records mains, alts, and aliases in Guild Notes. Guild Fellowship should be able to use that information.

Seeing an unfamiliar character shouldn't leave you asking "Who is that?" Guild Fellowship should tell you: "Oh, that's Final playing Malgen."

## Identity in Guild Chat

When someone speaks in guild chat, it should be immediately obvious **who the person is**, even on an unfamiliar alt.

> **Malgen:** Anyone want to run a dungeon?

could become

> **Malgen [Final]:** Anyone want to run a dungeon?

If a player has no alias, their main character could serve as the identity:

> **RandomAlt [Dresden]:** Anyone want to run a dungeon?

Exact presentation and behavior still need design. The key capability: **guild chat should identify the person behind the character.** This makes chat much easier to follow in guilds where members have many alts.

## Guild Greet

The project began as a replacement for the old Guild Greet addon. Desired capabilities:

- Multiple greeting messages.
- Variation/randomization so greetings don't always sound the same.
- Recognizing when guild members come online.
- Recognizing the same person across different characters.
- Not greeting again when someone just switches alts.
- Avoiding greeting spam when several members log in at about the same time.
- Avoiding greeting spam when multiple members are running Guild Fellowship.
- Greetings that feel social rather than robotic.

## Fellowship Discovery

Help members discover **who they could be playing with**:

- Who is around my level?
- Who is in my zone?
- Who is nearby?
- Who could run the same dungeon as me?
- Who is currently interested in grouping?
- Who is willing to help?
- Who has a character suited to what I want to do?

Knowing about alts makes this especially useful. Example: I need a tank for content around level 35. Mike is online on his level-60 Mage, but Guild Fellowship knows he also has a level-34 Warrior, so it can tell me:

> **Mike is online and has a level-appropriate Warrior.**

That doesn't mean Mike wants to switch. The goal is not automatic matchmaking. It is:

> **Help guild members notice opportunities to play together that they otherwise wouldn't have noticed.**

## Player Availability

Players could say what they're interested in doing:

- Questing
- Dungeons
- PvP
- Helping
- Anything
- Busy / unavailable

This makes Discovery more useful: "Mike has an appropriate tank alt **and is currently interested in running dungeons.**" It should encourage interaction without creating pressure or unwanted spam.

## People-Centric Guild Information

Present the guild as **people rather than characters**. Instead of a flat roster (Dresden, Shiro, Malgen, Bob, Bobadin, Bobmage, Sarah, Sarahpriest), show the relationships:

**Final** — Dresden, Shiro, Malgen
**Bob** — Bob, Bobadin, Bobmage
**Sarah** — Sarah, Sarahpriest

Useful information could include:

- Who is online.
- Which character they're currently playing.
- Their main and alts.
- Alias.
- Character levels/classes.
- Where they're playing.
- Whether they're available to group.
- Relevant guild activity.

## Community Activity

Help members and officers see whether the guild is actually interacting as a community:

- Who has been active recently.
- Who takes part in guild chat.
- Who groups with guildmates.
- Who attends guild events.
- Who organizes activities.
- Who helps other members.
- Who is new.
- Who hasn't been around recently.

A key leadership use case is spotting someone falling through the cracks:

> A new member has been logging in regularly for several weeks but hasn't really interacted or grouped with anyone.

Leadership can then reach out and help them become part of the community.

The intent is **not** to create productivity scores or rank members by how "good" they are. It is to help leadership understand how healthy and connected the community is.

## Events

Help members organize activities together, not just raids:

- Dungeon runs.
- Questing groups.
- Leveling nights.
- PvP.
- Raids.
- Social events.
- Guild meetings.
- Bible studies.
- Custom events.

The emphasis is on making it easier for members to **do things together**.

## Helping and Mentoring

Members could indicate areas where they're willing to help:

- New players.
- Class questions.
- Tanking.
- Healing.
- Quest help.
- Dungeon help.
- PvP.
- Professions.
- General mentoring.

This answers: "Who in the guild might be able and willing to help me with this?"

## Professions and Crafting

Because Guild Fellowship understands people and their alts, it could help members find crafting resources in the guild: "Who can make this item?" Even if the right crafter isn't logged in on that character:

> Final is online as Shiro, but Dresden knows this recipe.

## New Member Experience

Help new members become part of the community:

- Welcome information.
- Introductions.
- Guild resources.
- Rules.
- Discord information.
- Onboarding steps.
- Finding people around their level.
- Finding people willing to answer questions.
- Letting officers see whether someone is getting connected.

## Community Roles (not guild rank)

Members could be given special guild roles that are separate from guild rank. Example: a **Welcome Party** role that gets access to a dashboard of new members who need to be welcomed or followed up with.

## Officer Tools

Useful to leadership without being an officers-only addon:

- Understanding who members actually are across their characters.
- New-member information.
- Member activity.
- Inactivity.
- Promotion-related information.
- Guild history.
- Member notes.
- Onboarding.
- Event participation.
- Community participation.
- Identifying members who may not be connecting with others.

## Future Possibilities

Worth keeping in mind, without assuming they belong in the product:

- Discord bot integration.
- Discord identity linking.
- Shared Discord/WoW events.
- External companion application.
- Website integration.
- Guild wiki/resources.
- Guild announcements/news.
- Guild milestones.
- Guild-wide profession directory.
- Help requests.
- Mentoring systems.
- Community statistics.
- Import/export.
- Additional guild-management tools.

Discord integration is a **possible future capability**, not currently required.

## What Makes Guild Fellowship Different

It is not mainly meant to answer "How well does our guild raid?" It answers:

- Who are these people?
- Who is that alt talking in guild chat?
- Who is around me?
- Who could I play with?
- Who wants to play?
- Who could help me?
- Who could I help?
- What are we doing together?
- Are our new members becoming part of the community?
- Is someone quietly falling through the cracks?

> **Help turn a collection of characters in a guild roster into a community of people who know each other and play together.**
