local Runner = require("spec.runner")
local ArticleUtil = require("articleutil")

local describe, it = Runner.describe, Runner.it
local assertEqual, assertTrue, assertNil = Runner.assertEqual, Runner.assertTrue, Runner.assertNil
local assertMatch, assertNoMatch = Runner.assertMatch, Runner.assertNoMatch

describe("getBookmarkId", function()
    it("reads the ID back out of a filename", function()
        assertEqual(ArticleUtil.getBookmarkId("[kk-id_abc123] Some Article.epub"), "abc123")
    end)

    it("works on a full path", function()
        assertEqual(ArticleUtil.getBookmarkId("/mnt/onboard/karakeep/[kk-id_xy9] T.epub"), "xy9")
    end)

    it("survives a title containing the postfix", function()
        assertEqual(ArticleUtil.getBookmarkId("[kk-id_abc] Lists] and things.epub"), "abc")
    end)

    it("reads the trailing marker current versions write", function()
        assertEqual(ArticleUtil.getBookmarkId("Some Article [kk-id_abc123].epub"), "abc123")
        assertEqual(ArticleUtil.getBookmarkId("/mnt/onboard/kk/A Title [kk-id_xy9].epub"), "xy9")
    end)

    it("still reads the leading marker earlier versions wrote", function()
        -- Downloads made before the rename must not be orphaned or re-fetched.
        assertEqual(ArticleUtil.getBookmarkId("[kk-id_abc123] Some Article.epub"), "abc123")
    end)

    it("ignores files that are not ours", function()
        assertNil(ArticleUtil.getBookmarkId("Some Other Book.epub"))
        assertNil(ArticleUtil.getBookmarkId("[w-id_12] A wallabag article.epub"))
        assertNil(ArticleUtil.getBookmarkId("[kk-id_] Empty.epub"))
        assertNil(ArticleUtil.getBookmarkId("[kk-id_abc"))
        assertNil(ArticleUtil.getBookmarkId(nil))
    end)
end)

describe("safeTitle", function()
    it("replaces characters FAT32 cannot store", function()
        assertEqual(ArticleUtil.safeTitle('a/b\\c:d*e?f"g<h>i|j'), "a_b_c_d_e_f_g_h_i_j")
    end)

    it("neutralises brackets so the ID prefix stays unambiguous", function()
        assertEqual(ArticleUtil.safeTitle("[draft] Notes"), "(draft) Notes")
    end)

    it("collapses whitespace and trims", function()
        assertEqual(ArticleUtil.safeTitle("  a   b  "), "a b")
    end)

    it("never returns an empty name", function()
        assertEqual(ArticleUtil.safeTitle(""), "Untitled")
        assertEqual(ArticleUtil.safeTitle(nil), "Untitled")
        assertEqual(ArticleUtil.safeTitle("..."), "Untitled")
    end)

    it("does not end in a dot or a space", function()
        assertEqual(ArticleUtil.safeTitle("Ends with a dot."), "Ends with a dot")
    end)

    it("truncates to the byte budget", function()
        assertTrue(#ArticleUtil.safeTitle(string.rep("x", 500), 40) <= 40)
    end)
end)

describe("trimPartialUtf8", function()
    it("leaves complete strings alone", function()
        assertEqual(ArticleUtil.trimPartialUtf8("caf\195\169"), "caf\195\169")
        assertEqual(ArticleUtil.trimPartialUtf8("plain"), "plain")
    end)

    it("drops a dangling multi-byte sequence", function()
        -- "café" cut one byte short of the é
        assertEqual(ArticleUtil.trimPartialUtf8("caf\195"), "caf")
        -- a 3-byte character missing its last byte
        assertEqual(ArticleUtil.trimPartialUtf8("a\226\128"), "a")
    end)
end)

describe("buildFilename", function()
    it("puts the title first, so a file browser shows it", function()
        local name = ArticleUtil.buildFilename("k7dz", "Why Kobo?")
        assertEqual(name, "Why Kobo_ [kk-id_k7dz].epub")
        assertEqual(ArticleUtil.getBookmarkId(name), "k7dz")
    end)

    it("round-trips a title long enough to be truncated", function()
        local name = ArticleUtil.buildFilename("k7dz", string.rep("word ", 60))
        assertEqual(ArticleUtil.getBookmarkId(name), "k7dz")
        assertMatch(name, "[kk-id_k7dz].epub")
    end)

    it("round-trips even with a hostile title", function()
        local name = ArticleUtil.buildFilename("abc", "[weird] title/with: junk")
        assertEqual(ArticleUtil.getBookmarkId(name), "abc")
    end)

    it("stays within a 255 byte filename", function()
        local name = ArticleUtil.buildFilename("abc", string.rep("long ", 200))
        assertTrue(#name <= 255, "filename was " .. #name .. " bytes")
    end)
end)

describe("hasLegacyName", function()
    it("spots the leading marker", function()
        assertTrue(ArticleUtil.hasLegacyName("[kk-id_abc] Title.epub"))
        assertTrue(ArticleUtil.hasLegacyName("/mnt/kk/[kk-id_abc] Title.epub"))
    end)

    it("does not flag the current form", function()
        assertEqual(ArticleUtil.hasLegacyName("Title [kk-id_abc].epub"), false)
        assertEqual(ArticleUtil.hasLegacyName("Some Other Book.epub"), false)
        assertEqual(ArticleUtil.hasLegacyName(nil), false)
    end)
end)

describe("utf8Char", function()
    it("encodes each sequence length", function()
        assertEqual(ArticleUtil.utf8Char(65), "A")
        assertEqual(ArticleUtil.utf8Char(0xE9), "\195\169")      -- é
        assertEqual(ArticleUtil.utf8Char(0x2014), "\226\128\148") -- em dash
        assertEqual(ArticleUtil.utf8Char(0x1F600), "\240\159\152\128")
    end)
end)

describe("decodeEntities", function()
    it("decodes named entities", function()
        assertEqual(ArticleUtil.decodeEntities("a &amp; b"), "a & b")
        assertEqual(ArticleUtil.decodeEntities("&lt;tag&gt;"), "<tag>")
    end)

    it("decodes numeric entities in both bases", function()
        assertEqual(ArticleUtil.decodeEntities("caf&#233;"), "caf\195\169")
        assertEqual(ArticleUtil.decodeEntities("caf&#xE9;"), "caf\195\169")
    end)

    it("leaves unknown entities alone", function()
        assertEqual(ArticleUtil.decodeEntities("&notareal;"), "&notareal;")
    end)
end)

describe("escapeXml", function()
    it("escapes the five XML specials", function()
        assertEqual(ArticleUtil.escapeXml([[<a href="x">'&']]),
            "&lt;a href=&quot;x&quot;&gt;&apos;&amp;&apos;")
    end)

    it("escapes ampersands only once", function()
        assertEqual(ArticleUtil.escapeXml("&lt;"), "&amp;lt;")
    end)
end)

describe("sanitizeHtml", function()
    it("removes scripts and their contents", function()
        local out = ArticleUtil.sanitizeHtml('<p>a</p><script>alert("x")</script><p>b</p>')
        assertNoMatch(out, "alert")
        assertNoMatch(out, "script")
        assertMatch(out, "<p>a</p>")
        assertMatch(out, "<p>b</p>")
    end)

    it("removes styles, iframes and comments", function()
        assertNoMatch(ArticleUtil.sanitizeHtml("<style>p{color:red}</style>x"), "color")
        assertNoMatch(ArticleUtil.sanitizeHtml('<iframe src="ad"></iframe>x'), "iframe")
        assertNoMatch(ArticleUtil.sanitizeHtml("<!-- tracking -->x"), "tracking")
    end)

    it("strips inline event handlers", function()
        local out = ArticleUtil.sanitizeHtml('<p onclick="evil()">a</p>')
        assertNoMatch(out, "onclick")
        assertMatch(out, ">a</p>")
    end)

    it("defuses javascript: links", function()
        assertNoMatch(ArticleUtil.sanitizeHtml('<a href="javascript:evil()">x</a>'), "javascript:")
    end)

    it("keeps ordinary markup intact", function()
        local html = "<h2>Title</h2><p>Body with <em>emphasis</em>.</p>"
        assertEqual(ArticleUtil.sanitizeHtml(html), html)
    end)

    it("keeps id attributes, which the table of contents points at", function()
        -- The ids are added after sanitising, but the page's own anchors have to
        -- survive it: in-page links in the article refer to them.
        assertMatch(ArticleUtil.sanitizeHtml('<h2 id="kk-s1">Title</h2>'), 'id="kk-s1"')
    end)
end)

describe("htmlToText", function()
    it("flattens tags to whitespace-normalised text", function()
        assertEqual(ArticleUtil.htmlToText("<p>Hello</p>\n<p>world</p>"), "Hello world")
    end)

    it("decodes entities as it goes", function()
        assertEqual(ArticleUtil.htmlToText("<p>a &amp; b</p>"), "a & b")
    end)

    it("does not run adjacent words together", function()
        assertEqual(ArticleUtil.htmlToText("<b>one</b><i>two</i>"), "one two")
    end)
end)

describe("findTextOffsets", function()
    local text = "The quick brown fox jumps over the lazy dog near the river bank today"

    it("finds an exact passage", function()
        local first, last = ArticleUtil.findTextOffsets(text, "brown fox")
        assertEqual(first, 10)
        assertEqual(last, 19)
        assertEqual(text:sub(first + 1, last), "brown fox")
    end)

    it("normalises whitespace before matching", function()
        local first = ArticleUtil.findTextOffsets(text, "  brown\n  fox ")
        assertEqual(first, 10)
    end)

    it("falls back to a middle slice when the edges do not match", function()
        local needle = "XX quick brown fox jumps over the lazy dog YY"
        local first, last = ArticleUtil.findTextOffsets(text, needle)
        assertTrue(first, "expected the probe fallback to find something")
        assertTrue(last > first)
    end)

    it("returns nil when the passage is absent", function()
        assertNil(ArticleUtil.findTextOffsets(text, "not in the article at all"))
        assertNil(ArticleUtil.findTextOffsets(text, ""))
    end)

    it("treats the needle literally, not as a pattern", function()
        local haystack = "cost is 10% (approx) per unit"
        local first = ArticleUtil.findTextOffsets(haystack, "10% (approx)")
        assertEqual(first, 8)
    end)

    -- Karakeep indexes highlights the way JavaScript indexes a string, so the
    -- offsets must count UTF-16 code units rather than bytes. Getting this
    -- wrong misplaces every highlight in any article containing so much as a
    -- curly quote ahead of it.
    it("counts offsets in UTF-16 code units, not bytes", function()
        -- "Café" is 5 bytes but 4 code units, so a byte offset would be one too
        -- many from here on.
        local accented = "Caf\195\169 is a word. The quick brown fox jumps."
        local first, last = ArticleUtil.findTextOffsets(accented, "The quick brown fox")
        assertEqual(first, 16)
        assertEqual(last, 35)
    end)

    it("counts an astral character as a surrogate pair", function()
        -- U+1F600, four bytes, two UTF-16 code units.
        local emoji = "\240\159\152\128 and then the passage"
        local first = ArticleUtil.findTextOffsets(emoji, "the passage")
        assertEqual(first, 12)
    end)

    it("measures the passage itself in code units too", function()
        local text_with_dash = "before \226\128\148 after the mark"
        local first, last = ArticleUtil.findTextOffsets(text_with_dash, "\226\128\148 after")
        assertEqual(first, 7)
        assertEqual(last, 14) -- em-dash (1) + " after" (6)
    end)

    it("keeps the probe fallback on character boundaries", function()
        -- Chosen so both cuts land inside a multi-byte sequence: the leading
        -- one on a continuation byte, the trailing one on a lead byte whose
        -- sequence is left incomplete. Cutting there anyway still matches
        -- byte-wise, but reports offsets pointing into half a character.
        local dash = "\226\128\148" -- em-dash: 3 bytes, 1 code unit
        local prose = dash:rep(4) .. " a passage that is quite long indeed and carries on " .. dash:rep(4)
        local needle = "ZZ" .. prose .. "ZZ"

        local first, last = ArticleUtil.findTextOffsets(prose, needle)
        assertEqual(first, 3)  -- snapped forward off the 3rd dash's last byte
        assertEqual(last, 57)  -- snapped back off the trailing dash it bisected
    end)

    it("returns nil for a multi-byte passage that is simply absent", function()
        assertNil(ArticleUtil.findTextOffsets(text, string.rep("\195\169", 21)))
    end)
end)

describe("utf16Length", function()
    it("counts ASCII one for one", function()
        assertEqual(ArticleUtil.utf16Length("plain text"), 10)
        assertEqual(ArticleUtil.utf16Length(""), 0)
    end)

    it("counts a two-byte sequence as one unit", function()
        assertEqual(ArticleUtil.utf16Length("\195\169"), 1)       -- é
        assertEqual(ArticleUtil.utf16Length("\194\1831"), 2)      -- Ã + "1"
    end)

    it("counts a three-byte sequence as one unit", function()
        assertEqual(ArticleUtil.utf16Length("\226\128\148"), 1)   -- em-dash
        assertEqual(ArticleUtil.utf16Length("\230\188\162"), 1)   -- 漢
    end)

    it("counts an astral character as two units", function()
        assertEqual(ArticleUtil.utf16Length("\240\159\152\128"), 2)
    end)

    it("stays monotonic on invalid input", function()
        assertEqual(ArticleUtil.utf16Length("\169\169"), 2) -- stray continuation bytes
        assertEqual(ArticleUtil.utf16Length(nil), 0)
    end)
end)

describe("imageSourceFrom", function()
    it("prefers a lazy-loading attribute over a placeholder src", function()
        assertEqual(ArticleUtil.imageSourceFrom(
            ' src="https://e.com/1x1.gif" data-src="https://e.com/real.jpg"'),
            "https://e.com/real.jpg")
    end)

    it("recognises the other common lazy attributes", function()
        for _, name in ipairs({ "data-original", "data-lazy-src", "data-actualsrc" }) do
            assertEqual(ArticleUtil.imageSourceFrom(
                string.format(' %s="https://e.com/r.jpg" src="https://e.com/p.gif"', name)),
                "https://e.com/r.jpg", name)
        end
    end)

    it("falls back to srcset when there is no data- attribute", function()
        assertEqual(ArticleUtil.imageSourceFrom(
            ' srcset="https://e.com/a.jpg 480w, https://e.com/b.jpg 1200w"'),
            "https://e.com/b.jpg")
    end)

    it("uses plain src when that is all there is", function()
        assertEqual(ArticleUtil.imageSourceFrom(' src="https://e.com/a.jpg"'),
            "https://e.com/a.jpg")
    end)

    it("rejects a data: URI or an obvious placeholder", function()
        assertNil(ArticleUtil.imageSourceFrom(' src="data:image/gif;base64,R0lG"'))
        assertNil(ArticleUtil.imageSourceFrom(' src="https://e.com/placeholder.png"'))
        assertNil(ArticleUtil.imageSourceFrom(' src="https://e.com/blank.gif"'))
    end)

    it("decodes entities in the URL", function()
        assertEqual(ArticleUtil.imageSourceFrom(' data-src="https://e.com/a.jpg?w=1&amp;h=2"'),
            "https://e.com/a.jpg?w=1&h=2")
    end)

    it("is case-insensitive about attribute names", function()
        assertEqual(ArticleUtil.imageSourceFrom(' DATA-SRC="https://e.com/a.jpg"'),
            "https://e.com/a.jpg")
    end)

    it("returns nil for an img with nothing usable", function()
        assertNil(ArticleUtil.imageSourceFrom(' alt="x"'))
        assertNil(ArticleUtil.imageSourceFrom(nil))
    end)
end)

describe("pickFromSrcset", function()
    it("takes the widest candidate that suits an e-reader", function()
        assertEqual(ArticleUtil.pickFromSrcset("a.jpg 400w, b.jpg 1200w, c.jpg 3000w"), "b.jpg")
    end)

    it("falls back to the narrowest when all are oversized", function()
        assertEqual(ArticleUtil.pickFromSrcset("a.jpg 2400w, b.jpg 4000w"), "a.jpg")
    end)

    it("handles a single candidate with no descriptor", function()
        assertEqual(ArticleUtil.pickFromSrcset("only.jpg"), "only.jpg")
    end)

    it("copes with untidy whitespace", function()
        assertEqual(ArticleUtil.pickFromSrcset("  a.jpg   400w ,  b.jpg  900w  "), "b.jpg")
    end)

    it("returns nil for nothing", function()
        assertNil(ArticleUtil.pickFromSrcset(""))
        assertNil(ArticleUtil.pickFromSrcset(nil))
    end)
end)

describe("collectImages", function()
    it("rewrites sources and collects them in order", function()
        local html = '<p><img src="https://e.com/a.png"/>x<img src="https://e.com/b.jpg"/></p>'
        local out, images = ArticleUtil.collectImages(html)

        assertEqual(#images, 2)
        assertEqual(images[1].src, "https://e.com/a.png")
        assertEqual(images[1].path, "images/img1.png")
        assertEqual(images[2].path, "images/img2.jpg")
        assertMatch(out, 'src="images/img1.png"')
        assertNoMatch(out, "e.com")
    end)

    it("reuses one entry for a repeated source", function()
        local html = '<img src="https://e.com/a.png"><img src="https://e.com/a.png">'
        local out, images = ArticleUtil.collectImages(html)
        assertEqual(#images, 1)
        local count = select(2, out:gsub('src="images/img1%.png"', ""))
        assertEqual(count, 2)
    end)

    it("picks up lazy-loaded images", function()
        local html = '<img src="https://e.com/1x1.gif" data-src="https://e.com/real.jpg">'
        local out, images = ArticleUtil.collectImages(html)
        assertEqual(#images, 1)
        assertEqual(images[1].src, "https://e.com/real.jpg")
        assertMatch(out, 'src="images/img1.jpg"')
    end)

    it("drops data URIs, relative paths and sourceless tags", function()
        local out, images = ArticleUtil.collectImages(
            '<img src="data:image/png;base64,AAAA"><img src="/rel.png"><img alt="x">')
        assertEqual(#images, 0)
        assertNoMatch(out, "<img")
    end)

    it("honours the cap and drops the overflow", function()
        local html = ""
        for i = 1, 10 do html = html .. string.format('<img src="https://e.com/%d.png">', i) end

        local out, images = ArticleUtil.collectImages(html, 3)
        assertEqual(#images, 3)
        assertEqual(select(2, out:gsub("<img", "")), 3)
    end)
end)

describe("imageExtension and mediaType", function()
    it("maps known extensions, ignoring query strings", function()
        assertEqual(ArticleUtil.imageExtension("https://e.com/a.PNG?w=100"), ".png")
        assertEqual(ArticleUtil.imageExtension("https://e.com/a.jpeg"), ".jpg")
    end)

    it("defaults to jpg for extensionless URLs", function()
        assertEqual(ArticleUtil.imageExtension("https://e.com/image"), ".jpg")
    end)

    it("maps paths to media types", function()
        assertEqual(ArticleUtil.mediaType("images/img1.png"), "image/png")
        assertEqual(ArticleUtil.mediaType("images/img1.gif"), "image/gif")
        assertEqual(ArticleUtil.mediaType("images/img1.unknown"), "image/jpeg")
    end)
end)

describe("sniffImageType", function()
    it("recognises formats by magic bytes", function()
        assertEqual(ArticleUtil.sniffImageType("\255\216\255" .. string.rep("\0", 20)), "image/jpeg")
        assertEqual(ArticleUtil.sniffImageType("\137PNG\r\n\26\n" .. string.rep("\0", 20)), "image/png")
        assertEqual(ArticleUtil.sniffImageType("GIF89a" .. string.rep("\0", 20)), "image/gif")
        assertEqual(ArticleUtil.sniffImageType("RIFF\0\0\0\0WEBP" .. string.rep("\0", 20)), "image/webp")
    end)

    it("returns nil for HTML served in place of an image", function()
        assertNil(ArticleUtil.sniffImageType("<!DOCTYPE html><html>404 not found</html>"))
        assertNil(ArticleUtil.sniffImageType("short"))
    end)
end)

describe("contentSources", function()
    local function link(fields)
        local content = { type = "link", url = "https://e.com/a" }
        for k, v in pairs(fields) do content[k] = v end
        return { id = "b1", content = content }
    end

    local function labels(sources)
        local out = {}
        for _, source in ipairs(sources) do table.insert(out, source.label) end
        return table.concat(out, " > ")
    end

    it("prefers inline readable HTML", function()
        local sources = ArticleUtil.contentSources(link{ htmlContent = "<p>x</p>" })
        assertEqual(sources[1].kind, "inline")
    end)

    it("falls back to the content asset", function()
        -- Karakeep normally expands this asset itself when asked with
        -- includeContent=true. It is reachable when that expansion failed:
        -- the list endpoint catches the error and returns a null htmlContent.
        local sources = ArticleUtil.contentSources(link{ contentAssetId = "a1" })
        assertEqual(sources[1].kind, "asset")
        assertEqual(sources[1].asset_id, "a1")
        assertTrue(not sources[1].full_page)
    end)

    it("puts extracted content ahead of archives by default", function()
        local sources = ArticleUtil.contentSources(link{
            contentAssetId = "a1",
            precrawledArchiveAssetId = "p1",
            fullPageArchiveAssetId = "f1",
        })
        assertEqual(labels(sources),
            "readable HTML asset > precrawled archive > full page archive > readable content endpoint")
    end)

    it("prefers the user's own capture over Karakeep's snapshot", function()
        local sources = ArticleUtil.contentSources(link{
            precrawledArchiveAssetId = "p1",
            fullPageArchiveAssetId = "f1",
        })
        assertEqual(sources[1].label, "precrawled archive")
        assertEqual(sources[2].label, "full page archive")
    end)

    it("flips the order when asked to prefer archives", function()
        local sources = ArticleUtil.contentSources(link{
            htmlContent = "<p>x</p>",
            precrawledArchiveAssetId = "p1",
        }, true)
        assertEqual(labels(sources),
            "precrawled archive > inline readable HTML > readable content endpoint")
    end)

    it("marks archives as whole pages", function()
        local sources = ArticleUtil.contentSources(link{ precrawledArchiveAssetId = "p1" })
        assertTrue(sources[1].full_page)
    end)

    it("always ends with the endpoint, so there is a last resort", function()
        local bare = ArticleUtil.contentSources(link{})
        assertEqual(#bare, 1)
        assertEqual(bare[1].kind, "endpoint")
    end)

    it("ignores empty strings, which are not usable content", function()
        local sources = ArticleUtil.contentSources(link{ htmlContent = "", contentAssetId = "" })
        assertEqual(#sources, 1)
        assertEqual(sources[1].kind, "endpoint")
    end)

    it("returns nothing for bookmarks that are not links", function()
        assertEqual(#ArticleUtil.contentSources{ content = { type = "text", text = "x" } }, 0)
        assertEqual(#ArticleUtil.contentSources{ content = { type = "asset" } }, 0)
        assertEqual(#ArticleUtil.contentSources{}, 0)
        assertEqual(#ArticleUtil.contentSources(nil), 0)
    end)
end)

describe("displayText", function()
    it("passes ordinary strings through", function()
        assertEqual(ArticleUtil.displayText("A Title"), "A Title")
    end)

    it("falls back for anything unusable", function()
        local function jsonNull() end
        assertEqual(ArticleUtil.displayText(jsonNull, "Untitled"), "Untitled")
        assertEqual(ArticleUtil.displayText(nil, "Untitled"), "Untitled")
        assertEqual(ArticleUtil.displayText("", "Untitled"), "Untitled")
        assertEqual(ArticleUtil.displayText({}, "Untitled"), "Untitled")
    end)

    it("renders numbers", function()
        assertEqual(ArticleUtil.displayText(42), "42")
    end)

    it("never returns a value string.format would reject", function()
        local function jsonNull() end
        for _, v in ipairs({ "ok", 1 }) do
            assertTrue(pcall(string.format, "%s", ArticleUtil.displayText(v)))
        end
        assertTrue(pcall(string.format, "%s", ArticleUtil.displayText(jsonNull)))
    end)
end)

describe("stripJsonNulls", function()
    -- KOReader decodes JSON null to a function, which is truthy. Stand-in here.
    local function jsonNull() end -- the value itself is the sentinel; never called

    it("removes a null field so `or` falls through", function()
        local bookmark = ArticleUtil.stripJsonNulls{ title = jsonNull, id = "a" }
        assertNil(bookmark.title)
        assertEqual(bookmark.title or "Untitled", "Untitled")
    end)

    it("reproduces the crash it exists to prevent", function()
        -- Before the fix, a null title survived the `or` chain and reached
        -- string formatting, which errors with "invalid replacement value".
        local raw = { title = jsonNull }
        assertTrue(raw.title, "a JSON null must be truthy for this test to mean anything")
        local ok = pcall(string.format, "%s", raw.title)
        assertTrue(not ok or type(raw.title) == "function")

        local cleaned = ArticleUtil.stripJsonNulls{ title = jsonNull }
        assertEqual(string.format("%s", cleaned.title or "Untitled"), "Untitled")
    end)

    it("recurses into nested objects", function()
        local bookmark = ArticleUtil.stripJsonNulls{
            id = "a",
            content = { type = "link", url = "https://e.com", author = jsonNull },
        }
        assertNil(bookmark.content.author)
        assertEqual(bookmark.content.url, "https://e.com")
    end)

    it("clears a null nextCursor so pagination terminates", function()
        -- Left in place, the sentinel is truthy, so the paging loop would keep
        -- going and send "function: 0x..." as the cursor.
        local page = ArticleUtil.stripJsonNulls{ bookmarks = {}, nextCursor = jsonNull }
        assertNil(page.nextCursor)
    end)

    it("recurses into arrays of objects", function()
        local page = ArticleUtil.stripJsonNulls{
            bookmarks = {
                { id = "a", title = jsonNull },
                { id = "b", title = "kept" },
            },
        }
        assertEqual(#page.bookmarks, 2)
        assertNil(page.bookmarks[1].title)
        assertEqual(page.bookmarks[2].title, "kept")
    end)

    it("drops nulls inside an array without truncating it", function()
        local out = ArticleUtil.stripJsonNulls{ list = { "a", jsonNull, "b" } }
        assertEqual(#out.list, 2)
        assertEqual(out.list[1], "a")
        assertEqual(out.list[2], "b")
    end)

    it("leaves ordinary values alone", function()
        local out = ArticleUtil.stripJsonNulls{
            s = "x", n = 1, t = true, f = false, empty = {},
        }
        assertEqual(out.s, "x")
        assertEqual(out.n, 1)
        assertEqual(out.t, true)
        assertEqual(out.f, false, "false must survive; it is not a null")
        assertEqual(type(out.empty), "table")
    end)

    it("tolerates scalars and deep nesting", function()
        assertEqual(ArticleUtil.stripJsonNulls("plain"), "plain")
        assertNil(ArticleUtil.stripJsonNulls(jsonNull))

        local deep, cursor = {}, nil
        cursor = deep
        for _ = 1, 40 do cursor.next = {}; cursor = cursor.next end
        assertTrue(ArticleUtil.stripJsonNulls(deep), "must not overflow the stack")
    end)
end)

describe("buildQuery", function()
    it("returns an empty string for no parameters", function()
        assertEqual(ArticleUtil.buildQuery({}), "")
        assertEqual(ArticleUtil.buildQuery(nil), "")
    end)

    it("sorts keys and renders booleans", function()
        assertEqual(ArticleUtil.buildQuery{ limit = 10, archived = false, includeContent = true },
            "?archived=false&includeContent=true&limit=10")
    end)

    it("percent-encodes values", function()
        assertEqual(ArticleUtil.buildQuery{ q = "a b&c" }, "?q=a%20b%26c")
    end)

    it("skips nil values", function()
        assertEqual(ArticleUtil.buildQuery{ cursor = nil, limit = 5 }, "?limit=5")
    end)

    -- Rather than "?cursor=table%3A%200x55f3…", which would go on the wire as a
    -- real value and fail in a thoroughly confusing way.
    it("drops values that cannot be encoded", function()
        assertEqual(ArticleUtil.buildQuery{ cursor = {}, limit = 5 }, "?limit=5")
        assertEqual(ArticleUtil.buildQuery{ cursor = print, limit = 5 }, "?limit=5")
    end)
end)

describe("normaliseServerUrl", function()
    it("strips trailing slashes", function()
        assertEqual(ArticleUtil.normaliseServerUrl("https://k.example.com/"), "https://k.example.com")
    end)

    it("strips a pasted /api/v1 suffix", function()
        assertEqual(ArticleUtil.normaliseServerUrl("https://k.example.com/api/v1"), "https://k.example.com")
        assertEqual(ArticleUtil.normaliseServerUrl("https://k.example.com/api/v1/"), "https://k.example.com")
    end)

    it("trims surrounding whitespace", function()
        assertEqual(ArticleUtil.normaliseServerUrl("  https://k.example.com  "), "https://k.example.com")
    end)

    it("leaves a port and a subpath alone", function()
        assertEqual(ArticleUtil.normaliseServerUrl("http://192.168.1.5:3000"), "http://192.168.1.5:3000")
        assertEqual(ArticleUtil.normaliseServerUrl("https://host/karakeep"), "https://host/karakeep")
    end)
end)


describe("originalExtension", function()
    it("recognises an uploaded PDF", function()
        assertEqual(ArticleUtil.originalExtension({ type = "asset", assetType = "pdf" }), ".pdf")
    end)

    it("uses the MIME type for an image, since \"image\" is not a format", function()
        assertEqual(ArticleUtil.originalExtension({
            type = "asset", assetType = "image", mimeType = "image/png",
        }), ".png")
    end)

    it("falls back to the file name", function()
        assertEqual(ArticleUtil.originalExtension({
            type = "asset", assetType = "image", fileName = "Scan.JPG",
        }), ".jpg")
    end)

    it("prefers the PDF asset type over a misleading MIME type", function()
        assertEqual(ArticleUtil.originalExtension({
            type = "asset", assetType = "pdf", mimeType = "application/octet-stream",
        }), ".pdf")
    end)

    it("refuses a format KOReader cannot open", function()
        assertNil(ArticleUtil.originalExtension({
            type = "asset", assetType = "archive", mimeType = "application/zip", fileName = "x.zip",
        }))
    end)

    it("refuses an image with nothing to identify it by", function()
        assertNil(ArticleUtil.originalExtension({ type = "asset", assetType = "image" }))
    end)

    it("tolerates a missing content table", function()
        assertNil(ArticleUtil.originalExtension(nil))
    end)
end)

describe("originalTitle", function()
    it("prefers the bookmark title", function()
        assertEqual(ArticleUtil.originalTitle{
            title = "Designing Data-Intensive Applications",
            content = { type = "asset", fileName = "book.pdf" },
        }, "Designing Data-Intensive Applications")
    end)

    it("uses the file name when there is no title", function()
        assertEqual(ArticleUtil.originalTitle{
            content = { type = "asset", fileName = "paper.pdf" },
        }, "paper")
    end)

    it("does not strip a suffix that is not a document extension", function()
        -- Stripping every ".xyz" would turn this into "Node".
        assertEqual(ArticleUtil.originalTitle{ title = "Node.js internals" }, "Node.js internals")
    end)

    it("never returns an empty title", function()
        assertEqual(ArticleUtil.originalTitle{ content = { type = "asset" } }, "Untitled")
        assertEqual(ArticleUtil.originalTitle{ title = "" }, "Untitled")
    end)
end)

describe("extensionForMediaType", function()
    it("picks the extension that matches the sniffed type", function()
        assertEqual(ArticleUtil.extensionForMediaType("image/png"), ".png")
        assertEqual(ArticleUtil.extensionForMediaType("image/webp"), ".webp")
        assertEqual(ArticleUtil.extensionForMediaType("image/jpeg"), ".jpg")
    end)

    it("defaults to .jpg when the type is unknown or absent", function()
        assertEqual(ArticleUtil.extensionForMediaType(nil), ".jpg")
        assertEqual(ArticleUtil.extensionForMediaType("application/pdf"), ".jpg")
    end)
end)

describe("coverSources", function()
    it("prefers the asset Karakeep serves over the page's own image", function()
        local sources = ArticleUtil.coverSources{
            imageAssetId = "asset-1",
            imageUrl = "https://example.com/a.jpg",
        }
        assertEqual(#sources, 2)
        assertEqual(sources[1].kind, "asset")
        assertEqual(sources[1].asset_id, "asset-1")
        assertEqual(sources[2].kind, "url")
    end)

    it("offers the URL alone when there is no asset", function()
        local sources = ArticleUtil.coverSources{ imageUrl = "https://example.com/a.jpg" }
        assertEqual(#sources, 1)
        assertEqual(sources[1].url, "https://example.com/a.jpg")
    end)

    it("offers nothing when there is no cover", function()
        assertEqual(#ArticleUtil.coverSources{}, 0)
        assertEqual(#ArticleUtil.coverSources(nil), 0)
    end)

    it("ignores sources it cannot fetch", function()
        -- A relative path has nothing to resolve against, and a data: URI would
        -- have to be base64 decoded before its bytes could even be sniffed.
        assertEqual(#ArticleUtil.coverSources{ imageUrl = "/a.jpg" }, 0)
        assertEqual(#ArticleUtil.coverSources{ imageUrl = "data:image/png;base64,AAAA" }, 0)
        assertEqual(#ArticleUtil.coverSources{ imageUrl = "" }, 0)
    end)
end)

describe("assignHeadingIds", function()
    it("numbers h2 and h3 in document order", function()
        local html, headings = ArticleUtil.assignHeadingIds(
            "<h2>One</h2><p>x</p><h3>Sub</h3><h2>Two</h2>")

        assertMatch(html, '<h2 id="kk-s1">One</h2>')
        assertMatch(html, '<h3 id="kk-s2">Sub</h3>')
        assertMatch(html, '<h2 id="kk-s3">Two</h2>')
        assertEqual(#headings, 3)
        assertEqual(headings[1].level, 2)
        assertEqual(headings[2].level, 3)
        assertEqual(headings[3].text, "Two")
    end)

    it("numbers the same way on a rebuild, so a re-download stays stable", function()
        local input = "<h2>A</h2><h2>B</h2>"
        local _, first = ArticleUtil.assignHeadingIds(input)
        local _, second = ArticleUtil.assignHeadingIds(input)
        assertEqual(first[2].id, second[2].id)
    end)

    it("keeps an id the page already had", function()
        local html, headings = ArticleUtil.assignHeadingIds('<h2 id="intro">Intro</h2>')
        assertMatch(html, '<h2 id="intro">Intro</h2>')
        assertEqual(headings[1].id, "intro")
    end)

    it("takes the label from the text, not the markup", function()
        local _, headings = ArticleUtil.assignHeadingIds("<h2>Use <em>less</em> &amp; code</h2>")
        assertEqual(headings[1].text, "Use less & code")
    end)

    it("leaves headings it has no use for alone", function()
        local html, headings = ArticleUtil.assignHeadingIds("<h1>Title</h1><h4>Deep</h4>")
        assertEqual(html, "<h1>Title</h1><h4>Deep</h4>")
        assertEqual(#headings, 0)
    end)

    it("never produces an empty label", function()
        local _, headings = ArticleUtil.assignHeadingIds("<h2></h2>")
        assertEqual(headings[1].text, "…")
    end)

    it("tolerates non-string input", function()
        local html, headings = ArticleUtil.assignHeadingIds(nil)
        assertEqual(html, "")
        assertEqual(#headings, 0)
    end)
end)

describe("tocFromHeadings", function()
    it("nests an h3 under the h2 above it", function()
        local toc = ArticleUtil.tocFromHeadings({
            { level = 2, id = "a", text = "A" },
            { level = 3, id = "a1", text = "A1" },
            { level = 3, id = "a2", text = "A2" },
            { level = 2, id = "b", text = "B" },
        })
        assertEqual(#toc, 2)
        assertEqual(#toc[1].children, 2)
        assertEqual(toc[1].children[1].id, "a1")
        assertEqual(#toc[2].children, 0)
    end)

    it("keeps an h3 with no h2 before it, rather than dropping it", function()
        local toc = ArticleUtil.tocFromHeadings({
            { level = 3, id = "x", text = "X" },
        })
        assertEqual(#toc, 1)
        assertEqual(toc[1].id, "x")
    end)

    it("handles an article with no headings", function()
        assertEqual(#ArticleUtil.tocFromHeadings({}), 0)
        assertEqual(#ArticleUtil.tocFromHeadings(nil), 0)
    end)
end)

describe("language", function()
    it("uses the language the crawler recorded", function()
        assertEqual(ArticleUtil.language{ content = { language = "de" } }, "de")
    end)

    it("keeps a full tag, which crengine understands", function()
        assertEqual(ArticleUtil.language{ content = { language = "en-GB" } }, "en-GB")
    end)

    it("falls back to the bookmark's own field", function()
        assertEqual(ArticleUtil.language{ language = "fr", content = {} }, "fr")
    end)

    it("defaults to en, which is all Karakeep often has", function()
        assertEqual(ArticleUtil.language{ content = {} }, "en")
        assertEqual(ArticleUtil.language(nil), "en")
    end)

    it("ignores a value that is not shaped like a language tag", function()
        assertEqual(ArticleUtil.language{ content = { language = "not a tag" } }, "en")
        assertEqual(ArticleUtil.language{ content = { language = "" } }, "en")
        assertEqual(ArticleUtil.language{ content = { language = 42 } }, "en")
    end)
end)

describe("summaryKind", function()
    it("says the plugin is unconfigured before anything else", function()
        assertEqual(ArticleUtil.summaryKind{ configured = false, downloaded = 3 }, "not_configured")
    end)

    it("reports a download when something was downloaded", function()
        assertEqual(ArticleUtil.summaryKind{ downloaded = 2, skipped = 1 }, "downloaded")
    end)

    it("distinguishes a tidy-up from a download", function()
        assertEqual(ArticleUtil.summaryKind{ removed = 2, fetched = 5 }, "cleaned_up")
    end)

    it("says nothing was downloaded when everything failed", function()
        assertEqual(ArticleUtil.summaryKind{ failed = 3, fetched = 3 }, "failed")
    end)

    it("says everything is already here", function()
        assertEqual(ArticleUtil.summaryKind{ skipped = 4, fetched = 4 }, "all_present")
    end)

    it("separates an empty scope from an empty result", function()
        assertEqual(ArticleUtil.summaryKind{ fetched = 0 }, "nothing_unread")
        assertEqual(ArticleUtil.summaryKind{ fetched = 4 }, "nothing_new")
    end)

    it("tolerates a missing or empty table", function()
        assertEqual(ArticleUtil.summaryKind{ downloaded = 0 }, "nothing_unread")
        assertEqual(ArticleUtil.summaryKind(nil), "nothing_new")
    end)
end)

describe("failureKind", function()
    it("recognises a missing content failure however it is worded", function()
        assertEqual(ArticleUtil.failureKind("no_content"), "no_content")
        assertEqual(ArticleUtil.failureKind("no readable content"), "no_content")
    end)

    it("singles out a 403, which has an actual fix", function()
        assertEqual(ArticleUtil.failureKind("HTTP 403"), "http_403")
    end)

    it("recognises other HTTP statuses, wherever the code appears", function()
        assertEqual(ArticleUtil.failureKind("HTTP 500"), "http")
        assertEqual(ArticleUtil.failureKind("The file could not be fetched (HTTP 502)."), "http")
    end)

    it("groups the ways writing the EPUB can fail", function()
        assertEqual(ArticleUtil.failureKind("zip_open_failed"), "write")
        assertEqual(ArticleUtil.failureKind("could not write OEBPS/main.lua"), "write")
        assertEqual(ArticleUtil.failureKind("archive is only 12 bytes"), "write")
        assertEqual(ArticleUtil.failureKind("could not save the file"), "write")
        assertEqual(ArticleUtil.failureKind("io_error"), "write")
    end)

    it("recognises the transport and configuration failures", function()
        assertEqual(ArticleUtil.failureKind("network_error"), "network")
        assertEqual(ArticleUtil.failureKind("not_configured"), "not_configured")
        assertEqual(ArticleUtil.failureKind("unsupported file type"), "unsupported")
        assertEqual(ArticleUtil.failureKind("http_error"), "server")
    end)

    it("leaves an unrecognised reason to be shown as it is", function()
        assertEqual(ArticleUtil.failureKind("larger than the 80 MB limit"), "unknown")
        assertEqual(ArticleUtil.failureKind(nil), "unknown")
        assertEqual(ArticleUtil.failureKind(""), "unknown")
    end)
end)


describe("isTempName", function()
    it("rejects the half-written original that carries a bookmark ID", function()
        -- The bug this exists for: "X [kk-id_abc].pdf.part" is matched by
        -- getBookmarkId(), so a scan that trusted the marker would believe the
        -- PDF was already on the device and never fetch it again.
        assertTrue(ArticleUtil.isTempName("Title [kk-id_abc].pdf.part"))
        assertEqual(ArticleUtil.getBookmarkId("Title [kk-id_abc].pdf.part"), "abc")
    end)

    it("rejects our scratch files", function()
        assertTrue(ArticleUtil.isTempName(".karaoke-asset.tmp"))
    end)

    it("accepts a finished download and a sidecar", function()
        assertTrue(not ArticleUtil.isTempName("Title [kk-id_abc].pdf"))
        assertTrue(not ArticleUtil.isTempName("Title [kk-id_abc].epub"))
        assertTrue(not ArticleUtil.isTempName("Title [kk-id_abc].sdr"))
    end)

    it("tolerates empty and non-string input", function()
        assertTrue(not ArticleUtil.isTempName(nil))
        assertTrue(not ArticleUtil.isTempName(""))
    end)
end)

describe("samePath", function()
    it("ignores a trailing slash and case, as FAT does", function()
        assertTrue(ArticleUtil.samePath("/mnt/onboard/archive/", "/mnt/onboard/Archive"))
    end)

    it("does not confuse a subdirectory with its parent", function()
        assertTrue(not ArticleUtil.samePath("/mnt/onboard/karakeep", "/mnt/onboard/karakeep/archive"))
    end)

    it("never matches on nil or empty, so an unset archive folder matches nothing", function()
        assertTrue(not ArticleUtil.samePath("/mnt/onboard/x", nil))
        assertTrue(not ArticleUtil.samePath("", ""))
    end)
end)


-- Lists as folders. The names here are the real shape of the owner's Karakeep:
-- "Learning" with children, and a smart list alongside them.
local function tree(lists)
    return ArticleUtil.indexLists(lists)
end

describe("listChain", function()
    local lists = {
        { id = "a", name = "Learning", type = "manual" },
        { id = "b", name = "Rust", type = "manual", parentId = "a" },
        { id = "c", name = "Deep", type = "manual", parentId = "b" },
    }
    local by_id = tree(lists)

    it("walks parentId up to the root, root first", function()
        local chain = ArticleUtil.listChain(lists[3], by_id)
        assertEqual(#chain, 3)
        assertEqual(chain[1].name, "Learning")
        assertEqual(chain[3].name, "Deep")
    end)

    it("returns a single-element chain for a top-level list", function()
        assertEqual(#ArticleUtil.listChain(lists[1], by_id), 1)
    end)

    it("gives up on a cycle instead of looping for ever", function()
        local cyclic = tree({
            { id = "x", name = "X", parentId = "y" },
            { id = "y", name = "Y", parentId = "x" },
        })
        assertNil(ArticleUtil.listChain({ id = "x", name = "X", parentId = "y" }, cyclic))
    end)

    it("gives up when a parent is missing from the response", function()
        assertNil(ArticleUtil.listChain({ id = "z", name = "Z", parentId = "gone" }, by_id))
    end)
end)

describe("folderForChain", function()
    local function chain_of(...)
        local out = {}
        for _, name in ipairs({ ... }) do table.insert(out, { name = name }) end
        return out
    end

    it("keeps the nesting, sanitising each segment on its own", function()
        -- safeTitle() on the whole path would replace "/" and produce
        -- "Learning_Replication & consistency", destroying the nesting.
        assertEqual(ArticleUtil.folderForChain(chain_of("Learning", "Replication & consistency")),
            "Learning/Replication & consistency")
    end)

    it("replaces characters FAT cannot hold, per segment", function()
        assertEqual(ArticleUtil.folderForChain(chain_of("A/B", 'C:D*?')), "A_B/C_D__")
    end)

    it("drops empty segments and dot-dot", function()
        assertEqual(ArticleUtil.folderForChain(chain_of("Learning", "", "  ", "..", "Rust")),
            "Learning/Rust")
    end)

    it("strips a trailing dot, which FAT cannot represent", function()
        assertEqual(ArticleUtil.folderForChain(chain_of("Rust...")), "Rust")
    end)

    it("returns nil when nothing usable is left", function()
        assertNil(ArticleUtil.folderForChain(chain_of("", "  ")))
        assertNil(ArticleUtil.folderForChain(nil))
    end)
end)

describe("chooseList", function()
    local lists = {
        { id = "m-root", name = "Learning", type = "manual" },
        { id = "m-deep", name = "Rust", type = "manual", parentId = "m-root" },
        { id = "s-root", name = "Morning briefs", type = "smart" },
    }
    local by_id = tree(lists)

    it("prefers a manual list over a smart one, however deep", function()
        local list = ArticleUtil.chooseList({ "s-root", "m-root" }, by_id)
        assertEqual(list.id, "m-root")
    end)

    it("prefers the deepest manual list", function()
        local list = ArticleUtil.chooseList({ "m-root", "m-deep" }, by_id)
        assertEqual(list.id, "m-deep")
    end)

    it("breaks a tie by name, then id, so the answer cannot flip between syncs", function()
        local ties = tree({
            { id = "2", name = "Beta", type = "manual" },
            { id = "1", name = "Alpha", type = "manual" },
        })
        assertEqual(ArticleUtil.chooseList({ "2", "1" }, ties).id, "1")
        assertEqual(ArticleUtil.chooseList({ "1", "2" }, ties).id, "1")
    end)

    it("ignores lists that are not in the tree", function()
        assertNil(ArticleUtil.chooseList({ "nope" }, by_id))
    end)
end)

describe("dateSegment", function()
    it("reads the day out of createdAt", function()
        assertEqual(ArticleUtil.dateSegment({ createdAt = "2026-11-23T08:15:00.000Z" }), "2026-11-23")
    end)

    it("falls back to firstCreatedAt, then gives up", function()
        assertEqual(ArticleUtil.dateSegment({ firstCreatedAt = "2025-01-02T00:00:00Z" }), "2025-01-02")
        assertNil(ArticleUtil.dateSegment({ createdAt = "not a date" }))
        assertNil(ArticleUtil.dateSegment({}))
    end)
end)

describe("wantsDateFolder", function()
    local list = { name = "Morning briefs" }

    it("is off for an empty or 'none' setting", function()
        assertTrue(not ArticleUtil.wantsDateFolder("", list))
        assertTrue(not ArticleUtil.wantsDateFolder("none", list))
        assertTrue(not ArticleUtil.wantsDateFolder(nil, list))
    end)

    it("covers everything for 'all'", function()
        assertTrue(ArticleUtil.wantsDateFolder("all", list))
        assertTrue(ArticleUtil.wantsDateFolder("all", nil))
    end)

    it("matches named lists case-insensitively, ignoring spaces", function()
        assertTrue(ArticleUtil.wantsDateFolder(" Morning briefs , Daily", list))
        assertTrue(not ArticleUtil.wantsDateFolder("Daily", list))
    end)
end)


describe("isUnder", function()
    it("matches a file inside the folder", function()
        assertTrue(ArticleUtil.isUnder("/mnt/onboard/karakeep/archive/Title [kk-id_a].pdf",
            "/mnt/onboard/karakeep/archive"))
    end)

    it("does not match the folder itself", function()
        assertTrue(not ArticleUtil.isUnder("/mnt/onboard/karakeep/archive", "/mnt/onboard/karakeep/archive"))
    end)

    it("does not match a sibling whose name merely starts the same", function()
        -- "archive-old" is not inside "archive"; a prefix test without the
        -- separator would say it was.
        assertTrue(not ArticleUtil.isUnder("/mnt/onboard/karakeep/archive-old/x.pdf",
            "/mnt/onboard/karakeep/archive"))
    end)

    it("ignores a trailing slash and case, as FAT does", function()
        assertTrue(ArticleUtil.isUnder("/mnt/onboard/Karakeep/ARCHIVE/x.pdf",
            "/mnt/onboard/karakeep/archive/"))
    end)

    it("never matches on nil or an empty folder", function()
        assertTrue(not ArticleUtil.isUnder(nil, "/x"))
        assertTrue(not ArticleUtil.isUnder("/x/y", ""))
        assertTrue(not ArticleUtil.isUnder("/x/y", nil))
    end)
end)

return Runner
