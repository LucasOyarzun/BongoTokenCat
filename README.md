# BongoTokenBar

A Bongo Cat for every coding agent you have running. The paws drum in time with
what each agent is actually producing, so a glance at the corner of the screen
tells you who is working, who is stuck, and who is waiting on you.

macOS menu bar app. Swift 6 + SwiftUI, no dependencies, personal use.

## What it does

- **One cat per agent**, labelled with its git branch — or a single cat standing for
  the whole fleet. Toggle in the menu.
- **The rhythm is the signal.** Cats drum while their agent streams output, and tap
  slowly between bursts so a working agent never looks like a stopped one. A busy
  row looks busy.
- **Badges for what the paws cannot say**: `…` thinking, `zzz` asleep, `?` waiting
  for you, `!` error, `✓` done. Working and delegating need none — the rhythm
  carries it.
- **Click a cat to dismiss its badge.** `…` fades on its own, but `?`, `!` and `✓`
  hold until you have actually looked at them.
- **Skins unlock with tokens spent.** Six coat colours, from plain white at zero to
  gold at 100B.
- **Drag a cat anywhere.** Size runs from 44pt to 320pt; the gaps between cats stay
  click-through, so the overlay never steals a click from the window behind it.

### States

| Hook event | State | Cat |
|---|---|---|
| `PreToolUse` / `PostToolUse` / `MessageDisplay` | working | drumming, slow tap between bursts |
| `PreToolUse(Task)` / `SubagentStart` | delegating | same as working |
| `UserPromptSubmit` | thinking | paws up, `…` |
| `Notification` / `Elicitation` | waiting for you | one paw raised, `?` |
| `Stop` | done | paws up, `✓` |
| `StopFailure` / `PostToolUseFailure` | error | slumped, `!` |
| `SessionStart`, or 45s silent | idle | paws up, no badge |
| `SessionEnd`, or 15 min silent | asleep | dimmed, paws down, `zzz` |

States age on their own: 45s silent drops to idle, 15 min to asleep, 30 min after
a session ends the cat disappears. The three states that carry something for *you*
— a question, a finish, an error — never age out; click the cat to clear them.

Archiving a Conductor workspace deletes its worktree, and a cat whose directory is
gone is dropped on the next tick whatever state it was in. Without that the three
states above would never age their way to removal, and an archived workspace would
leave a cat behind for good.

## Install

Requires macOS 14+ and a Swift toolchain (Command Line Tools is enough).

```bash
./scripts/build-app.sh
open build/BongoTokenBar.app
```

Then open the menu bar icon and press **Install hooks**.

### About the hooks

The app cannot see your agents until Claude Code is told to notify it. Installing
registers a hook command in `~/.claude/settings.json`.

It **merges**: entries are matched by our own script path, so existing hooks are
left alone, and a timestamped backup is written to `~/.bongotokenbar/` before any
write. **Remove hooks** in the menu takes only ours back out.

The hook itself is a three-line shell script that pipes the payload to a localhost
port with a 250ms timeout and always exits 0 — it can never slow down or break a
session, only fail to animate a cat.

## Tuning the rhythm

`DrumEngine.tokensPerSecond` (default 120) sets how long a message drums for.
Measured against a real history — median 428 output tokens per assistant message,
tool calls a median 7.7s apart — that lands around a 50% duty cycle: visibly busy,
with pauses that mean something. Lower it and the cat never rests; raise it and it
barely moves.

Driving the paws from *tool calls* instead is the obvious design and it does not
work: one strike every eight seconds reads as broken.

## Development

```bash
./scripts/test.sh                                   # 78 tests
./scripts/send-test-event.sh Stop demo /tmp/proj    # fake an event
tail -f ~/.bongotokenbar/bongotokenbar.log
```

Logic lives in `BongoKit`; the executable is a six-line shim so the tests can
import it. Tests are a plain executable with a small harness rather than a
`.testTarget` — without Xcode, neither XCTest nor swift-testing has an importable
module.

`.build` inside a Conductor workspace fails with a SQLite I/O error, so the scripts
use `/tmp/bongo-build`. Override with `SCRATCH_PATH`.

### Token scanning

The first scan reads every transcript (~60s on a 457-file history) and then caches
per-file totals keyed by size and modification time. Later scans re-read only what
changed — about 2s. Per-file dedup is used rather than global; measured on a real
history the two produce an identical total.

## Labels

A cat is labelled with its **git branch**, not its folder. Conductor names a
workspace folder independently of the branch (`cebu-v2`), so the folder tells you
nothing about the work; the branch does, and it keeps up when the folder is
renamed. The menu shows the full `project · branch`.

Git is read directly from `.git` rather than by shelling out — Conductor workspaces
are worktrees, so the `gitdir:` pointer is the normal case here. Results are cached
for 30s so a burst of hook events costs one lookup.

## Credits

Bongo Cat is by **[@StrayRogue](https://twitter.com/strayrogue)** (the cat drawing)
and **[@DitzyFlama](https://twitter.com/ditzyflama)** (the original meme).

The sprites here are from [bongocat-osu](https://github.com/kuroni/bongocat-osu)
(MIT) — its taiko set, which has a filled white body and one image per paw pose.
`scripts/prepare-sprites.py` turns that artwork into what the app bundles: it keys
out the opaque white desk behind the cat and the white backdrop baked into the
bongo photo, so the overlay sits on the desktop with nothing behind it. Rerun it
against a fresh clone to rebuild the PNGs.

[bongo.cat](https://github.com/Externalizable/bongo.cat) (MIT) was the first source
tried. Its art is line work with a transparent interior — it only reads as a white
cat because that page has a white background, and the outline is open, so there is
no enclosed region to fill.

Please keep the credit if you fork this. Per the
[Bongo Cat FAQ](https://bongocat.carrd.co/), reuse is fine as long as the original
artist is credited and linked.

The idea of driving a desktop pet from Claude Code hooks comes from
[LLMPET](https://github.com/myunwang/LLMPET) (MIT); the token-tracking approach
from [PokeTokenBar](https://github.com/chattymin/PokeTokenBar) (MIT). No code from
either is copied here.

## License

MIT for the code. The Bongo Cat artwork remains StrayRogue's.
