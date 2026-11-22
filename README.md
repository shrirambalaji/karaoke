<p align="center">
  <img src="docs/logo.svg" width="120" height="120" alt="Karaoke">
</p>

<h1 align="center">karaoke</h1>

<p align="center">
  <b>Your Karakeep reading list, offline on a Kobo.</b><br>
  Articles rebuilt as EPUBs, uploaded PDFs saved untouched, read status and highlights back to the server.
</p>

<p align="center">
  <a href="https://github.com/shrirambalaji/karaoke/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/shrirambalaji/karaoke?label=release&color=d2743a"></a>
  <a href="#licence"><img alt="Licence" src="https://img.shields.io/github/license/shrirambalaji/karaoke?color=202b38"></a>
  <img alt="KOReader" src="https://img.shields.io/badge/KOReader-2024.04%2B-2f6f4f">
  <img alt="Devices" src="https://img.shields.io/badge/kobo-e--ink%20readers-4b5563">
</p>

> [!NOTE]
> **This is a fork of [`davepwsmith/KaraKo`](https://github.com/davepwsmith/KaraKo),**
> maintained at [`shrirambalaji/karaoke`](https://github.com/shrirambalaji/karaoke).
> Upstream is still called KaraKo; from 0.8.0 this fork is called Karaoke
> throughout, including the plugin folder and its settings file.
>
> Upstream KaraKo syncs articles and nothing else. This fork keeps all of that
> and adds **the features `wallabag.koplugin` has that KaraKo did not**, plus
> **uploaded PDFs and images saved as they are** rather than skipped. Releases
> on this repository are the source of truth for the fork — see
> [what this fork adds](#what-this-fork-adds-over-upstream).

> [!CAUTION]
> The plugin this started from is vibe-coded with Claude Code, and the additions
> in this fork are in the same spirit. Everything here passes `make check`,
> `make test` and a build of the installable zip, and the paths that only a real
> device can exercise are listed in [TESTING.md](TESTING.md). Treat it with the
> caution that anything vibe-coded deserves.

## Why this exists

Read your [Karakeep](https://karakeep.app) library on a Kobo, via
[KOReader](https://koreader.rocks) — the way `wallabag.koplugin` already lets
people read their Wallabag library there.

`karaoke.koplugin` syncs unread bookmarks onto the device as EPUBs, saves uploaded
PDFs and images as they are, and pushes your read status and highlights back to
Karakeep when you are done with them.

It is modelled on KOReader's [`wallabag.koplugin`][wallabag], which solves the
same problem for a different read-it-later service; this fork closes the gap
between the two.

[wallabag]: https://github.com/koreader/koreader/tree/master/plugins/wallabag.koplugin

## What it does

- Downloads unread bookmarks as EPUBs, built on device from Karakeep's crawled
  article HTML, with images embedded.
- **Saves uploaded PDFs and images exactly as they are**, rather than trying to
  rebuild them into an EPUB.
- Syncs everything unarchived, or just one Karakeep list or tag, or only your
  favourites.
- Skips articles carrying any tag you tell it to ignore.
- **Adds articles to Karakeep from the device**, queueing the link when there is
  no connection.
- Archives an article in Karakeep once you finish it, optionally tagging it and
  deleting the local copy — or moving it to an archive folder instead.
- Sends the highlights you make in KOReader back to Karakeep, and optionally the
  review note as tags.
- Optionally syncs when Wi-Fi connects, without interrupting your reading.
- Cleans up local copies of articles you archived elsewhere.

## What this fork adds over upstream

Everything `wallabag.koplugin` does that upstream KaraKo did not, plus PDFs:

| Feature | Setting |
| --- | --- |
| PDFs and other uploaded originals, saved unchanged | `download_originals`, `max_original_mb` |
| Only download favourites | `only_favourited` |
| Ignore articles by tag | `ignore_tags` |
| Add an article from the reader, with an offline queue | **Karaoke → Add an article** |
| Move finished articles to an archive folder instead of deleting | `archive_directory` |
| Delete in Karakeep instead of archiving | `remote_delete_instead_of_archive` |
| Send the review note as tags | `send_review_as_tags` |
| Configurable network timeout | `network_timeout` |

The word "originals" is deliberate: an uploaded PDF is never converted, never
re-fetched through the crawler, and never summarised. It is the bytes the user
put into Karakeep, written to the device with the same
`Article Title [kk-id_…]` name an article gets, so read status, archiving and
local-copy bookkeeping work identically for both.

### PDFs and other uploaded files

A bookmark whose content is an uploaded file — a PDF, a scan, a saved image — is
fetched from `GET /assets/{id}` and written to the download folder unchanged:

```
The Rustonomicon [kk-id_9f3a1c].pdf
```

What that gives you, because the file keeps the same marker every other download
has:

- **Read status works.** Finishing a PDF archives it in Karakeep like any
  article, and the `.sdr` sidecar records your page in the usual way.
- **Archiving, tagging and the local-copy rules apply** without a special case —
  including "never delete something you have opened", and an archive folder if
  you set one.
- **Rebuild re-fetches it in place** rather than orphaning it under a new name.

The format is resolved from the asset's type, then its MIME type, then its file
name, and anything KOReader has no provider for is skipped deliberately rather
than saved as a file that cannot be opened. Size is capped by `max_original_mb`
(default 80) rather than `max_archive_mb`, because a PDF is routinely larger than
a page archive.

**Highlights are not sent for PDFs.** Karakeep stores offsets into its own
rendered text, and a PDF annotation anchors into a page; there is nothing to
match, so highlighting a PDF stays local instead of arriving on the server
misplaced.

### Adding articles from the reader

**Karaoke → Add an article** takes a link and saves it to Karakeep without
touching a phone. Offline, the link is queued in `karaoke_queue.lua` and sent by
the next sync — at the *start* of the sync, so a link added a minute ago can be
downloaded in the same run. Both adding and flushing the queue are bindable as
gestures (**Settings → Gestures**), as `karaoke_add` and `karaoke_upload_queue`.

### Archiving, deleting, and keeping finished articles

Three separate choices, because they answer three different questions:

| Question | Setting |
| --- | --- |
| What happens on the server when I finish an article? | archive it (`archive_finished`, `archive_read`, `archive_abandoned`) or delete it outright (`remote_delete_instead_of_archive`) |
| Does the local copy stay? | `delete_local_after_archive` |
| If it stays, where does it go? | `archive_directory` — moved there with its sidecar, history entry and collection membership |

The archive folder is the useful middle ground: the article leaves the unread
ones but does not disappear, which is what a finished long read usually wants.

## Requirements

- A Karakeep server, and an API key from **Settings → API Keys**.
- KOReader installed on the device. Downloading needs `ffi/archiver` and
  `cre.getBalancedHTML`, which is anything from 2021 onwards.
- **Sending highlights back needs KOReader 2024.04 or newer**, which is where
  highlights and bookmarks were merged into the single `annotations` sidecar
  table this reads. On an older build everything else works and highlight
  syncing simply finds nothing; the log says so once per article.

## API key scopes

Karakeep lets you scope an API key per resource. The plugin touches six, and
needs **None** for everything else — no Backups, Feeds, Prompts, Rules, Webhooks,
or any Admin scope:

| Resource | Access | Needed for |
| --- | --- | --- |
| **Bookmarks** | Read/write | Everything. Read to list and fetch articles; write to archive them |
| **Attachments** | Read | PDFs and other uploaded files, page archives, and a fallback for article text |
| **Highlights** | Read/write | Sending highlights back. Read first, to avoid duplicates |
| **Lists** | Read | Only the "choose a list" picker |
| **Tags** | Read | Only the "choose a tag" picker |
| **User account** | Read | Optional. Without it `Save and test` still passes, it just cannot name the account |
| *everything else* | None | Never called |

> **The UI calls this resource "Attachments" and the API calls it `assets`.**
> They are the same scope: the endpoint is `GET /api/v1/assets/{assetId}`, and
> Karakeep's own translation keys still map `assets` to the label "Attachments".
> If you went looking for a chip called "Assets" and concluded PDFs were
> unsupported, that is this mismatch.

**Attachments: Read is no longer optional in this fork.** It is what fetches an
uploaded PDF — see [PDFs and other uploaded files](#pdfs-and-other-uploaded-files).
Ordinary article text still arrives inline under Bookmarks: Read, whatever its
length; Attachments: Read remains optional only if you turn
`download_originals` off, and is still needed for saved page archives.

Two of these are not what you would guess, so they are worth stating plainly.
Both were confirmed against Karakeep's own scope enforcement in
`packages/trpc/index.ts`, where a tRPC query needs `read` and a mutation needs
`readwrite` on whichever resource its router is scoped to:

- **Syncing a list or a tag does not need the Lists or Tags scope.**
  `GET /lists/{id}/bookmarks` and `GET /tags/{id}/bookmarks` both call
  `api.bookmarks.getBookmarks` internally, so Bookmarks: Read covers them. Lists
  and Tags are needed only so the settings menu can show you what to pick from.
- **Tagging on archive needs Bookmarks: Read/write, not Tags: Read/write.**
  `POST /bookmarks/{id}/tags` routes through `api.bookmarks.updateTags`.

### Cutting it down further

Each write scope maps to one feature, so you can grant less if you turn the
matching feature off:

| If you want | Grant |
| --- | --- |
| Articles only, nothing written back, no PDFs | Bookmarks: **Read** |
| …plus PDFs, uploaded files and saved page archives | Attachments: **Read** |
| …plus archive on finish, and tag on archive | Bookmarks: **Read/write** |
| …plus highlights sent back | Highlights: **Read/write** |
| …plus picking a list or tag in the menu | Lists: **Read**, Tags: **Read** |
| …plus your account name in the connection test | User account: **Read** |

A key missing a scope fails that one call with `403 API key is missing required
scope: <scope>`, which the log records — the rest of the sync carries on.
**Feeds, Prompts, Backups, Rules, Webhooks and Admin are never called**; if
your key has them, they can be dropped without losing anything.

Give the device its own key rather than reusing one, so you can revoke just that
one if you lose the Kobo.

## Install

Download `karaoke.koplugin-vX.Y.Z.zip` from the
[latest release](https://github.com/shrirambalaji/karaoke/releases/latest) and
unzip it into KOReader's `plugins` directory. The zip contains the
`karaoke.koplugin/` folder itself, so there is nothing to rearrange:

```sh
unzip karaoke.koplugin-v0.6.0.zip -d /mnt/onboard/.adds/koreader/plugins/
```

Or from a clone, if you would rather:

```sh
git clone https://github.com/shrirambalaji/karaoke
cp -r karaoke/karaoke.koplugin /mnt/onboard/.adds/koreader/plugins/
```

Either way the destination is KOReader's `plugins` directory:

| Device | Destination |
| --- | --- |
| Kobo | `/mnt/onboard/.adds/koreader/plugins/karaoke.koplugin/` |
| Kindle | `/mnt/us/koreader/plugins/karaoke.koplugin/` |
| Flatpak | `~/.var/app/rocks.koreader.KOReader/config/koreader/plugins/karaoke.koplugin/` |
| AppImage | `~/.config/koreader/plugins/karaoke.koplugin/` |
| Desktop / emulator | `<koreader>/plugins/karaoke.koplugin/` |

Restart KOReader. The plugin appears under **Tools → More tools → Karaoke**
(the hamburger menu in the file manager).

### Upgrading from KaraKo

0.8.0 renamed the plugin from KaraKo to Karaoke, so the folder and the file names
changed. Upgrading is a folder swap plus one clean-up:

```sh
unzip karaoke.koplugin-vX.Y.Z.zip -d /mnt/onboard/.adds/koreader/plugins/
rm -rf /mnt/onboard/.adds/koreader/plugins/karako.koplugin
```

Leaving both folders in place installs the plugin twice, under two names, with
two menu entries — so delete the old one rather than layering over it.

Your settings come with you, on first start, with nothing to do:

- `settings/karako.lua` — the server address, API key and every other setting —
  is copied to `karaoke.lua`.
- `karaoke.conf` is used from then on; an existing `karako.conf` is still read
  as a fallback, so a device that seeded itself from one keeps its setup.
- `karaoke_queue.lua` replaces `karako_queue.lua`; links already queued in the
  old file are sent, not lost.

**Gestures need re-binding.** The dispatcher action ids changed from `karako_*`
to `karaoke_*`, so anything you bound under **Settings → Gestures** points at an
id that no longer exists. Re-bind from the names you see in the list
(`karaoke_sync`, `karaoke_add`, `karaoke_upload_queue`, …). Nothing rewrites
them for you: a binding stores the id itself, so one pointing at `karako_sync`
now just does nothing.

Downloaded articles are untouched — filenames carry the Karakeep bookmark ID in
an unchanged `[kk-id_…]` marker, not the plugin's name, so nothing is
re-downloaded and nothing stops being archived.

### Flatpak and AppImage

These two do not use the `plugins` directory next to the application — that one
is read-only under Flatpak. KOReader also scans a writable plugin directory
inside its data directory, and that is where the plugin has to go:

```sh
mkdir -p ~/.var/app/rocks.koreader.KOReader/config/koreader/plugins
cp -r karaoke/karaoke.koplugin ~/.var/app/rocks.koreader.KOReader/config/koreader/plugins/
```

`datastorage.lua` picks that path whenever `FLATPAK`, `APPIMAGE` or
`KO_MULTIUSER` is set in the environment: the data directory becomes
`$XDG_CONFIG_HOME/koreader`, which Flatpak redirects into
`~/.var/app/rocks.koreader.KOReader/config`. Confirm the plugin was found with:

```sh
flatpak run rocks.koreader.KOReader 2>&1 | grep -iE "Looking for plugins|karaoke"
```

You want two lines — the directory being scanned, and `Plugin loaded karaoke`.

One further Flatpak gotcha: the sandbox restricts filesystem access, so the
**download folder must be somewhere KOReader can write**. Check what it is
allowed to reach with `flatpak info --show-permissions rocks.koreader.KOReader`,
and grant more if you need to:

```sh
flatpak override --user --filesystem=~/Books rocks.koreader.KOReader
```

## If a sync downloads nothing

The most common cause is the download folder. Before fetching anything, Karaoke
now checks that the folder exists — creating it if not — and that it can
actually write there, and says so plainly if it cannot. Previously an unwritable
folder surfaced only as every article failing to build, one line at a time, deep
inside the zip writer.

Under Flatpak this is the likely default rather than an edge case: the sandbox
reaches very little of your filesystem. Check what it is allowed:

```sh
flatpak info --show-permissions rocks.koreader.KOReader
flatpak override --user --filesystem=~/Books rocks.koreader.KOReader
```

Anywhere under the data directory itself always works, because KOReader owns it:

```
~/.var/app/rocks.koreader.KOReader/config/koreader/karaoke/
```

On a Kobo, somewhere under `/mnt/onboard` is both writable and visible to the
native library.

If the folder is fine and articles still fail, the sync summary now names the
first reason, and the log has one line per failure tagged `Karaoke:`.

## Seeing the log

KOReader logs to standard output, so start it from a terminal:

```sh
flatpak run rocks.koreader.KOReader          # Flatpak
./koreader-*.AppImage                        # AppImage
```

The default log level is `info`, which hides this plugin's `logger.dbg` lines —
including every API request. Pass `-d` for debug, or `-d -v` for verbose:

```sh
flatpak run rocks.koreader.KOReader -d
```

It can also be turned on persistently in the UI, under
**Help → Report a bug → Enable verbose logging**.

The first thing the plugin logs is which copy of itself is running, which is the
quickest way to catch a stale install — the line numbers in a stack trace will
not tell you:

```
INFO  Karaoke: version 0.6.0, main.lua modified 2026-08-02 09:14:03, loaded from …/plugins/karaoke.koplugin
```

If that timestamp is older than your last `cp`, KOReader is running the previous
copy. Delete the destination folder before copying over it.

Lines from this plugin are tagged `Karaoke:`, and HTTP requests `KaraokeApi:`:

```sh
flatpak run rocks.koreader.KOReader -d 2>&1 | grep -iE "karaoke"
```

Note that on desktop platforms nothing redirects output to `crash.log`, unlike
on a Kobo or Kindle — stdout is the only place the log appears.

## Set up

1. **Karaoke → Server.** Enter your server's base address (e.g.
   `https://karakeep.example.com`, or `http://192.168.1.10:3000` on a LAN) and
   your API key. `Save and test` reports whether the address and key work — a
   pasted `/api/v1` suffix is stripped for you.
2. **Karaoke → Download folder.** Pick where articles should live. On a Kobo,
   somewhere under `/mnt/onboard` keeps them visible in the native library too.
3. **Karaoke → What to sync.** All unarchived bookmarks (the default), or a
   single list or tag — the plugin fetches your lists and tags to choose from.
4. **Karaoke → Synchronise now.**

You can bind *Synchronise Karaoke* to a gesture under
**Settings → Gestures**.

### Setting up from a file instead

Typing an API key on an e-reader keyboard is miserable, so settings can be read
from a plain text file instead. **Karaoke → Settings file → Create an example
file** writes a commented one for you; edit it on a computer and use *Reload it
now*, or just restart KOReader.

```ini
# karaoke.conf
server_url = https://karakeep.example.com
api_token  = ak1_your_key_here
directory  = /mnt/onboard/karakeep

articles_per_sync = 50
download_images   = false
archive_tag       = read-on-kobo
```

Checked in this order, first found wins — **Settings file → Where Karaoke looks**
shows the list with the active one ticked:

1. `<koreader data dir>/karaoke.conf`
2. `<koreader data dir>/settings/karaoke.conf`
3. `karaoke.koplugin/karaoke.conf`, next to the plugin

Then those three paths again under the pre-0.8.0 name, `karako.conf`, so a file
written before the rename still seeds. A `karaoke.conf` always wins where both
exist, whichever location they are in.

On Flatpak the data directory is
`~/.var/app/rocks.koreader.KOReader/config/koreader`; on a Kobo it is
`/mnt/onboard/.adds/koreader`.

Notes on how it behaves:

- The file **seeds** settings the first time Karaoke runs. They then appear in the
  menus like any other setting, and **whatever you set in the menus wins** from
  that point on.
- Editing the file later does nothing by itself. Use **Settings file → Reload it
  now** to pull the changes in, which overwrites the matching settings.
- Anything the file leaves out is under the menu's control from the start.
- Values are taken literally to end of line, so URLs and tokens need no quoting.
  `key: value` works as well as `key = value`; `#` and `;` start a comment;
  booleans accept `true/false`, `yes/no`, `on/off`, `1/0`.
- A misspelled setting is **reported in the log**, not silently ignored.
- The file holds your API key in plain text. Keep it readable only by you, and
  give the device its own key so it can be revoked on its own.

## Rebuilding articles you already have

An article on the device is skipped on every later sync — that is what stops a
sync re-fetching your whole library each time. It also means an improvement to
how EPUBs are built reaches only *new* articles, with no way to apply it to the
ones you have short of deleting files by hand and guessing which were affected.

**Karaoke → Rebuild all articles** re-fetches every article on the device and
builds it again. Use it after upgrading Karaoke. It is also bindable as a gesture,
under **Settings → Gestures**.

- Read status and highlights are **sent to Karakeep first**, so nothing is lost
  server-side even if a rebuild goes wrong.
- Existing copies are **written over in place**, keeping the filename, so the
  `.sdr` sidecar stays attached and your highlights and reading position survive.
  A rebuilt article may position highlights differently, though, since they are
  anchored into a document that has changed.
- If the title changed in Karakeep since you downloaded it, the new title goes
  into the EPUB's metadata but the **file keeps its old name** — renaming it
  would strand the sidecar and leave you with two copies.
- A build that fails leaves the copy already on the device untouched: EPUBs are
  assembled into a temporary file and only renamed over the original once the
  whole archive is written.
- Only articles still unarchived in Karakeep come back. Anything archived there
  is out of the sync scope and is left alone.

## How articles are named

Downloads are named `Article Title [kk-id_abc123].epub`. The bracketed marker is
how the Karakeep bookmark ID survives a round trip through the filesystem — it is
what lets a later sync know that an article is already on the device, archive the
right bookmark when you finish it, and attach your highlights to it. There is no
separate index to fall out of step.

It sits at the **end** so the title is what you see. Earlier versions led with it,
which put an opaque ID where the title should be and, since a file browser
truncates the end of a long name, pushed the title out of sight entirely. It also
made the folder sort by ID rather than alphabetically.

Both forms are read back the same way, so upgrading orphans nothing and
re-downloads nothing. Articles already on the device are renamed to match on the
next sync — reading progress, highlights and collection membership follow the
file. There is nothing to turn on and nothing to run; once the folder is
consistent the check costs nothing and never fires again.

Renaming an article yourself is fine, as long as the `[kk-id_…]` marker survives
somewhere in the name. Remove it and Karaoke stops recognising the file: it will
download the article again and will never archive it.

## Automatic syncing

Off by default. **Karaoke → Sync when Wi-Fi connects** reacts to the network
coming up — it never turns the radio on itself, which would be a bad trade on a
device that spends most of its life asleep.

What it does depends on what you are doing:

- **Reading a document** — sends read status and highlights only. That is the
  half that goes stale on the server, it needs no progress dialogs, and so it
  cannot interrupt you. Downloads wait.
- **In the file manager** — a full sync, reporting to a transient notification
  rather than a modal.

**Sync at most every** (default 30 minutes) stops a flaky connection from
syncing repeatedly. Manual *Synchronise now* ignores the limit.

Whether to bother is a fair question. The plugin is designed so that nothing is
lost by syncing late: read status and highlights live durably in KOReader's
`.sdr` sidecars and are reconciled against the server on every run, so a sync
you never got round to is caught by the next one. Automatic syncing buys
timeliness, not correctness. If you sync manually often enough to keep the
device stocked, manual is perfectly sound.

## What syncs which way, and what happens on a conflict

There is no conflict *resolution* here, and it is worth being plain about that
rather than implying more than the plugin does.

| Thing | Direction | On conflict |
| --- | --- | --- |
| Article content | Karakeep → device | Re-downloaded only if missing locally |
| Uploaded originals (PDF, images) | Karakeep → device | Saved as-is; re-downloaded only if missing locally |
| Finished / read | device → Karakeep | Device wins. Un-archiving in Karakeep while the local copy is finished re-archives it on the next sync |
| Archived elsewhere | Karakeep → device | Local copy deleted, **but only if you never opened it** |
| Highlights | device → Karakeep | Create-only, matched by text. See below |
| Reading position | neither | Not synced at all — that is [KOSync][kosync]'s job, between KOReader devices |
| Tags, title, notes | Karakeep → device | Read at download time; later edits do not reach an already-downloaded copy |

[kosync]: https://github.com/koreader/koreader/tree/master/plugins/kosync.koplugin

### Highlights specifically

Highlights are pushed one way and never deleted or updated, and the matching is
by text because nothing else is shared between the two sides. The consequences
are worth knowing:

- **Deleting a highlight in KOReader does not delete it in Karakeep.**
- **Deleting a highlight in Karakeep brings it back.** It is still in the local
  sidecar, and the next sync sees it missing from the server and recreates it.
  To be rid of one, delete it on the device as well.
- **Editing a highlight's text in Karakeep creates a duplicate**, because the
  local text no longer matches anything on the server.
- **Editing only the note in KOReader changes nothing remotely** — the text
  still matches, so the highlight is treated as already present.
- Highlighting the same passage twice on the device sends it once.

If any of that bothers you, **Karaoke → Send highlights to Karakeep** turns the
whole thing off and nothing is written.

## How highlights are matched

This is the one part that is best-effort, and it is worth understanding — it
also changed on the server side in **Karakeep 0.35.0 (2026-11-15)**, so which
half of it you get depends on your version.

KOReader records a highlight's position as a crengine XPointer into *the EPUB
this plugin generated*. Karakeep's `/highlights` API wants a position inside
*its own* rendered content. The two coordinate systems have nothing in common,
so the only thing both sides genuinely share is the highlighted text itself.

What the plugin sends is the text, your note and the chapter title, plus
character offsets wherever it can work them out:

- A passage found exactly once in the article gets correct offsets.
- A passage appearing more than once resolves to its **first** occurrence, which
  may not be the one you highlighted.
- A passage that cannot be found at all is still sent, with the text and your
  note intact but no position (offsets `0,0`). Losing the note seemed worse than
  an unanchored highlight.
- Highlights already in Karakeep with the same text are skipped, so repeated
  syncs do not pile up duplicates.

Offsets are counted in UTF-16 code units, because that is how a JavaScript
string is indexed and Karakeep is a JavaScript application. Counting bytes
instead — which is what Lua does by default — puts every highlight in an article
progressively out of place as soon as it contains anything outside ASCII, and a
single curly quote or em-dash is enough.

**On Karakeep 0.35.0 and later the offsets matter much less.** That release
changed the server to find a highlight by its text *and the text around it*
rather than by raw offsets, so a highlight this plugin could only place
approximately — or not at all — still lands on the right words, and survives the
article being re-crawled. The offsets are still sent, and still used by older
servers, but they are no longer the thing that decides where a highlight appears.

Your note and the chapter title travel with the highlight. Highlight colours are
mapped onto the four Karakeep supports; anything else becomes yellow.

## Notes and limitations

### Fork-specific

- **`remote_delete_instead_of_archive` deletes the bookmark in Karakeep**, and
  nothing on the device can undo it. Archiving, the default, only moves it out
  of the unread list.
- **PDFs are not converted.** If Karakeep holds an article whose crawled content
  is a PDF, you get whatever Karakeep extracted (usually text), not the PDF.
  Only actual uploaded files are saved as files.
- **Highlights for PDFs stay on the device.** See above.
- **`only_favourited` with a list or tag scope** is applied client-side, and only
  when the server actually reports the `favourited` field; a page that omits it
  is not mistaken for "nothing is a favourite", which would empty the scope.

- **Karakeep has no EPUB export endpoint**, unlike Wallabag, so the plugin builds
  the EPUB itself: it sanitises the crawled HTML, hands it to crengine's
  `getBalancedHTML()` to make it well-formed, fetches images, and writes the
  container with `ffi/archiver`. Image-heavy articles are noticeably slower on
  Kobo hardware than a plain text sync — turn off *Embed images* if you mind.
- **Only `link` and `text` bookmarks sync.** Asset bookmarks (uploaded PDFs and
  images) are skipped; they are already in a readable format and do not need us.
- **Lazy-loaded images are resolved.** Karakeep's extraction keeps a page's
  original markup, so articles from sites that lazy-load arrive with a
  placeholder in `src` and the real picture in `data-src`, `data-original`,
  `srcset` and friends. Those are read in preference to `src`, and a `<noscript>`
  block is unwrapped when it contains the plain `<img>` such sites hide there.
  From a `srcset`, the widest candidate up to 1600px wins.
- **WebP is embedded.** crengine links libwebp and renders it — verified by
  page count, since a tall WebP takes a one-page document to three. An earlier
  version excluded WebP on the assumption it could not, which quietly dropped a
  large share of images from modern sites.
- Image types are detected from their magic bytes rather than the URL's
  extension, and any image that fails to download has its `<img>` removed so you
  never see a broken image box.
- **Image embedding is bounded**, at 2 MB for any one image and 8 MB across an
  article, on top of the *Embed images* count limit. Every image is held in
  memory until the EPUB is written, and a Kobo has little to spare; an article
  pointing at print-resolution photographs would otherwise take all of it.
  Anything over the limit is dropped with its `<img>`, and the log names it.
- **Local deletion is conservative.** Articles are only removed when the sync saw
  your whole library uninterrupted — never after a capped or cancelled run — and
  never if you have opened them. An article archived on another device is tidied
  up on the next full sync. A consequence worth knowing: if your unread count
  exceeds *Articles per sync*, every run is capped, so this cleanup never
  happens until the backlog drops below the limit.
- **The API key is stored in the clear** in
  `koreader/settings/karaoke.lua`, as KOReader has no keystore. It is worth
  giving the device its own key so you can revoke just that one.

## Optionally, an OPDS bridge

If you would rather have the EPUBs generated server-side, [yazdipour/karakeep-opds][opds]
exposes Karakeep as an OPDS catalog that KOReader's built-in OPDS browser can
read. It produces nicer EPUBs than anything achievable in Lua on a Kobo.

It is not a replacement for this plugin, though — OPDS is a download-only
protocol, so nothing flows back: no archive-on-finish and no highlights. The two
compose well, since its acquisition links carry the Karakeep bookmark ID
(`/opds/bookmarks/{id}.epub`).

[opds]: https://github.com/yazdipour/karakeep-opds

## Development

```sh
make check  # syntax and accidental globals, every file
make test   # the spec suite, any Lua 5.1
make dist   # build the installable zip
```

### Cutting a release

The version lives in `karaoke.koplugin/_meta.lua` and nowhere else. Bump it,
commit, then tag to match:

```sh
git tag v0.6.0 && git push origin v0.6.0
```

`.github/workflows/release.yml` runs the checks and the specs, refuses the tag if
it disagrees with `_meta.lua`, builds `karaoke.koplugin-v0.6.0.zip` and attaches
it to a GitHub release with generated notes.

`articleutil.lua` has no KOReader dependencies and carries the bulk of the fiddly
logic, so it is directly testable off-device. EPUB assembly needs the real
crengine and libarchive; `tools/epubcheck.lua` drives those headlessly against an
extracted KOReader AppImage — no build required.

See [TESTING.md](TESTING.md), which also lists what is verified and what still
needs checking on a real Kobo.

## Licence

AGPL-3.0-or-later, matching KOReader, whose modules this plugin builds on.
