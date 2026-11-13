# Tiny Putt

**Pull back. Let go. Sink it.**

A quick, friendly top-down mini-golf game for iPhone, iPad and Mac. No ads, no purchases, no accounts, and it works fully offline.

### 👉 [gbabichev.github.io/TinyPutt](https://gbabichev.github.io/TinyPutt/)

Screenshots, how it works, support and the privacy policy are all on the website.

## The game

- **500 holes** across four worlds (meadow, farm, desert and winter): hand-made first holes, then generated ones that get trickier, each proven finishable by a headless checker.
- **Obstacles**: sand, ice, mud, water and lava, hills, wind, windmills, portals, ramps, bumpers, switches and doors, and more.
- **Levels**: a thumbnail of every hole, with your best score. Replay any hole or play ahead.
- **Players**: pass and play with separate progress, or **Versus** on the same hole. Earn ball colours as you go.

## Requirements

iOS 18, iPadOS 18 or macOS 15 or later.

## Building

Open `Tiny Putt.xcodeproj` in Xcode and run the **Tiny Putt** scheme, or from the command line:

```bash
xcodebuild -project "Tiny Putt.xcodeproj" -scheme "Tiny Putt" -destination 'platform=macOS' build
```

`Tools/HoleChecker` is the command-line tool that generates the campaign table and checks that every hole can be finished. It shares the game's `Engine` sources.

## Support and privacy

Questions, bugs and ideas: [open an issue](https://github.com/gbabichev/TinyPutt/issues). Tiny Putt collects no data; see the [privacy policy](https://gbabichev.github.io/TinyPutt/PrivacyPolicy.html).

© 2026 George Babichev
