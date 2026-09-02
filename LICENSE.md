# License and Standing

## Why This Runs on an Old Version of World of Warcraft

In the author's own words, kept verbatim because the reasoning is the point:

> we used an old version of WoW because everyone knows WoW and can build their
> queststorydungeons knowing how the mechanics work. WoW truly is the greatest
> in a genre, please check them out at battle.net.

That is a design argument before it is anything else. A shared vocabulary is
the most valuable thing a creative tool can be handed, and this one arrives
pre-installed in almost everybody: what a pull is, what aggro is, what a
healer does, what happens when you stand in the fire, how far you can jump,
what a cooldown costs you. None of that has to be taught.

So when someone builds a **queststorydungeon** here, they are not learning a
system. They are using one they already know, to say something they have not
said before. The mechanics are the grammar; the queststorydungeon is the
sentence.

Please do check them out at battle.net.

## Standing

This is a private project. It is not for distribution, not a product, and not
a service. Nothing here is offered to the public.

It is not affiliated with, endorsed by, sponsored by, or connected to Blizzard
Entertainment in any way. World of Warcraft and all associated marks belong to
Blizzard Entertainment. No game client, game data, art, audio, or copyrighted
material of theirs is contained in this repository or distributed by it.

What this repository contains is original work: a control plane that operates
on a locally-run server, and documents describing how and why it does so.

## What It Is Built On

- **AzerothCore** — the open-source WotLK 3.3.5a server emulator this project
  attaches to. GNU AGPL v3.
- **mod-playerbots** — AI companions, from the `liyunfan1223` fork.
- **mod-ale** — the AzerothCore Lua Engine, which is how anything runs inside
  the server process.

Each carries its own license, and each keeps it. Nothing here relicenses
anything.

## On the Artifacts This Project Produces

A queststorydungeon exported from here is a **text file describing an
arrangement**: which props stand where, which characters are placed how, what
the story of it is. It contains no game assets. It is a recipe, and it is the
author's.

Applying one to a world requires a world you already run, a client you already
own, and a copy of the game you already have. This project has opinions about
arrangements; it has nothing to say about how anyone came by the game.
