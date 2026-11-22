--[[--
Specs for the parts of epubbuilder.lua that do not touch the device.

The module pulls in KOReader's networking and logging at load time, so those are
stubbed here. `build()` itself needs crengine and libarchive and is therefore
only exercisable on a real KOReader install — see TESTING.md.
]]

local Runner = require("spec.runner")

local describe, it = Runner.describe, Runner.it
local assertEqual, assertTrue = Runner.assertEqual, Runner.assertTrue
local assertMatch, assertNoMatch = Runner.assertMatch, Runner.assertNoMatch

-- Stand-ins for the KOReader modules epubbuilder.lua requires at load time.
package.preload["logger"] = function()
    return setmetatable({}, { __index = function() return function() end end })
end
package.preload["socket"] = function() return { skip = function() end } end
package.preload["socketutil"] = function()
    return { set_timeout = function() end, reset_timeout = function() end }
end
package.preload["socket.http"] = function() return { request = function() end } end

local ArticleUtil = require("articleutil")
local EpubBuilder = require("epubbuilder")

describe("markdownToHtml", function()
    it("converts headings at the right level", function()
        assertEqual(EpubBuilder.markdownToHtml("# Title"), "<h1>Title</h1>")
        assertEqual(EpubBuilder.markdownToHtml("### Sub"), "<h3>Sub</h3>")
    end)

    it("wraps prose in paragraphs", function()
        assertEqual(EpubBuilder.markdownToHtml("Hello there"), "<p>Hello there</p>")
    end)

    it("groups consecutive bullets into one list", function()
        local out = EpubBuilder.markdownToHtml("* one\n* two")
        assertEqual(out, "<ul>\n<li>one</li>\n<li>two</li>\n</ul>")
    end)

    it("closes a list before following prose", function()
        local out = EpubBuilder.markdownToHtml("* one\n\nafter")
        assertMatch(out, "</ul>")
        assertMatch(out, "<p>after</p>")
        assertTrue(out:find("</ul>") < out:find("<p>after"), "list must close before the paragraph")
    end)

    it("renders inline emphasis, code and links", function()
        assertMatch(EpubBuilder.markdownToHtml("a **bold** b"), "<strong>bold</strong>")
        assertMatch(EpubBuilder.markdownToHtml("a *it* b"), "<em>it</em>")
        assertMatch(EpubBuilder.markdownToHtml("a `x` b"), "<code>x</code>")
        assertMatch(EpubBuilder.markdownToHtml("[label](https://e.com)"),
            '<a href="https://e.com">label</a>')
    end)

    it("distinguishes images from links", function()
        local out = EpubBuilder.markdownToHtml("![alt](https://e.com/a.png)")
        assertMatch(out, '<img src="https://e.com/a.png" alt="alt"/>')
        assertNoMatch(out, "<a href")
    end)

    it("escapes HTML in the source", function()
        assertMatch(EpubBuilder.markdownToHtml("a <script> b"), "&lt;script&gt;")
    end)

    it("passes fenced code through verbatim and closes the block", function()
        local out = EpubBuilder.markdownToHtml("```\n# not a heading\n```")
        assertMatch(out, "<pre>")
        assertMatch(out, "# not a heading")
        assertMatch(out, "</pre>")
        assertNoMatch(out, "<h1>")
    end)

    it("closes an unterminated code fence", function()
        local out = EpubBuilder.markdownToHtml("```\nx")
        assertMatch(out, "</pre>")
    end)

    it("handles block quotes and rules", function()
        assertEqual(EpubBuilder.markdownToHtml("> quoted"), "<blockquote>quoted</blockquote>")
        assertEqual(EpubBuilder.markdownToHtml("---"), "<hr/>")
    end)

    it("tolerates empty and non-string input", function()
        assertEqual(EpubBuilder.markdownToHtml(""), "")
        assertEqual(EpubBuilder.markdownToHtml(nil), "")
    end)
end)

describe("buildDocument", function()
    local bookmark = {
        id = "abc123",
        title = "A Piece About Kobos",
        note = "read this on the train",
        content = {
            type = "link",
            url = "https://example.com/kobo",
            author = "A. Writer",
            publisher = "Example Press",
            datePublished = "2026-01-15T09:00:00.000Z",
        },
    }

    it("puts the title in an h1", function()
        local out = EpubBuilder.buildDocument(bookmark, "<p>body</p>")
        assertMatch(out, "<h1>A Piece About Kobos</h1>")
    end)

    it("includes author, publisher and a date trimmed to the day", function()
        local out = EpubBuilder.buildDocument(bookmark, "<p>body</p>")
        assertMatch(out, "A. Writer")
        assertMatch(out, "Example Press")
        assertMatch(out, "2026-01-15")
        assertNoMatch(out, "09:00:00")
    end)

    it("carries the source link and the Karakeep note", function()
        local out = EpubBuilder.buildDocument(bookmark, "<p>body</p>")
        assertMatch(out, 'href="https://example.com/kobo"')
        assertMatch(out, "read this on the train")
    end)

    it("appends the body", function()
        assertMatch(EpubBuilder.buildDocument(bookmark, "<p>body</p>"), "<p>body</p>")
    end)

    it("escapes metadata rather than trusting it", function()
        local hostile = {
            id = "x",
            title = 'Title <script>alert("x")</script>',
            content = { type = "link", url = 'https://e.com/"onload="evil' },
        }
        local out = EpubBuilder.buildDocument(hostile, "<p>body</p>")
        assertNoMatch(out, "<script>")
        assertMatch(out, "&lt;script&gt;")
        assertNoMatch(out, '"onload="')
    end)

    it("falls back to a placeholder when there is no body", function()
        assertMatch(EpubBuilder.buildDocument(bookmark, nil), "No readable content")
    end)

    it("falls back to the URL when there is no title", function()
        local untitled = { id = "x", content = { type = "link", url = "https://e.com/a" } }
        assertMatch(EpubBuilder.buildDocument(untitled, "<p>b</p>"), "<h1>https://e.com/a</h1>")
    end)

    it("omits optional metadata that is absent", function()
        local bare = { id = "x", content = { type = "link", url = "https://e.com/a" } }
        local out = EpubBuilder.buildDocument(bare, "<p>b</p>")
        assertNoMatch(out, "kk-note")
    end)
end)

describe("opf", function()
    local bookmark = {
        id = "abc123",
        title = "A Piece About Kobos",
        content = { type = "link", url = "https://example.com/kobo" },
    }
    local cover = { path = "images/cover.png", media_type = "image/png" }

    it("stays an EPUB 2 package, because crengine reads EPUB 2", function()
        assertMatch(EpubBuilder.opf(bookmark, "T", {}, nil), 'version="2.0"')
        assertNoMatch(EpubBuilder.opf(bookmark, "T", {}, cover), "properties=")
    end)

    it("declares no cover when there is not one", function()
        local out = EpubBuilder.opf(bookmark, "T", {}, nil)
        assertNoMatch(out, 'name="cover"')
        assertNoMatch(out, "cover.xhtml")
        assertMatch(out, [[<itemref idref="content"/>]])
    end)

    it("declares the cover the EPUB 2 way: meta plus manifest item", function()
        local out = EpubBuilder.opf(bookmark, "T", {}, cover)
        assertMatch(out, [[<meta name="cover" content="cover-img"/>]])
        assertMatch(out, [[<item id="cover-img" href="images/cover.png" media-type="image/png"/>]])
        assertMatch(out, [[<item id="cover-page" href="cover.xhtml" media-type="application/xhtml+xml"/>]])
    end)

    it("puts the cover first in the spine, so opening shows the art", function()
        local out = EpubBuilder.opf(bookmark, "T", {}, cover)
        local cover_at = out:find([[<itemref idref="cover-page" linear="yes"/>]], 1, true)
        local content_at = out:find([[<itemref idref="content"/>]], 1, true)
        assertTrue(cover_at ~= nil, "the cover must be in the spine")
        assertTrue(cover_at < content_at, "the cover must precede the text")
    end)

    it("points the guide at the text, so reading can skip the cover", function()
        local out = EpubBuilder.opf(bookmark, "T", {}, cover)
        assertMatch(out, [[<reference type="cover" title="Cover" href="cover.xhtml"/>]])
        assertMatch(out, [[<reference type="text" title="T" href="content.xhtml"/>]])
    end)

    it("writes the bookmark's language, defaulting to en", function()
        assertMatch(EpubBuilder.opf(bookmark, "T", {}, nil), "<dc:language>en</dc:language>")
        local german = { id = "x", content = { type = "link", language = "de" } }
        assertMatch(EpubBuilder.opf(german, "T", {}, nil), "<dc:language>de</dc:language>")
    end)

    it("escapes the title in the guide's title attribute", function()
        local out = EpubBuilder.opf(bookmark, 'T <script>', {}, nil)
        assertNoMatch(out, "<script>")
        assertMatch(out, "&lt;script&gt;")
    end)
end)

describe("ncx", function()
    local bookmark = { id = "abc123" }

    it("always has the article itself as its first entry", function()
        local out = EpubBuilder.ncx(bookmark, "Title", {})
        assertMatch(out, [[<navPoint id="navpoint-1" playOrder="1">]])
        assertMatch(out, "<text>Title</text>")
        assertMatch(out, [[<content src="content.xhtml"/>]])
    end)

    it("emits a navPoint per heading, pointing into the document", function()
        local toc = ArticleUtil.tocFromHeadings({
            { level = 2, id = "kk-s1", text = "First" },
            { level = 2, id = "kk-s2", text = "Second" },
        })
        local out = EpubBuilder.ncx(bookmark, "Title", toc)
        assertMatch(out, [[<content src="content.xhtml#kk-s1"/>]])
        assertMatch(out, [[<content src="content.xhtml#kk-s2"/>]])
        assertMatch(out, "<text>First</text>")
    end)

    it("nests an h3 inside its h2 in the XML too", function()
        local toc = ArticleUtil.tocFromHeadings({
            { level = 2, id = "kk-s1", text = "First" },
            { level = 3, id = "kk-s2", text = "Detail" },
        })
        local out = EpubBuilder.ncx(bookmark, "Title", toc)
        local outer = out:find([[<content src="content.xhtml#kk-s1"/>]], 1, true)
        local inner = out:find([[<content src="content.xhtml#kk-s2"/>]], 1, true)
        local closes = out:find("</navPoint>", outer, true)
        assertTrue(inner > outer and inner < closes, "the child must sit inside the parent navPoint")
    end)

    it("increases playOrder through nested entries", function()
        local toc = ArticleUtil.tocFromHeadings({
            { level = 2, id = "a", text = "A" },
            { level = 3, id = "b", text = "B" },
        })
        local out = EpubBuilder.ncx(bookmark, "Title", toc)
        -- Title is 1, the h2 is 2, its nested h3 is 3.
        assertMatch(out, 'id="navpoint-2" playOrder="2"')
        assertMatch(out, 'id="navpoint-3" playOrder="3"')
    end)

    it("escapes heading text rather than letting it break the XML", function()
        local toc = { { id = "kk-s1", text = "a < b & c", children = {} } }
        local out = EpubBuilder.ncx(bookmark, "Title", toc)
        assertNoMatch(out, "a < b")
        assertMatch(out, "a &lt; b &amp; c")
    end)
end)

describe("coverXhtml", function()
    it("is a document with the cover image in it", function()
        local out = EpubBuilder.coverXhtml("images/cover.png")
        assertMatch(out, [[<img src="images/cover.png" alt="Cover"/>]])
        assertMatch(out, [[<html xmlns="http://www.w3.org/1999/xhtml">]])
        assertNoMatch(out, "<svg")
    end)

    it("declares XML, so it is a document rather than a fragment", function()
        assertMatch(EpubBuilder.coverXhtml("images/cover.png"), [[<?xml version="1.0" encoding="UTF-8"?>]])
    end)
end)

return Runner
