# Testing

Three layers, cheapest first. The first two run without a device.

```sh
make check   # syntax + accidental globals, every file
make test    # the spec suite, any Lua 5.1
```

`make test` prints the count it actually ran, so it is not repeated here — a
number written into prose only goes stale.

Then `tools/epubcheck.lua` against a real KOReader (below), which is the one
that matters: EPUB assembly is the part most likely to be wrong, and it needs
crengine and libarchive.

## Getting a KOReader to test against

**Do not build from source unless you need to.** KOReader's own docs note that
if you only want to work on Lua frontend code — which is all this plugin is —
you can extract the AppImage instead. That takes about a minute rather than the
best part of an hour.

```sh
# Pick the current tag from https://github.com/koreader/koreader/releases
curl -LO https://github.com/koreader/koreader/releases/download/v2026.07/koreader-v2026.07-x86_64.AppImage
chmod +x koreader-v2026.07-x86_64.AppImage
./koreader-v2026.07-x86_64.AppImage --appimage-extract
cd squashfs-root/usr/lib/koreader
```

That directory contains everything needed: `luajit`, `libs/libkoreader-cre.so`,
`ffi/archiver.lua`, fonts, and a `plugins/` directory. Install the plugin with:

```sh
cp -r /path/to/karaoke/karaoke.koplugin plugins/
```

### Running the UI

```sh
./luajit reader.lua                 # file manager
./luajit reader.lua path/to.epub    # straight into a document
```

Headless works too, which is useful over SSH or in CI:

```sh
xvfb-run -a -s "-screen 0 600x800x24" ./luajit reader.lua path/to.epub
```

Two messages are container noise and can be ignored: SDL's
`XDG_RUNTIME_DIR is invalid or not set`, and `XIO: fatal IO error` when Xvfb is
torn down at the end.

Confirm the plugin loaded — the log line is `Plugin loaded karaoke`:

```sh
./luajit reader.lua 2>&1 | grep -i karaoke
```

It appears under **Tools → More tools → Karaoke**.

### Building from source instead

Worth it if you want the Kobo screen simulations, which the AppImage cannot give
you. `kodev run` takes a device profile:

```sh
git clone https://github.com/koreader/koreader && cd koreader
./kodev fetch-thirdparty && ./kodev build
ln -s /path/to/karaoke/karaoke.koplugin \
      koreader-emulator-*/koreader/plugins/
./kodev run -s kobo-clara        # or kobo-forma, kobo-aura-one, kobo-h2o
```

`--simulate` accepts `kobo-forma`, `kobo-aura-one`, `kobo-clara`, `kobo-h2o`,
`kindle-paperwhite`, `legacy-paperwhite`, `kindle` and `hidpi`; `-W`, `-H` and
`-D` set width, height and DPI directly. This needs the full toolchain
(SDL3 ≥ 3.2.12, meson, ninja, nasm and the rest — see KOReader's
`doc/Building.md`), or you can use their premade Docker image from
[koreader/virdevenv](https://github.com/koreader/virdevenv), which needs only
Git and Docker.

## tools/epubcheck.lua

Drives `EpubBuilder.build()` against the real crengine and libarchive without
starting the UI, and asserts on the result. Exits non-zero on failure.

```sh
cd squashfs-root/usr/lib/koreader
cp -r /path/to/karaoke/tools .
./luajit tools/epubcheck.lua
```

To include the image checks, run the fixture server first — it serves a real
PNG, a PNG behind a `.jpg` name, and an HTML error page where an image should
be:

```sh
python3 tools/fixtures.py &                       # 127.0.0.1:8799
KK_IMG_SERVER=http://127.0.0.1:8799/ ./luajit tools/epubcheck.lua
```

It covers the things that silently degrade rather than crash: that crengine
actually balances the ragged HTML, that `<script>` and `onclick` are gone, that
entities become UTF-8, that image media types come from the bytes rather than
the URL, that an image which fails to download leaves no `<img>` behind, that
the image size budget drops images without failing the article, and that a
cancelled build abandons the file rather than writing half of one.

It also asserts the two structures that only exist inside the finished archive:

- **Covers.** The cover page, the image named for its sniffed type, `<meta
  name="cover" content="cover-img"/>` matching its manifest item, the cover
  first in the spine, no EPUB 3 `properties=` claimed, `include_covers = false`
  writing neither, and a non-image response leaving no cover behind. With
  `KK_IMG_SERVER` set it also checks the page-URL fallback and that an HTML error
  page at that URL is skipped.
- **Table of contents.** That the heading ids survive crengine's balancer, that
  there is a navPoint per heading plus one for the article, that an `h3`'s
  navPoint is nested inside its `h2`'s, and that `dc:language` follows the
  bookmark rather than being hardcoded.

The TOC assertions read the NCX and the XHTML. They do not open the book, so
`validateAndFixToc(): TOC is fine` on a device is still the check that the
contents list renders (below).

## What is verified, and what is not

Verified against KOReader v2026.07:

- The plugin loads (`Plugin loaded karaoke`) with `main.lua` initialising
  cleanly alongside 32 stock plugins.
- Generated EPUBs open in `CreDocument`, render, and pass
  `validateAndFixToc(): TOC is fine`.
- `content.xhtml`, `content.opf`, `toc.ncx` and `container.xml` are all
  well-formed XML.
- Ragged HTML is balanced; images are fetched, sniffed and embedded, with
  failures dropped cleanly.

Added in 0.9.0 and **not yet verified on a device** — the cover and TOC
structures are asserted by `tools/epubcheck.lua`, but everything below is about
how crengine and the Kobo's own library actually render them:

- **Cover art in mosaic view and on the shelves.** Whether the plugin's cover
  shows as the tile, and whether `cover.xhtml` is what you land on when you open
  the article. The store's own library may index cover art at import time rather
  than reading the EPUB, which would leave shelves bare until a rescan — worth
  knowing either way.
- **Table of contents in the reader.** Open the contents menu on a long article:
  one entry per `h2`, `h3` indented, and tapping one lands on the right heading.
- **Hyphenation and justified text.** That justified paragraphs are hyphenated
  with the device's dictionary, and that this does not fight a user style tweak
  that turns hyphenation off.
- **Code blocks.** A Rust or Postgres article with a wide `pre` block: lines
  should wrap rather than run off the page, and a block should not split across
  a page break.
- **Wide tables** take the screen width at the smaller size instead of being
  clipped.
- **Night mode.** Rules, table borders and code backgrounds should be visible
  but not muddy in inverted mode.
- **The failure dialog.** Force a failure (revoke the key's `Assets: Read` scope
  and download a PDF) and confirm the second dialog names the article and
  suggests the scope.

Still unverified, and worth doing on a real Kobo:

1. **A large image-heavy article**, timed. This is the main performance risk of
   building EPUBs in Lua on a Kobo. Compare with *Embed images* off, and watch
   for images dropped by the size budget (`MAX_IMAGE_TOTAL_BYTES`) in the log.
2. **`api.lua` against a live Karakeep** — every endpoint here is exercised only
   against the OpenAPI spec, not a running server. Start with
   `Server → Save and test`.
3. **Highlight round trip.** Highlight a passage appearing twice and confirm the
   first-occurrence behaviour in the README; then one appearing once, and check
   the offsets land correctly in Karakeep's web UI. **Pick an article with
   accented characters, curly quotes or em-dashes before the highlight** — that
   is what the UTF-16 offset conversion exists for, and a byte-offset regression
   would be invisible in pure-ASCII prose.
4. **Interrupted and capped syncs.** Cancel mid-download — including during
   *Fetching image n of m*, which is now honoured immediately rather than at the
   next article — and set *Articles per sync* below your unread count; confirm
   nothing local is deleted either time. The guard is `complete and not
   cancelled` in `synchronize()`.
5. **Archive from another device**, then sync, and confirm the unopened local
   copy is removed.
6. **A self-signed certificate**, if your Karakeep uses one. KOReader has its own
   CA bundle and will refuse an unknown issuer; it surfaces as
   `Could not reach the server.`

### Added by this fork, none of it yet exercised on hardware

`articleutil.lua`'s new helpers (`originalExtension`, `originalTitle`) have
specs. Everything below is in `main.lua`, which the spec runner cannot reach, so
these were only linted, reviewed against KOReader v2026.07.1's API, and built.

1. **A PDF bookmark end to end** — needs **`Attachments: Read`** on the API key
   (the `assets` scope; the API and the UI use different words for it), or
   every asset returns 403 and the sync summary names it. Confirm the file
   arrives with its `.pdf` extension and `[kk-id_…]` marker, then that reading
   it to the end archives it in Karakeep, and that *Rebuild* replaces it in place
   without losing the sidecar.
2. **An oversized original** — check that a file over `max_original_mb` is
   skipped with a reason in the summary, and that no `.part` file is left behind.
3. **Archive folder** — with `archive_directory` set, finish an article and
   confirm the file, its `.sdr` and its history entry all moved, and that
   collections still list it. `FileManager:moveFile` plus
   `DocSettings.updateLocation` is the same sequence wallabag uses, but the
   combination has not been run here.
4. **`remote_delete_instead_of_archive`** — irreversible; try it on a throwaway
   bookmark first.
5. **Add an article offline** — with Wi-Fi off, add a link, confirm it queues,
   then sync and confirm it is `POST`ed before the fetch.
6. **`only_favourited` with a list or tag scope**, against a server that does
   not include the `favourited` field, to confirm the scope does not come back
   empty.
9. **Interrupt a PDF download** (kill KOReader mid-transfer, or pull the cable
   on a desktop run) and confirm the next sync fetches it again rather than
   believing it is already there. The `.part` file should be gone from the
   download folder once the next sync starts.
10. **An oversized original.** Set `max_original_mb` to 1 and sync a larger PDF:
   the transfer should stop part-way, the summary should say it is over the
   limit, and the device should not have briefly written the whole file.
11. **An archive folder inside the download folder.** Finish an article, sync
   again, and confirm it is not archived a second time.
12. **A PDF with highlights**: the sync summary should say the highlights were
   not sent, rather than staying silent.

7. **`ignore_tags`** with a tag containing a space, which is the case the
   comma-splitting exists for.
8. **`Save and test` with a key that has no `User account` scope.** It should
   report a connection and say the account name is unavailable, not that the key
   was rejected. `verifyCredentials()` falls back to `GET /bookmarks` on a 403
   for exactly this; a key with no Bookmarks scope should instead fail with the
   missing-scope message.

## Adding specs

`spec/runner.lua` is a deliberately small `describe`/`it` harness. busted is not
used because these modules must run under a plain Lua 5.1 interpreter, the
dialect LuaJIT implements. Add a file to `spec/`, require it from `spec/all.lua`,
and use `assertEqual`, `assertTrue`, `assertNil`, `assertMatch` and
`assertNoMatch`.

To cover a module that pulls in KOReader, stub what it needs via
`package.preload` before requiring it, as `spec/epubbuilder_spec.lua` does. Note
that `socketutil` drags in the whole device stack, which probes SDL and needs a
display — `epubbuilder.lua` requires the networking modules lazily inside
`fetchUrl()` for exactly this reason.
