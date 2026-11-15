# Night Broom

A tiny Halloween arcade game made for **Micro Jam 069** (theme: *Halloween*, prerequisite: *haunted keyboard controls*).

![Night Broom cover](media/cover.png)

You fly a witch over a sleeping village and grab candy until dawn. Ghosts keep diving into the keyboard at the bottom of the screen and possessing keys. A possessed key turns purple and its arrow flips to a new direction, so Up might now fly you down. The on-screen keycaps always show what each key does right now. Grab a jack-o'-lantern to chase every ghost out at once.

**Play it in the browser:** ITCH_URL

## Controls

| Key | Action |
| --- | --- |
| Arrow keys or WASD | Fly (check the keycaps once ghosts arrive) |
| Any key | Start / fly again |

Grab candy in quick runs for a combo (up to +5 each). Bats cost a life; three hits and you fall. The night lasts two minutes.

## Screenshots

| | |
| --- | --- |
| ![A ghost haunts a key](media/screenshot-1.png) | ![Candy combo](media/screenshot-2.png) |
| ![Dawn](media/screenshot-3.png) | ![Title](media/title.png) |

## How the haunting works

Each key holds a direction. When a ghost lands on a key, that key's direction changes (the first time it's always a full reverse, later it's random). The haunt lasts 9 to 13 seconds, and a small bar under the key drains to show how long is left. More keys can be haunted at once as the night goes on, up to all four. A jack-o'-lantern appears while any key is haunted; grabbing it frees every key and gives back a life.

## Playtesting

The web build publishes its state to the page when opened with `?bot=1`, and `tools/bot.js` (Playwright) plays full nights against it with two policies: one that reads the key mapping the keycaps show, and one that assumes normal arrows. Over the tuning runs the mapping-aware bot collected about twice as much candy and was the only one to reach dawn, which is the check that the keycaps carry everything a player needs. A separate first-look test (an AI agent shown three screenshots and nothing else) led to the drain bars, the "FREES KEYS" tag on the pumpkin and the dawn label.

## Build

Godot 4.7.2 with web export templates installed.

```sh
./build.sh            # exports build/web and zips it to build/night-broom-web.zip
```

The web export uses the no-threads template, so it runs on itch.io without special headers.

## Credits

All art and sound effects are by Kenney (CC0). Music is "Danse Macabre" by Kevin MacLeod (CC BY 4.0). Full list in [CREDITS.md](CREDITS.md).

## AI disclosure

No AI-generated art, sound or music is used. Every sprite and sound is a human-made Kenney asset and the music is Kevin MacLeod's. The code was written with help from an AI coding assistant (Claude), which the Micro Jam 069 rules allow ("using AI for coding or debugging").

## License

Code: MIT (see [LICENSE](LICENSE)). Assets keep their own licenses (see [CREDITS.md](CREDITS.md)).
