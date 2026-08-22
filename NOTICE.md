# Third-party notices

BongoTokenCat's own code is MIT ([LICENSE](LICENSE)). This file covers everything
in the repository that someone else made, and what their terms require.

## Artwork — Bongo Cat

Bongo Cat is by **[@StrayRogue](https://twitter.com/strayrogue)** (the cat drawing)
and **[@DitzyFlama](https://twitter.com/ditzyflama)** (the original meme). Per the
[Bongo Cat FAQ](https://bongocat.carrd.co/), reuse is fine as long as the original
artist is credited and linked — so **please keep this credit if you fork.**

The sprites in `Sources/BongoKit/Resources/images/` are derived from the taiko set
of **[bongocat-osu](https://github.com/kuroni/bongocat-osu)**, which ships that
artwork under MIT. `scripts/prepare-sprites.py` keys out the opaque white desk
behind the cat and the white backdrop baked into the bongo photo, so the overlay
sits on the desktop with nothing behind it; the drawing itself is unchanged.

Because those PNGs are a derived work, bongocat-osu's notice travels with them:

```
MIT License

Copyright (c) 2018 Đặng Đoàn Đức Trung

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Also tried: bongo.cat

**[bongo.cat](https://github.com/Externalizable/bongo.cat)** by Eric Huber (MIT)
was the first art source attempted, and is credited here because the choice
between the two is worth recording. Its cat is line work with a transparent
interior — it only reads as white because that page has a white background, and
the outline is open, so there is no enclosed region a flood fill can reach. Over
a desktop it renders as a see-through wireframe. No asset from it ships here.

## Prior art — ideas, not code

**No code is copied from either project.** They are credited because the ideas
came from them.

| Project | What we took |
|---|---|
| **[LLMPET](https://github.com/myunwang/LLMPET)** by myunwang (MIT) | Driving a desktop pet from Claude Code hooks — that a hook payload is enough to know what an agent is doing, without polling or scraping. |
| **[PokeTokenBar](https://github.com/chattymin/PokeTokenBar)** by chattymin (MIT) | Reading token usage from Claude Code's local transcripts, and spending it as a progression currency. Its Homebrew tap + cask release setup is also the model for ours. |

## Runtime dependencies

None. BongoTokenCat is Swift 6 + SwiftUI against the macOS SDK, with no package
dependencies — `Package.swift` has an empty `dependencies` list.

`scripts/prepare-sprites.py` needs [Pillow](https://python-pillow.org/)
(HPND licence), but it is a build-time tool for regenerating the committed PNGs,
not something the app links against.
