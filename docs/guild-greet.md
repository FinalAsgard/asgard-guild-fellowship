# Guild Greet

Guild Greet helps you say hello to guildmates when they log in, and welcome people who join the guild. It greets the **person**, by the name the guild knows them by, not whichever alt they happen to be on. It also keeps guild chat from filling up with identical greetings.

It builds on [Identity](identity.md): people, display names, and sync between add-on users.

## Turning it on

Guild Greet is **off by default**. Turn it on in **Settings → Asgard's Guild Fellowship → Feature toggles → Guild Greet**.

The add-on never posts anything on its own. The game only lets add-ons send chat when you click something, so every greeting comes from a button you press.

## The greet prompt

When a guildmate comes online, a small **Guild Greet** window pops up with a short chime:

> Zel came online.  **[Greet]**  **[Dismiss]**

- **Greet** posts one line in guild chat, such as `Welcome back, Zel!`
- **Dismiss**, or the window's ✕, closes it without posting.

Someone who joins the guild gets their own row and button:

> Mike Newman joined the guild.  **[Welcome]**

The prompt also behaves like this:

- **Several at once:** anyone who arrives while the prompt is open is added to it, and one click greets everyone waiting: `Welcome back, Zel and Kira!` A very large batch is split across lines, and names are never cut off.
- **Separate rows:** welcome-backs and new-member welcomes stay in separate rows and lines. Greet and Welcome each clear only their own row.
- **Remembers its spot:** drag the window wherever you like, and it opens there next time.
- **Goes away on its own:** an unanswered prompt closes about 2 minutes after the last person was added.
- **Waits out combat:** during combat, no prompt appears. It shows up when combat ends, as long as the arrivals are still under 2 minutes old.

## Who gets greeted

People are greeted, not characters:

- **Switching alts** never counts as coming online.
- **Coming back within 30 minutes** of last being online (a relog or a short break) isn't greeted again.
- **People already online when you log in** aren't greeted, and neither are you or your own alts.
- **A brand-new member** gets one welcome, and isn't also offered as "came online" right after joining.

## Not too many greetings

When several guildmates use Guild Greet, at most **two** of them greet the same arrival. Two feels friendly, and more is spam.

- Each Greet or Welcome click is quietly announced to other add-on users over the add-on channel. Nothing extra appears in chat.
- Once someone has been greeted twice, they disappear from everyone else's prompt.
- This needs **Sync with other add-on users** turned on. With sync off, your prompt ignores what others did.

## Your messages

Each player writes their own greetings in the settings:

| Setting | Used for | Default examples |
| --- | --- | --- |
| **Welcome-back messages** | Guildmates coming online | `Welcome back, {name}!`, `Hey {name}, welcome back!` |
| **New-member messages** | People joining the guild | `Welcome to the guild, {name}!` |
| **Welcome new members** | Turns new-member welcomes on or off (on by default) | |

- Put one message per line. `{name}` becomes the person (or people) being greeted. A line without `{name}` gets the names added at the end.
- A message is picked at random, and never the same one twice in a row.
- Color codes and `|` characters are removed. Clearing a list brings back the built-in messages.
