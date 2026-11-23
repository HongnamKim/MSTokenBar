# MSTokenBar

[한국어](README.ko.md) · [日本語](README.ja.md)

A macOS menu-bar app that turns the AI coding tokens you already spend (Claude Code, Codex, Gemini CLI, and more) into Gunpla (plastic model kit) progress. It is a Gunpla-themed fork of [chattymin/PokeTokenBar](https://github.com/chattymin/PokeTokenBar).

> Work in progress: pixel sprites are still being drawn. Only the RX-78-2 Gundam has art so far; other suits show a silhouette. The catalog is a 12-suit development set, and the first release roster (127 mobile suits from 15 Universal Century series) is being prepared. Token usage tracking is inherited from the original project; see the [upstream README](https://github.com/chattymin/PokeTokenBar#readme) for the supported tools.

## How it works

- **Unbox**: spend AI coding tokens and your Kit Box opens. A mobile suit comes out.
- **Grade up**: keep spending and the suit climbs through the kit grades actually released for it: SD → MGSD → HG → RG → MG → PG. Grades that were never released are skipped.
- **Complete**: at its final grade the suit is complete. It is saved to your Hangar and a new Kit Box arrives. A completed suit does not come out again until you have completed every suit.
- **Customs**: commander and ace customs, such as Char's Zaku II, are rare variants of their base suit. Paint tools from the shop (Masking Tape → Panel Line Pen → Paint Set → Airbrush) raise the chance for good.
- **Hangar**: one cell per suit records every grade you have built. Filter by series and earn a badge for completing each one.
- **Items**: a Sanding Sponge gives instant progress, and Uncommon or Rare Boxes guarantee a rarity tier.

## Requirements

macOS 14 or later.

## Build from source

```bash
git clone https://github.com/HongnamKim/MSTokenBar.git
cd MSTokenBar
scripts/build-app.sh      # builds build/MSTokenBar.app and installs it to /Applications
```

## Credits

Forked from [PokeTokenBar](https://github.com/chattymin/PokeTokenBar) by chattymin. The original MIT license and copyright notice are kept in [LICENSE](LICENSE).

## Disclaimer

Unofficial, non-commercial fan project. Not affiliated with Bandai Namco or Sunrise. All rights to the original works belong to their owners.
