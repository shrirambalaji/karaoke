--[[--
Headless check for EpubBuilder.build() against a real KOReader.

`make test` covers the pure Lua, but EPUB assembly needs crengine (for
getBalancedHTML) and libarchive (for the zip), neither of which can be faked
usefully. This script drives the real ones without starting the UI.

Run it from inside an extracted KOReader AppImage — see TESTING.md:

    cd squashfs-root/usr/lib/koreader
    ./luajit tools/epubcheck.lua

Exits non-zero if any check fails.
]]

require("setupkoenv")

-- Required before anything pulls in KOReader's device layer, which the image
-- fetching path does.
local DataStorage = require("datastorage")
G_reader_settings = require("luasettings"):open(
    DataStorage:getDataDir() .. "/settings.reader.lua")

package.path = "plugins/karaoke.koplugin/?.lua;" .. package.path

local cre = require("libs/libkoreader-cre")
os.execute("mkdir -p /tmp/kk-crcache")
pcall(cre.initCache, "/tmp/kk-crcache", 0, true, 40)

local EpubBuilder = require("epubbuilder")

local failures = 0

local function check(name, condition, detail)
    if condition then
        print("  ok   " .. name)
    else
        failures = failures + 1
        print("  FAIL " .. name .. (detail and ("  -> " .. tostring(detail)) or ""))
    end
end

local function readEntry(epub_path, entry)
    local pipe = io.popen(string.format("unzip -p %q %q 2>/dev/null", epub_path, entry))
    if not pipe then return nil end
    local content = pipe:read("*a")
    pipe:close()
    return content ~= "" and content or nil
end

--------------------------------------------------------------------------------
print("Ragged HTML is balanced into a valid EPUB")
--------------------------------------------------------------------------------

local ragged = {
    id = "epubcheck1",
    title = "A Test Article",
    note = "note from Karakeep",
    content = {
        type = "link",
        url = "https://example.com/a",
        author = "A. Writer",
        publisher = "Example Press",
        datePublished = "2026-01-15T09:00:00.000Z",
        htmlContent = [[<p>unclosed paragraph
<p>second &amp; third <em>emphasis <b>nested</b></p></div>
<h2>heading</h2><ul><li>one<li>two</ul>
<blockquote>Caf&#233; &mdash; na&iuml;ve</blockquote>
<script>alert("stripped")</script><p onclick="evil()">final.</p>]],
    },
    tags = { { id = "t1", name = "testing" } },
}

local plain_path = "/tmp/kk-epubcheck-plain.epub"
local built, build_err = EpubBuilder.build(ragged, plain_path, { include_images = false })
check("build succeeds", built, build_err)

local xhtml = readEntry(plain_path, "OEBPS/content.xhtml")
check("content.xhtml exists", xhtml ~= nil)

if xhtml then
    -- The point of the crengine pass: without it these stay broken.
    check("unclosed <p> is closed", xhtml:find("<p>unclosed paragraph </p>", 1, true) ~= nil)
    check("mis-nested <em> is closed", xhtml:find("<b>nested</b></em>", 1, true) ~= nil)
    check("stray </div> is dropped", xhtml:find("</div>", 1, true) == nil)
    check("<li> items are closed", xhtml:find("<li>one</li>", 1, true) ~= nil)

    -- Sanitising happens before crengine sees it.
    check("<script> is stripped", xhtml:find("alert(", 1, true) == nil)
    check("onclick is stripped", xhtml:find("onclick", 1, true) == nil)

    check("entities become UTF-8", xhtml:find("Caf\195\169", 1, true) ~= nil)
    check("XML declaration is present", xhtml:find("<?xml", 1, true) == 1)
    check("xhtml namespace survives", xhtml:find("xmlns=", 1, true) ~= nil)
    check("metadata is rendered", xhtml:find("A. Writer", 1, true) ~= nil)
    check("Karakeep note travels with it", xhtml:find("note from Karakeep", 1, true) ~= nil)
end

for _, entry in ipairs({ "mimetype", "META-INF/container.xml", "OEBPS/content.opf",
                         "OEBPS/toc.ncx", "OEBPS/stylesheet.css" }) do
    check("archive contains " .. entry, readEntry(plain_path, entry) ~= nil)
end

--------------------------------------------------------------------------------
print("Every h2 and h3 gets an id, and a navPoint to match")
--------------------------------------------------------------------------------

-- The table of contents is only as good as the ids it points at, so this
-- asserts both halves: the ids have to survive crengine's balancer, and the NCX
-- has to point at them in reading order. Nesting is asserted on the XML rather
-- than trusted from ArticleUtil.tocFromHeadings(), which the specs already cover.
local sectioned = {
    id = "epubcheck-toc",
    title = "Sectioned",
    content = {
        type = "link",
        url = "https://example.com/s",
        language = "de",
        htmlContent = [[<p>intro</p>
<h2>First part</h2><p>a</p>
<h3>Detail</h3><p>b</p>
<h2>Second part</h2><p>c</p>
<h2>Repeated</h2><h2>Repeated</h2>]],
    },
}

local toc_path = "/tmp/kk-epubcheck-sections.epub"
local toc_built, toc_err = EpubBuilder.build(sectioned, toc_path, { include_images = false })
check("build with headings succeeds", toc_built, toc_err)

local toc_xhtml = readEntry(toc_path, "OEBPS/content.xhtml") or ""
local toc_ncx = readEntry(toc_path, "OEBPS/toc.ncx") or ""
local toc_opf = readEntry(toc_path, "OEBPS/content.opf") or ""

check("headings get ids, and crengine keeps them",
    toc_xhtml:find('id="kk-s1"', 1, true) ~= nil, toc_xhtml:sub(1, 500))
check("every heading is numbered", select(2, toc_xhtml:gsub('id="kk%-s%d', "")) == 5,
    (select(2, toc_xhtml:gsub('id="kk%-s%d', ""))))
check("repeated heading text still gets distinct ids",
    toc_xhtml:find('id="kk-s4"', 1, true) ~= nil and toc_xhtml:find('id="kk-s5"', 1, true) ~= nil)

-- One navPoint for the article itself, then one per heading.
check("there is a navPoint per heading, plus the article",
    select(2, toc_ncx:gsub("<navPoint ", "")) == 6,
    (select(2, toc_ncx:gsub("<navPoint ", ""))))
check("a navPoint points at the heading's id",
    toc_ncx:find('src="content.xhtml#kk-s1"', 1, true) ~= nil)

local outer_at = toc_ncx:find('src="content.xhtml#kk-s1"', 1, true) or 0
local inner_at = toc_ncx:find('src="content.xhtml#kk-s2"', 1, true) or 0
local first_close = toc_ncx:find("</navPoint>", outer_at, true) or 0
check("the h3 sits inside its h2's navPoint",
    outer_at > 0 and inner_at > outer_at and inner_at < first_close,
    string.format("outer=%d inner=%d close=%d", outer_at, inner_at, first_close))

check("dc:language comes from the bookmark, not hardcoded",
    toc_opf:find("<dc:language>de</dc:language>", 1, true) ~= nil)

--------------------------------------------------------------------------------
print("Images are fetched, sniffed and embedded")
--------------------------------------------------------------------------------

-- Needs a local fixture server; skipped when it is not running.
local base = os.getenv("KK_IMG_SERVER")

if not base then
    print("  skip (set KK_IMG_SERVER, e.g. http://127.0.0.1:8799/, to run these)")
else
    local with_images = {
        id = "epubcheck2",
        title = "Image Test",
        content = {
            type = "link",
            url = "https://example.com/i",
            htmlContent = table.concat({
                '<p>a</p><img src="' .. base .. 'a.png">',
                -- Extension lies about the content; the bytes must win.
                '<p>b</p><img src="' .. base .. 'liar.jpg">',
                -- An HTML error page served where an image was expected.
                '<p>c</p><img src="' .. base .. 'broken.png">',
                '<p>d</p><img src="http://127.0.0.1:9/unreachable.png">',
                -- Same source twice: one file, two references.
                '<p>e</p><img src="' .. base .. 'a.png">',
            }),
        },
    }

    local image_path = "/tmp/kk-epubcheck-images.epub"
    local ok_images = EpubBuilder.build(with_images, image_path, { include_images = true })
    check("build with images succeeds", ok_images)

    local opf = readEntry(image_path, "OEBPS/content.opf") or ""
    local body = readEntry(image_path, "OEBPS/content.xhtml") or ""

    check("real image is embedded", readEntry(image_path, "OEBPS/images/img1.png") ~= nil)
    check("media type comes from the bytes, not the URL",
        opf:find('href="images/img2.jpg" media%-type="image/png"') ~= nil)
    check("non-image response is rejected", readEntry(image_path, "OEBPS/images/img3.png") == nil)
    check("unreachable image is rejected", readEntry(image_path, "OEBPS/images/img4.png") == nil)
    check("failed images leave no <img> behind",
        select(2, body:gsub("<img", "")) == 3)
    check("duplicate source is embedded once",
        readEntry(image_path, "OEBPS/images/img5.png") == nil)
    check("all paragraphs survive", select(2, body:gsub("<p>", "")) >= 5)

    ----------------------------------------------------------------------------
    print("Budgets and cancellation")
    ----------------------------------------------------------------------------

    -- A budget too small for even the first image: everything is dropped, and
    -- the article is still built rather than failing outright.
    local starved_path = "/tmp/kk-epubcheck-starved.epub"
    local ok_starved = EpubBuilder.build(with_images, starved_path, {
        include_images = true,
        max_image_bytes_total = 1,
    })
    check("build succeeds with the image budget spent", ok_starved)
    check("no image is embedded once the budget is spent",
        readEntry(starved_path, "OEBPS/images/img1.png") == nil)
    check("and no <img> is left pointing at one",
        (readEntry(starved_path, "OEBPS/content.xhtml") or ""):find("<img", 1, true) == nil)

    -- A progress callback that answers false is the reader cancelling.
    local cancel_path = "/tmp/kk-epubcheck-cancel.epub"
    os.remove(cancel_path)
    local ok_cancel, cancel_reason = EpubBuilder.build(with_images, cancel_path, {
        include_images = true,
        progress = function() return false end,
    })
    check("a progress callback returning false aborts", ok_cancel == false)
    check("and says why", cancel_reason == "cancelled", cancel_reason)
    check("and leaves no file behind", readEntry(cancel_path, "mimetype") == nil)
end

--------------------------------------------------------------------------------
print("Covers are declared the EPUB 2 way, and are optional")
--------------------------------------------------------------------------------

-- A minimal PNG header: enough for sniffImageType() to recognise the bytes. They
-- are never decoded here -- crengine only reads them when the book is opened --
-- so what matters is that the sniffed type, the filename and the manifest all
-- agree.
local TINY_PNG = "\137PNG\r\n\26\n\000\000\000\rIHDR\000\000\000\001\000\000\000\001\008\002\000\000\000"

local covered = {
    id = "epubcheck-cover",
    title = "Covered",
    content = {
        type = "link",
        url = "https://example.com/c",
        imageAssetId = "asset-1",
        -- Also set, but the asset is preferred: this must not be what ends up in
        -- the package, and it is unreachable so it could not be anyway.
        imageUrl = "http://127.0.0.1:9/unreachable.png",
        htmlContent = "<p>body</p>",
    },
}

local cover_path = "/tmp/kk-epubcheck-cover.epub"
local asked_for = {}
local ok_cover = EpubBuilder.build(covered, cover_path, {
    include_images = false,
    fetch_asset = function(asset_id, max_bytes)
        asked_for[#asked_for + 1] = { id = asset_id, max = max_bytes }
        return TINY_PNG
    end,
})
check("build with a cover succeeds", ok_cover)

local cover_opf = readEntry(cover_path, "OEBPS/content.opf") or ""

check("the cover asset is asked for by id", asked_for[1] and asked_for[1].id == "asset-1")
check("and with a size budget", asked_for[1] and asked_for[1].max ~= nil)
check("the cover page is in the archive", readEntry(cover_path, "OEBPS/cover.xhtml") ~= nil)
check("the cover image is in the archive, named for its sniffed type",
    readEntry(cover_path, "OEBPS/images/cover.png") ~= nil)
check("EPUB 2 declares it with <meta name=\"cover\">",
    cover_opf:find('<meta name="cover" content="cover-img"/>', 1, true) ~= nil)
check("the manifest item id is the one the meta names",
    cover_opf:find('id="cover-img" href="images/cover.png" media-type="image/png"', 1, true) ~= nil)
check("the cover page is in the manifest",
    cover_opf:find('id="cover-page" href="cover.xhtml"', 1, true) ~= nil)
check("the cover comes first in the spine",
    (cover_opf:find('idref="cover-page"', 1, true) or 0) < (cover_opf:find('idref="content"', 1, true) or 0))
check("the guide still points at the text",
    cover_opf:find('reference type="text"', 1, true) ~= nil)
check("no EPUB 3 cover property is claimed", cover_opf:find("properties=", 1, true) == nil)

local cover_page = readEntry(cover_path, "OEBPS/cover.xhtml") or ""
check("the cover page references the image that was written",
    cover_page:find('src="images/cover.png"', 1, true) ~= nil)

-- Turned off: the same bookmark, no cover, nothing declared.
local bare_path = "/tmp/kk-epubcheck-nocover.epub"
local ok_bare = EpubBuilder.build(covered, bare_path, {
    include_images = false,
    include_covers = false,
})
check("covers can be turned off", ok_bare)
check("and then nothing claims to be one",
    (readEntry(bare_path, "OEBPS/content.opf") or ""):find('name="cover"', 1, true) == nil)
check("and no cover page is written", readEntry(bare_path, "OEBPS/cover.xhtml") == nil)

-- A 404 page served where a cover was expected must not become one.
local not_image_path = "/tmp/kk-epubcheck-badcover.epub"
local ok_not_image = EpubBuilder.build(covered, not_image_path, {
    include_images = false,
    fetch_asset = function() return "<!DOCTYPE html><html>404</html>" end,
})
check("a non-image cover is skipped rather than embedded", ok_not_image)
check("and leaves no cover page behind", readEntry(not_image_path, "OEBPS/cover.xhtml") == nil)
check("and the article is still readable",
    readEntry(not_image_path, "OEBPS/content.xhtml") ~= nil)

-- The URL fallback needs real HTTP; skipped along with the image checks.
local cover_base = os.getenv("KK_IMG_SERVER")

if cover_base then
    local url_cover = {
        id = "epubcheck-urlcover",
        title = "Cover from the page",
        content = {
            type = "link",
            url = "https://example.com/u",
            -- No imageAssetId: the page's own image is the only source.
            imageUrl = cover_base .. "a.png",
            htmlContent = "<p>body</p>",
        },
    }

    local url_cover_path = "/tmp/kk-epubcheck-urlcover.epub"
    local ok_url_cover = EpubBuilder.build(url_cover, url_cover_path, { include_images = false })
    check("a cover can come from the page's own image", ok_url_cover)
    check("fetched over http and stored under the type its bytes give",
        readEntry(url_cover_path, "OEBPS/images/cover.png") ~= nil)

    -- And a broken URL is skipped, not fatal.
    local broken_cover = {
        id = "epubcheck-badurlcover",
        title = "Broken cover",
        content = {
            type = "link",
            url = "https://example.com/b",
            imageUrl = cover_base .. "broken.png",
            htmlContent = "<p>body</p>",
        },
    }
    local broken_path = "/tmp/kk-epubcheck-badurlcover.epub"
    check("an HTML error page at the cover URL is skipped",
        EpubBuilder.build(broken_cover, broken_path, { include_images = false }))
    check("and the article survives without a cover",
        readEntry(broken_path, "OEBPS/content.xhtml") ~= nil
            and readEntry(broken_path, "OEBPS/cover.xhtml") == nil)
else
    print("  skip cover-from-URL checks (set KK_IMG_SERVER to run them)")
end

--------------------------------------------------------------------------------
print("")
if failures == 0 then
    print("epubcheck: all checks passed")
    os.exit(0)
end
print(string.format("epubcheck: %d check(s) failed", failures))
os.exit(1)
