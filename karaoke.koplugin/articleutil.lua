--[[--
Pure helpers for the Karakeep plugin.

This module deliberately has no KOReader dependencies so that it can be
exercised by the specs in `spec/` with a plain Lua 5.1 interpreter.

@module koplugin.karaoke.articleutil
]]

local ArticleUtil = {}

-- Downloaded articles carry the Karakeep bookmark ID in their filename, so that
-- it survives a round trip through the filesystem with nothing to keep in sync.
--
-- The marker goes at the *end*, as "<title> [kk-id_<bookmarkId>].epub". It used
-- to lead, the way wallabag.koplugin's "[w-id_123] " does, but a file browser
-- shows the start of a name and truncates the end, so a leading marker put an
-- opaque ID where the title should be and pushed every title out of sight. It
-- also made the folder sort by ID rather than by title.
--
-- Names written by earlier versions still lead with it. Since the marker is
-- looked for anywhere in the name, both forms read back the same and no
-- existing download is orphaned or fetched again.
--
-- The marker is a filename wire format and deliberately does not follow the
-- plugin's name: "kk" is Karakeep's, and the value is baked into the name of
-- every article already sitting on a device. Changing it to match a rename
-- would orphan all of them -- the plugin would stop recognising its own
-- downloads, fetch everything again, and never archive the bookmarks behind
-- the copies it had just abandoned.
ArticleUtil.ID_OPEN = "[kk-id_"
ArticleUtil.ID_CLOSE = "]"

--- Extract the Karakeep bookmark ID from a filename or path.
--
-- Reads both the current trailing marker and the leading one earlier versions
-- wrote. safeTitle() turns any bracket in a title into a round one, so a
-- "[kk-id_" in a name is always ours.
--
-- @tparam string path Filename or full path of a downloaded article.
-- @treturn string|nil The bookmark ID, or nil if this is not one of our files.
function ArticleUtil.getBookmarkId(path)
    if type(path) ~= "string" then return nil end

    local name = path:match("([^/]+)$") or path

    -- Plain finds throughout: the marker contains "[" and "]", which would
    -- otherwise need escaping as a pattern.
    local open_at = name:find(ArticleUtil.ID_OPEN, 1, true)
    if not open_at then return nil end

    local from = open_at + #ArticleUtil.ID_OPEN
    local close_at = name:find(ArticleUtil.ID_CLOSE, from, true)
    if not close_at then return nil end

    local id = name:sub(from, close_at - 1)
    if id == "" then return nil end

    -- Karakeep IDs are opaque, but they are always URL-safe, so anything with a
    -- path separator or a bracket in it is a false positive.
    if id:find("[/%[%]]") then return nil end

    return id
end

--- Whether a name uses the leading marker earlier versions wrote.
-- @tparam string path
-- @treturn bool
function ArticleUtil.hasLegacyName(path)
    if type(path) ~= "string" then return false end
    local name = path:match("([^/]+)$") or path
    return name:sub(1, #ArticleUtil.ID_OPEN) == ArticleUtil.ID_OPEN
end

--- Drop a trailing incomplete UTF-8 sequence left behind by a byte-wise truncation.
-- @tparam string s
-- @treturn string
function ArticleUtil.trimPartialUtf8(s)
    local i = #s
    -- A sequence is at most 4 bytes, so we never need to walk back further.
    local limit = math.max(1, #s - 3)

    while i >= limit do
        local b = s:byte(i)
        if b < 0x80 then
            return s -- plain ASCII, nothing dangling
        elseif b >= 0xC0 then
            local need
            if b >= 0xF0 then need = 4
            elseif b >= 0xE0 then need = 3
            else need = 2 end

            if #s - i + 1 >= need then
                return s -- the sequence starting here is complete
            end
            return s:sub(1, i - 1)
        end
        i = i - 1 -- continuation byte, keep walking back to the start byte
    end

    return s
end

--- Whether a path sits inside a directory.
--
-- Used to leave alone anything already in the archive folder: it was put there
-- on purpose, and a folder layout has nothing to say about it.
--
-- @tparam string|nil path
-- @tparam string|nil dir
-- @treturn bool
function ArticleUtil.isUnder(path, dir)
    if type(path) ~= "string" or type(dir) ~= "string" or dir == "" then return false end

    local function normalise(p)
        return (p:gsub("/+$", "")):lower()
    end

    local inner, outer = normalise(path), normalise(dir)
    return inner:sub(1, #outer + 1) == outer .. "/"
end

--- Whether a filename is one of ours that has *not* finished downloading.
--
-- A `Title [kk-id_x].pdf.part` left behind by an interrupted sync still carries
-- the bookmark ID, so a scan that trusted the marker would decide the PDF was
-- already on the device and never fetch it again -- forever. Temp names are
-- therefore never counted as downloads, and are cleaned up when a sync starts.
--
-- @tparam string name Filename or path.
-- @treturn bool
function ArticleUtil.isTempName(name)
    if type(name) ~= "string" or name == "" then return false end
    local lower = name:lower()
    -- .part is ours (see downloadOriginal); the leading dot covers the scratch
    -- files we write into the download folder, e.g. .karaoke-asset.tmp.
    return lower:match("%.part$") ~= nil or lower:match("^%.") ~= nil
end

--- Whether two paths name the same directory, ignoring case and trailing slashes.
--
-- Used to recognise the archive folder when it sits inside the download folder,
-- and so to keep it out of the scan: a file that has been archived has already
-- been dealt with, and re-reading it would archive it again on every sync. FAT
-- is case-insensitive, so the comparison is too.
--
-- @tparam string|nil a
-- @tparam string|nil b
-- @treturn bool
function ArticleUtil.samePath(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end

    local function normalise(path)
        path = path:gsub("/+$", "")
        if path == "" then path = "/" end
        return path:lower()
    end

    return a ~= "" and b ~= "" and normalise(a) == normalise(b)
end

--- Index a `GET /lists` response by id.
--
-- @tparam table|nil lists Array of Karakeep lists.
-- @treturn table Map of id to list.
function ArticleUtil.indexLists(lists)
    local by_id = {}
    for _, list in ipairs(lists or {}) do
        if type(list) == "table" and list.id then by_id[list.id] = list end
    end
    return by_id
end

--- Walk a list's parentId chain up to the top.
--
-- @tparam table list A list from `GET /lists`.
-- @tparam table by_id Map of id to list.
-- @treturn table|nil Array of lists, root first, ending with `list`. nil when the
--   chain is broken (a parent that is not in the response) or contains a cycle.
function ArticleUtil.listChain(list, by_id)
    if type(list) ~= "table" or type(by_id) ~= "table" then return nil end

    local chain, seen, current = {}, {}, list

    while current do
        if seen[current.id] then return nil end -- cycle: never loop forever
        seen[current.id] = true
        table.insert(chain, 1, current)

        local parent_id = current.parentId
        if not parent_id then break end

        current = by_id[parent_id]
        -- A parent the response does not include (deleted, or outside the
        -- caller's access) leaves the path unknowable, so the bookmark stays in
        -- the root rather than landing in a folder that is only half its name.
        if not current then return nil end
    end

    return chain
end

--- Turn a list chain into a relative folder path.
--
-- Each segment goes through safeTitle() on its own: passing "Learning/Replication"
-- through safeTitle() as a whole would replace the slash and collapse the
-- nesting into one folder called "Learning_Replication".
--
-- Segments that clean down to nothing, or to "."/"..", are dropped rather than
-- written: on FAT they are either meaningless or actively dangerous.
--
-- @tparam table chain Array of lists, root first.
-- @treturn string|nil Relative path with "/" separators, or nil when nothing is left.
function ArticleUtil.folderForChain(chain)
    if type(chain) ~= "table" then return nil end

    local segments = {}
    for _, list in ipairs(chain) do
        -- Only a list with no usable name at all is skipped; safeTitle() turns an
        -- empty name into "Untitled", which is not a name anyone chose.
        local raw = list.name or ""
        -- Rejected before safeTitle(), not after: safeTitle("..") trims the
        -- trailing dots down to nothing and then answers "Untitled", which would
        -- have created a folder by that name for a list called "..".
        if raw:match("%S") and not raw:match("^[%.%s]*$") then
            local cleaned = ArticleUtil.safeTitle(raw, 60)
            cleaned = cleaned:gsub("%.+$", ""):gsub("^%s+", "") -- FAT: no trailing dot

            if cleaned ~= "" and cleaned ~= "." and cleaned ~= ".." then
                table.insert(segments, cleaned)
            end
        end
    end

    if #segments == 0 then return nil end
    return table.concat(segments, "/")
end

--- Decide which list a bookmark belongs to, out of the ones it is in.
--
-- Manual lists beat smart ones first, deliberately: a smart list's membership is
-- computed from a query, so letting it win would re-file a bookmark the user had
-- put somewhere by hand. Within a class the deepest wins (so "Learning/Rust"
-- beats "Learning"), then the alphabetically first name, then the id -- a fixed
-- order, because two syncs that disagreed would move the file back and forth.
--
-- @tparam table list_ids Array of list ids the bookmark is in.
-- @tparam table by_id Map of id to list.
-- @treturn table|nil The chosen list.
-- @treturn table|nil Its chain.
function ArticleUtil.chooseList(list_ids, by_id)
    local best_list, best_chain, best_rank

    for _, id in ipairs(list_ids or {}) do
        local list = by_id[id]
        local chain = list and ArticleUtil.listChain(list, by_id)

        if list and chain then
            local rank = {
                list.type == "smart" and 1 or 0, -- manual first
                -#chain,                          -- deeper first
                (list.name or ""):lower(),
                tostring(list.id),
            }

            local better = best_rank == nil
            if not better then
                for i = 1, 4 do
                    if rank[i] ~= best_rank[i] then
                        better = rank[i] < best_rank[i]
                        break
                    end
                end
            end

            if better then
                best_list, best_chain, best_rank = list, chain, rank
            end
        end
    end

    return best_list, best_chain
end

--- The `YYYY-MM-DD` folder segment for a bookmark, from its creation date.
--
-- @tparam table bookmark
-- @treturn string|nil
function ArticleUtil.dateSegment(bookmark)
    if type(bookmark) ~= "table" then return nil end
    local stamp = bookmark.createdAt or bookmark.firstCreatedAt
    if type(stamp) ~= "string" then return nil end
    local year, month, day = stamp:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if not year then return nil end
    return year .. "-" .. month .. "-" .. day
end

--- Whether a list's folder should get a date subfolder.
--
-- "all" means every list; anything else is a comma-separated list of list
-- *names*, matched case-insensitively. Names rather than paths so that a
-- renamed parent does not silently switch the behaviour off.
--
-- @tparam string|nil setting
-- @tparam table|nil list The list being placed, or nil for no list at all.
-- @treturn bool
function ArticleUtil.wantsDateFolder(setting, list)
    if type(setting) ~= "string" or setting == "" or setting:lower() == "none" then
        return false
    end
    if setting:lower() == "all" then return true end
    if not list then return false end

    local name = (list.name or ""):lower()
    for wanted in (setting .. ","):gmatch("([^,]*),") do
        -- Lowercase the setting side too: the list name is lowercased above, and
        -- comparing "Morning briefs" to "morning briefs" never matched.
        if wanted:match("^%s*(.-)%s*$"):lower() == name then return true end
    end
    return false
end

--- Turn an article title into something safe to write to a Kobo's FAT32 partition.
-- @tparam string|nil title
-- @tparam[opt=180] number max_len Maximum length in bytes.
-- @treturn string Never empty.
function ArticleUtil.safeTitle(title, max_len)
    max_len = max_len or 180

    if type(title) ~= "string" or title == "" then
        return "Untitled"
    end

    title = title:gsub("[%z\1-\31\127]", " ")   -- control characters
    title = title:gsub('[/\\%?%*:|"<>]', "_")   -- illegal on FAT32/NTFS
    title = title:gsub("%[", "("):gsub("%]", ")") -- keep our ID prefix unambiguous
    title = title:gsub("%s+", " ")
    title = title:gsub("^%s+", ""):gsub("%s+$", "")

    if #title > max_len then
        title = ArticleUtil.trimPartialUtf8(title:sub(1, max_len))
        title = title:gsub("%s+$", "")
    end

    -- FAT32 cannot represent a name ending in a dot or a space.
    title = title:gsub("[%.%s]+$", "")

    if title == "" then return "Untitled" end
    return title
end

--- Build the local filename for a bookmark: "<title> [kk-id_<id>].epub".
-- @tparam string id Karakeep bookmark ID.
-- @tparam string|nil title
-- @tparam[opt=".epub"] string ext
-- @treturn string
function ArticleUtil.buildFilename(id, title, ext)
    ext = ext or ".epub"
    local marker = " " .. ArticleUtil.ID_OPEN .. id .. ArticleUtil.ID_CLOSE

    -- Leave room for the marker and the extension within a 255 byte name.
    local budget = 255 - #marker - #ext

    return ArticleUtil.safeTitle(title, math.min(180, budget)) .. marker .. ext
end

--- Extensions KOReader can open on a Kobo, keyed by the lowercased form.
--
-- An uploaded original outside this list would be downloaded and then be
-- unopenable, so it is treated as not worth fetching rather than saved as a
-- file with no provider.
ArticleUtil.ORIGINAL_EXTENSIONS = {
    pdf = ".pdf", epub = ".epub", cbz = ".cbz", cbr = ".cbr",
    txt = ".txt", html = ".html", htm = ".htm",
    jpg = ".jpg", jpeg = ".jpeg", png = ".png", gif = ".gif",
    webp = ".webp", bmp = ".bmp", tiff = ".tiff", tif = ".tif",
}

--- Work out the local extension for an uploaded original.
--
-- Karakeep stores the file the user uploaded (a PDF, an image) as an asset.
-- `assetType` names the family, but "image" does not say which format it is, so
-- the MIME type and then the file name are tried too. Anything KOReader has no
-- provider for returns nil.
--
-- @tparam table content Karakeep bookmark content table.
-- @treturn string|nil Extension including the dot, e.g. ".pdf".
function ArticleUtil.originalExtension(content)
    if type(content) ~= "table" then return nil end

    local candidates = {}

    if content.assetType == "pdf" then
        table.insert(candidates, "pdf")
    end

    if type(content.mimeType) == "string" then
        local subtype = content.mimeType:match("^%s*[%w.+-]+/([%w.+-]+)")
        if subtype then table.insert(candidates, subtype) end
    end

    if type(content.fileName) == "string" then
        local ext = content.fileName:match("%.([%w]+)$")
        if ext then table.insert(candidates, ext) end
    end

    -- "application/octet-stream" and the like fall through to the next
    -- candidate rather than becoming an extension of their own.
    for _, ext in ipairs(candidates) do
        local known = ArticleUtil.ORIGINAL_EXTENSIONS[ext:lower()]
        if known then return known end
    end

    return nil
end

--- Title for an uploaded original.
--
-- Assets have no URL to fall back on, and when the file name is all there is it
-- carries an extension that buildFilename() would then add a second time.
--
-- @tparam table bookmark Karakeep bookmark.
-- @treturn string Never empty.
function ArticleUtil.originalTitle(bookmark)
    local content = (type(bookmark) == "table" and bookmark.content) or {}

    local title = bookmark.title
    if type(title) ~= "string" or title == "" then title = content.title end
    if type(title) ~= "string" or title == "" then title = content.fileName end
    if type(title) ~= "string" or title == "" then return "Untitled" end

    -- Only strip a suffix that is actually a document extension: a title like
    -- "Node.js internals" must keep its ".js".
    local suffix = title:match("%.([%w]+)$")
    if suffix and ArticleUtil.ORIGINAL_EXTENSIONS[suffix:lower()] then
        local stripped = title:gsub("%.[%w]+$", "")
        if stripped ~= "" then title = stripped end
    end

    return title
end

--- Encode a Unicode code point as UTF-8. Lua 5.1 has no utf8 library.
-- @tparam number cp
-- @treturn string
function ArticleUtil.utf8Char(cp)
    if type(cp) ~= "number" or cp < 0 or cp > 0x10FFFF then return "" end

    if cp < 0x80 then
        return string.char(cp)
    elseif cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40),
                           0x80 + (cp % 0x40))
    elseif cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000),
                           0x80 + (math.floor(cp / 0x40) % 0x40),
                           0x80 + (cp % 0x40))
    end

    return string.char(0xF0 + math.floor(cp / 0x40000),
                       0x80 + (math.floor(cp / 0x1000) % 0x40),
                       0x80 + (math.floor(cp / 0x40) % 0x40),
                       0x80 + (cp % 0x40))
end

local NAMED_ENTITIES = {
    amp = "&", lt = "<", gt = ">", quot = '"', apos = "'",
    nbsp = " ", ensp = " ", emsp = " ", thinsp = " ", shy = "",
    ndash = "\226\128\147", mdash = "\226\128\148",
    lsquo = "\226\128\152", rsquo = "\226\128\153",
    ldquo = "\226\128\156", rdquo = "\226\128\157",
    hellip = "\226\128\166", middot = "\194\183", bull = "\226\128\162",
    copy = "\194\169", reg = "\194\174", trade = "\226\132\162",
    laquo = "\194\171", raquo = "\194\187", deg = "\194\176",
}

--- Decode the HTML entities we are likely to meet in crawled article text.
-- Unknown named entities are left untouched.
-- @tparam string s
-- @treturn string
function ArticleUtil.decodeEntities(s)
    if type(s) ~= "string" then return "" end

    s = s:gsub("&#[xX](%x+);", function(hex)
        return ArticleUtil.utf8Char(tonumber(hex, 16))
    end)
    s = s:gsub("&#(%d+);", function(dec)
        return ArticleUtil.utf8Char(tonumber(dec))
    end)
    -- Returning nil from gsub leaves the match in place, which is what we want
    -- for entities we do not know about.
    s = s:gsub("&(%a+);", function(name)
        return NAMED_ENTITIES[name]
    end)

    return s
end

--- Escape a string for inclusion in XML/XHTML text or an attribute value.
-- @tparam string|nil s
-- @treturn string
function ArticleUtil.escapeXml(s)
    if type(s) ~= "string" then return "" end
    s = s:gsub("&", "&amp;")
    s = s:gsub("<", "&lt;")
    s = s:gsub(">", "&gt;")
    s = s:gsub('"', "&quot;")
    s = s:gsub("'", "&apos;")
    return s
end

-- Case-insensitive pattern for a tag or attribute name, e.g. "script" ->
-- "[sS][cC][rR][iI][pP][tT]". Non-letters are escaped first, so the hyphen in
-- an attribute like "data-src" stays a literal instead of becoming the lazy
-- repeat quantifier it would otherwise be.
local function anyCase(word)
    return (word:gsub("%W", "%%%0"):gsub("%a", function(c)
        return "[" .. c:lower() .. c:upper() .. "]"
    end))
end

local function stripElement(html, tag)
    local name = anyCase(tag)
    -- Paired form, then any leftover self-closing or orphaned opening tag.
    html = html:gsub("<%s*" .. name .. "[^>]*>.-<%s*/%s*" .. name .. "%s*>", "")
    html = html:gsub("<%s*/?%s*" .. name .. "[^>]*>", "")
    return html
end

--- Remove elements and attributes that have no business in an offline EPUB.
-- crengine's getBalancedHTML() deals with well-formedness afterwards; this only
-- removes things that are actively unhelpful on an e-reader.
-- @tparam string|nil html
-- @treturn string
function ArticleUtil.sanitizeHtml(html)
    if type(html) ~= "string" then return "" end

    html = html:gsub("<!%-%-.-%-%->", "")
    html = html:gsub("<[%?!][^>]*>", "") -- doctypes and processing instructions

    -- <noscript> is where a lazy-loading site keeps the plain <img> that works
    -- without JavaScript, so throwing the element away throws away the picture.
    -- Its contents are unwrapped when there is an image among them, and dropped
    -- otherwise -- what is left in that case is a "please enable JavaScript"
    -- notice that helps nobody on an e-reader.
    local noscript = anyCase("noscript")
    html = html:gsub("<%s*" .. noscript .. "[^>]*>(.-)<%s*/%s*" .. noscript .. "%s*>",
        function(inner)
            if inner:find("<%s*[iI][mM][gG]") then return inner end
            return ""
        end)
    html = html:gsub("<%s*/?%s*" .. noscript .. "[^>]*>", "") -- orphans

    for _, tag in ipairs({ "script", "style", "iframe", "object", "embed",
                           "form", "input", "button", "svg", "canvas" }) do
        html = stripElement(html, tag)
    end

    -- Inline event handlers: onclick="…", onload='…'
    html = html:gsub("%s[oO][nN]%a+%s*=%s*\"[^\"]*\"", "")
    html = html:gsub("%s[oO][nN]%a+%s*=%s*'[^']*'", "")
    -- javascript: URLs
    html = html:gsub("([hH][rR][eE][fF]%s*=%s*)\"%s*[jJ][aA][vV][aA][sS][cC][rR][iI][pP][tT]:[^\"]*\"", "%1\"#\"")
    html = html:gsub("([hH][rR][eE][fF]%s*=%s*)'%s*[jJ][aA][vV][aA][sS][cC][rR][iI][pP][tT]:[^']*'", "%1'#'")

    return html
end

--- Flatten HTML to the plain text used for highlight offset matching.
-- @tparam string|nil html
-- @treturn string Whitespace-normalised, entity-decoded text.
function ArticleUtil.htmlToText(html)
    if type(html) ~= "string" then return "" end

    local s = ArticleUtil.sanitizeHtml(html)
    -- Block-level boundaries become spaces so words do not run together.
    s = s:gsub("<[^>]*>", " ")
    s = ArticleUtil.decodeEntities(s)
    s = s:gsub("%s+", " ")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")

    return s
end

--- Collapse runs of whitespace, so text captured on device can be compared with
-- text rendered on the server.
-- @tparam string|nil s
-- @treturn string
function ArticleUtil.normaliseWhitespace(s)
    if type(s) ~= "string" then return "" end
    s = s:gsub("%s+", " ")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

--- Count the UTF-16 code units a UTF-8 string occupies.
--
-- Karakeep is a JavaScript application, so the offsets its highlights API takes
-- index a JavaScript string: UTF-16 code units, not bytes. A single "é" is two
-- bytes but one code unit, an emoji four bytes but two, so byte offsets drift
-- as soon as an article contains anything outside ASCII -- which is to say
-- almost always, since a curly quote or an em-dash is enough.
--
-- @tparam string s
-- @treturn number
function ArticleUtil.utf16Length(s)
    if type(s) ~= "string" then return 0 end

    local units, i, len = 0, 1, #s

    while i <= len do
        local b = s:byte(i)
        if b < 0x80 then
            units, i = units + 1, i + 1
        elseif b < 0xC0 then
            -- A stray continuation byte: not valid UTF-8. Counting it as one
            -- keeps the result monotonic rather than silently losing ground.
            units, i = units + 1, i + 1
        elseif b < 0xE0 then
            units, i = units + 1, i + 2
        elseif b < 0xF0 then
            units, i = units + 1, i + 3
        else
            units, i = units + 2, i + 4 -- above the BMP: a surrogate pair
        end
    end

    return units
end

--- Move an index forward to the start of a UTF-8 character.
local function alignToCharStart(s, i)
    while i <= #s do
        local b = s:byte(i)
        if b < 0x80 or b >= 0xC0 then break end -- not a continuation byte
        i = i + 1
    end
    return i
end

--- Locate a highlighted passage within an article's plain text.
--
-- KOReader records highlights as crengine XPointers, which mean nothing to
-- Karakeep, so the only thing the two sides share is the highlighted text
-- itself. This is therefore best-effort: a passage that appears more than once
-- resolves to its first occurrence, and one that cannot be found at all returns
-- nil so the caller can decide what to do.
--
-- @tparam string text Article plain text, as returned by htmlToText().
-- @tparam string needle The highlighted passage.
-- @treturn number|nil Zero-based start offset, in UTF-16 code units -- what
--   Karakeep indexes by. See utf16Length().
-- @treturn number|nil End offset, exclusive.
function ArticleUtil.findTextOffsets(text, needle)
    if type(text) ~= "string" or type(needle) ~= "string" then return nil end

    needle = ArticleUtil.normaliseWhitespace(needle)
    if needle == "" then return nil end

    local match_pos, match_len

    local start_pos = text:find(needle, 1, true)
    if start_pos then
        match_pos, match_len = start_pos, #needle
    elseif #needle > 40 then
        -- KOReader may have captured a partial word at either end, or the
        -- crawler and the renderer may disagree about punctuation. Retry on a
        -- distinctive middle slice before giving up. The slice is snapped to
        -- character boundaries: cutting mid-sequence would still match
        -- byte-wise, but the offsets it produced would point into the middle
        -- of a character.
        local from = alignToCharStart(needle, 11)
        local probe = ArticleUtil.trimPartialUtf8(needle:sub(from, #needle - 10))
        if probe ~= "" then
            local probe_pos = text:find(probe, 1, true)
            if probe_pos then
                match_pos, match_len = probe_pos, #probe
            end
        end
    end

    if not match_pos then return nil end

    local start_offset = ArticleUtil.utf16Length(text:sub(1, match_pos - 1))
    local length = ArticleUtil.utf16Length(text:sub(match_pos, match_pos + match_len - 1))

    return start_offset, start_offset + length
end

--- Rewrite <img> sources to local EPUB paths, collecting what needs downloading.
--
-- Data URIs and images we cannot resolve are dropped rather than left pointing
-- at the network, so the EPUB never shows a broken-image box.
--
-- @tparam string|nil html
-- @tparam[opt=30] number max_images
-- @treturn string Rewritten HTML.
-- @treturn table Array of { src = <remote url>, path = "images/img1.jpg" }.
-- Attributes a lazy-loading site puts the real image in, best first. The plain
-- `src` on such a page is a placeholder -- a 1x1 GIF, a blur, or a data: URI --
-- so it is consulted last.
local LAZY_ATTRS = {
    "data-src", "data-original", "data-lazy-src", "data-actualsrc",
    "data-hi-res-src", "data-full-src", "data-image-src",
}

--- Read one attribute out of a tag's attribute text.
-- @tparam string attrs
-- @tparam string name
-- @treturn string|nil
local function attribute(attrs, name)
    local pattern = (name:gsub("%W", "%%%0"):gsub("%a", function(c)
        return "[" .. c:lower() .. c:upper() .. "]"
    end))
    local value = attrs:match(pattern .. "%s*=%s*\"([^\"]*)\"")
        or attrs:match(pattern .. "%s*=%s*'([^']*)'")
    if not value then return nil end

    value = ArticleUtil.decodeEntities(value)
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then return nil end
    return value
end

-- Roughly the widest a 300 dpi e-reader can use. Anything larger is downscaled
-- for display anyway, so fetching it only costs time, memory and storage.
local USEFUL_IMAGE_WIDTH = 1600

--- Choose one URL from a srcset.
--
-- A srcset is "url 480w, url 1200w" or "url 1x, url 2x". The widest candidate
-- that is still sensible for an e-reader screen wins; failing that, the
-- narrowest available, since something is better than nothing.
--
-- @tparam string|nil srcset
-- @treturn string|nil
function ArticleUtil.pickFromSrcset(srcset)
    if type(srcset) ~= "string" or srcset == "" then return nil end

    local best, best_width
    local smallest, smallest_width

    for candidate in (srcset .. ","):gmatch("%s*(.-)%s*,") do
        if candidate ~= "" then
            local url = candidate:match("^(%S+)")
            local descriptor = candidate:match("%s(%d+)[wW]$")
                or candidate:match("%s(%d+)%.?%d*[xX]$")

            if url then
                -- A bare URL with no descriptor is treated as full width, since
                -- it is the only candidate the author offered.
                local width = tonumber(descriptor) or USEFUL_IMAGE_WIDTH
                -- "2x" style descriptors are multipliers, not widths.
                if candidate:match("[xX]$") then width = width * 800 end

                if width <= USEFUL_IMAGE_WIDTH and (not best_width or width > best_width) then
                    best, best_width = url, width
                end
                if not smallest_width or width < smallest_width then
                    smallest, smallest_width = url, width
                end
            end
        end
    end

    return best or smallest
end

--- Work out which URL an <img> really points at.
--
-- Karakeep's extraction keeps the page's original markup, so an article from a
-- lazy-loading site arrives with the real image in a data- attribute or a
-- srcset and a placeholder in `src`. Reading `src` alone is why such articles
-- came through with no pictures.
--
-- @tparam string attrs The attribute text of an <img> tag.
-- @treturn string|nil
function ArticleUtil.imageSourceFrom(attrs)
    if type(attrs) ~= "string" then return nil end

    for _, name in ipairs(LAZY_ATTRS) do
        local value = attribute(attrs, name)
        if value then return value end
    end

    local from_srcset = ArticleUtil.pickFromSrcset(
        attribute(attrs, "data-srcset") or attribute(attrs, "srcset"))
    if from_srcset then return from_srcset end

    local src = attribute(attrs, "src")
    if not src then return nil end

    -- A placeholder is worse than nothing: it would occupy the slot and stop
    -- anything better being used.
    if src:match("^%s*[dD][aA][tT][aA]:") then return nil end
    if src:lower():match("placeholder") or src:lower():match("blank%.") then return nil end

    return src
end

function ArticleUtil.collectImages(html, max_images)
    if type(html) ~= "string" then return "", {} end
    max_images = max_images or 30

    local images = {}
    local by_src = {}

    local rewritten = html:gsub("<%s*[iI][mM][gG]([^>]*)>", function(attrs)
        local src = ArticleUtil.imageSourceFrom(attrs)

        if not src or src == "" then return "" end

        -- Only absolute http(s) sources are usable: Karakeep gives us the
        -- article out of context, so a relative path has nothing to resolve
        -- against, and data: URIs are already inline.
        if not src:match("^[hH][tT][tT][pP][sS]?://") then return "" end

        local existing = by_src[src]
        if existing then
            return string.format('<img src="%s"/>', ArticleUtil.escapeXml(existing))
        end

        if #images >= max_images then return "" end

        local ext = ArticleUtil.imageExtension(src)
        local path = string.format("images/img%d%s", #images + 1, ext)

        table.insert(images, { src = src, path = path })
        by_src[src] = path

        -- No alt="": crengine's getBalancedHTML() rewrites an empty attribute
        -- to a bare one ("alt"), which is not well-formed XML.
        return string.format('<img src="%s"/>', ArticleUtil.escapeXml(path))
    end)

    return rewritten, images
end

local KNOWN_IMAGE_EXTS = {
    jpg = ".jpg", jpeg = ".jpg", png = ".png", gif = ".gif",
    webp = ".webp", svg = ".svg", bmp = ".bmp",
}

--- Guess a file extension for an image URL, defaulting to .jpg.
-- @tparam string src
-- @treturn string
function ArticleUtil.imageExtension(src)
    local path = src:match("^[^%?#]*") or src
    local ext = path:match("%.([%a%d]+)$")
    if ext then
        local known = KNOWN_IMAGE_EXTS[ext:lower()]
        if known then return known end
    end
    return ".jpg"
end

local MEDIA_TYPES = {
    [".jpg"] = "image/jpeg", [".png"] = "image/png", [".gif"] = "image/gif",
    [".webp"] = "image/webp", [".svg"] = "image/svg+xml", [".bmp"] = "image/bmp",
}

-- The same mapping read the other way, for images whose type came from their
-- bytes rather than from a URL. Derived rather than written out twice: two
-- copies of this table would eventually disagree.
local EXT_FOR_MEDIA_TYPE = {}
for ext, media_type in pairs(MEDIA_TYPES) do
    EXT_FOR_MEDIA_TYPE[media_type] = ext
end

--- Map a local image path to its EPUB media type.
-- @tparam string path
-- @treturn string
function ArticleUtil.mediaType(path)
    local ext = path:match("(%.[%a%d]+)$")
    return (ext and MEDIA_TYPES[ext:lower()]) or "image/jpeg"
end

--- Sniff an image's media type from its magic bytes.
-- The extension in a URL is frequently a lie, and crengine will refuse an image
-- whose declared type does not match its content.
-- @tparam string data
-- @treturn string|nil Media type, or nil if unrecognised.
function ArticleUtil.sniffImageType(data)
    if type(data) ~= "string" or #data < 12 then return nil end

    if data:sub(1, 3) == "\255\216\255" then return "image/jpeg" end
    if data:sub(1, 8) == "\137PNG\r\n\26\n" then return "image/png" end
    if data:sub(1, 6) == "GIF87a" or data:sub(1, 6) == "GIF89a" then return "image/gif" end
    if data:sub(1, 4) == "RIFF" and data:sub(9, 12) == "WEBP" then return "image/webp" end
    if data:sub(1, 2) == "BM" then return "image/bmp" end
    if data:match("^%s*<%?xml") or data:match("^%s*<svg") then return "image/svg+xml" end

    return nil
end

--- Filename extension for a media type sniffed from image bytes.
--
-- The extension has to agree with the declared media type, and that type comes
-- from the bytes: a URL ending in .jpg that serves a PNG must be stored as .png,
-- or crengine refuses the image. See sniffImageType().
--
-- @tparam string|nil media_type e.g. "image/png".
-- @treturn string Extension including the dot, defaulting to .jpg.
function ArticleUtil.extensionForMediaType(media_type)
    return EXT_FOR_MEDIA_TYPE[media_type] or ".jpg"
end

--- Where a bookmark's cover art may come from, best first.
--
-- Karakeep holds the lead image twice: as an asset it serves itself, and as the
-- URL its crawler found on the page. The asset wins because it keeps working
-- after the original site drops the picture, and it is the image Karakeep's own
-- interface shows -- but fetching it needs the "Assets: Read" scope on the API
-- key, so the URL is a real fallback rather than a nicety.
--
-- A data: URI is not offered as a source: the bytes would have to be base64
-- decoded, and sniffing the result is what decides whether it is usable at all.
--
-- @tparam table|nil content A bookmark's content table.
-- @treturn table Array of 0, 1 or 2 sources: { kind = "asset", asset_id = … } or
--   { kind = "url", url = … }.
function ArticleUtil.coverSources(content)
    if type(content) ~= "table" then return {} end

    local sources = {}

    if type(content.imageAssetId) == "string" and content.imageAssetId ~= "" then
        table.insert(sources, { kind = "asset", asset_id = content.imageAssetId })
    end

    if type(content.imageUrl) == "string" and content.imageUrl:match("^[hH][tT][tT][pP][sS]?://") then
        table.insert(sources, { kind = "url", url = content.imageUrl })
    end

    return sources
end

--- Give every h2 and h3 an id, and list them for the table of contents.
--
-- The ids are numbered rather than derived from the heading text. A slug would
-- collide on repeated headings ("Notes" twice in one article is normal) and
-- would move whenever a heading was edited, and nothing needs the id to be
-- readable -- only for the NCX and the document to agree. Numbering in document
-- order also means rebuilding an article produces the same ids, so a re-download
-- is not a different document to anything that cached the old one.
--
-- An id the page already had is kept: in-page links in the article point at it.
--
-- @tparam string|nil html
-- @treturn string HTML with ids on its headings.
-- @treturn table Array of { level = 2|3, id = …, text = … } in document order.
function ArticleUtil.assignHeadingIds(html)
    if type(html) ~= "string" then return "", {} end

    local headings, number = {}, 0

    local rewritten = html:gsub("<%s*[hH]([23])([^>]*)>(.-)<%s*/%s*[hH]%1%s*>",
        function(level, attrs, inner)
            number = number + 1

            local id = attribute(attrs, "id")
            if not id then
                id = "kk-s" .. number
                attrs = attrs .. string.format(' id="%s"', id)
            end

            -- Plain text for the contents list: a heading holding <em> or a
            -- link would otherwise arrive as markup in the NCX.
            local text = ArticleUtil.trimPartialUtf8(ArticleUtil.htmlToText(inner):sub(1, 200))
            if text == "" then text = "…" end

            table.insert(headings, { level = tonumber(level), id = id, text = text })

            return string.format("<h%s%s>%s</h%s>", level, attrs, inner, level)
        end)

    return rewritten, headings
end

--- Arrange headings into a table-of-contents tree.
--
-- One level of nesting, and only that: an h3 belongs under the h2 above it,
-- which is the shape an article's structure actually has. An h3 with no h2
-- before it stays top-level rather than being dropped -- a heading that exists
-- in the text and nowhere in the contents is worse than a flat entry.
--
-- @tparam table|nil headings From assignHeadingIds().
-- @treturn table Array of { id, text, level, children = { … } }.
function ArticleUtil.tocFromHeadings(headings)
    if type(headings) ~= "table" then return {} end

    local toc, last_h2 = {}, nil

    for _, heading in ipairs(headings) do
        local entry = {
            id = heading.id,
            text = heading.text,
            level = heading.level,
            children = {},
        }

        if heading.level == 3 and last_h2 then
            table.insert(last_h2.children, entry)
        else
            table.insert(toc, entry)
            if heading.level == 2 then last_h2 = entry end
        end
    end

    return toc
end

--- Where an article's text might come from, best first.
--
-- `htmlContent` is the normal source and covers articles of any length. Karakeep
-- inlines it in its database only below a size threshold (5 KB by default), but
-- a request with includeContent=true hydrates the field from the asset before
-- answering, so that split is invisible here. `contentAssetId` is a safety net
-- for the case where Karakeep's own read of that asset fails: it swallows the
-- error and returns null rather than failing the request.
--
-- The archives are a different kind of thing. `precrawledArchive` is what a
-- SingleFile upload produced and `fullPageArchive` is Karakeep's own snapshot;
-- both are whole pages, including navigation, sidebars, cookie banners and
-- inlined assets. Karakeep runs a precrawled archive through the same
-- readability extraction it uses for a live crawl, so its text has already
-- reached `htmlContent`/`contentAssetId` by the time we see the bookmark. They
-- are therefore a fallback for when extraction produced nothing, not a
-- preference -- unless the caller asks otherwise.
--
-- @tparam table bookmark
-- @tparam[opt=false] bool prefer_archive Put the archives first.
-- @treturn table Array of { kind, asset_id, full_page, label }.
function ArticleUtil.contentSources(bookmark, prefer_archive)
    local content = (type(bookmark) == "table" and bookmark.content) or {}
    if content.type ~= "link" then return {} end

    local readable, archives = {}, {}

    if type(content.htmlContent) == "string" and content.htmlContent ~= "" then
        table.insert(readable, { kind = "inline", label = "inline readable HTML" })
    end
    if type(content.contentAssetId) == "string" and content.contentAssetId ~= "" then
        table.insert(readable, {
            kind = "asset",
            asset_id = content.contentAssetId,
            label = "readable HTML asset",
        })
    end

    -- The user's own capture first: it is the one that can hold content behind
    -- a paywall they are entitled to read.
    if type(content.precrawledArchiveAssetId) == "string" and content.precrawledArchiveAssetId ~= "" then
        table.insert(archives, {
            kind = "asset",
            asset_id = content.precrawledArchiveAssetId,
            full_page = true,
            label = "precrawled archive",
        })
    end
    if type(content.fullPageArchiveAssetId) == "string" and content.fullPageArchiveAssetId ~= "" then
        table.insert(archives, {
            kind = "asset",
            asset_id = content.fullPageArchiveAssetId,
            full_page = true,
            label = "full page archive",
        })
    end

    local sources = {}
    local first = prefer_archive and archives or readable
    local second = prefer_archive and readable or archives

    for _, source in ipairs(first) do table.insert(sources, source) end
    for _, source in ipairs(second) do table.insert(sources, source) end

    -- Always last: it is served as markdown, so formatting and images are lost
    -- in the conversion back to HTML.
    table.insert(sources, { kind = "endpoint", label = "readable content endpoint" })

    return sources
end

--- Coerce a value to something safe to put in a UI string.
--
-- stripJsonNulls() should mean nothing odd ever reaches formatting, but a
-- surprise from the API should degrade to a readable label rather than throw
-- from inside string.gsub and abandon the whole sync.
--
-- @tparam any value
-- @tparam[opt="?"] string fallback Used when the value is not usable text.
-- @treturn string
function ArticleUtil.displayText(value, fallback)
    fallback = fallback or "?"

    if type(value) == "string" and value ~= "" then return value end
    if type(value) == "number" then return tostring(value) end

    return fallback
end

--- The dc:language for a bookmark's package.
--
-- This is not just a metadata line: crengine picks its hyphenation dictionary
-- from it, so a wrong or missing language changes how the text is laid out on a
-- narrow screen. Karakeep's crawler records a language only when the page said
-- so, which is often not the case, hence the "en" default; and when it does
-- record one it may be a full tag like "en-GB", which crengine understands.
--
-- Anything that is not shaped like a language tag is ignored rather than written
-- into the package, where it would either be invalid or, worse, valid and wrong.
--
-- @tparam table|nil bookmark
-- @treturn string
function ArticleUtil.language(bookmark)
    bookmark = type(bookmark) == "table" and bookmark or {}
    local content = type(bookmark.content) == "table" and bookmark.content or {}

    local function usable(value)
        if type(value) ~= "string" then return nil end
        return value:match("^%a%a?%a?[%w%-]*$")
    end

    return usable(content.language) or usable(bookmark.language) or "en"
end

--- Classify a finished sync, for the summary's headline.
--
-- "Downloaded 0 articles." is literally true in every one of these cases and
-- useful in none of them: nothing was unread, everything was already on the
-- device, articles were only tidied up, or the plugin was never configured.
-- The counts are sorted into a kind here so that main.lua only has to choose
-- wording, and so the choice itself is exercised by the specs.
--
-- @tparam table counts downloaded, skipped, failed, removed, fetched, configured
-- @treturn string One of "not_configured", "downloaded", "cleaned_up",
--   "failed", "all_present", "nothing_unread" or "nothing_new".
function ArticleUtil.summaryKind(counts)
    if type(counts) ~= "table" then return "nothing_new" end

    if counts.configured == false then return "not_configured" end
    if (counts.downloaded or 0) > 0 then return "downloaded" end
    if (counts.removed or 0) > 0 then return "cleaned_up" end
    if (counts.failed or 0) > 0 then return "failed" end
    if (counts.skipped or 0) > 0 then return "all_present" end
    if (counts.fetched or 0) == 0 then return "nothing_unread" end

    return "nothing_new"
end

--- Sort a failure reason into something that can be acted on.
--
-- Reasons arrive from two places with different habits: downloadOriginal()
-- writes sentences for the reader, while EpubBuilder.build() returns machine
-- words because it has no gettext. Both are classified here, so that main.lua
-- can show a sentence, and so that the one failure with a real fix attached --
-- a 403, which on this API is nearly always a missing scope on the key -- can
-- carry the advice.
--
-- @tparam string|nil reason
-- @treturn string One of "no_content", "http_403", "http", "write",
--   "unsupported", "not_configured", "network" or "unknown".
function ArticleUtil.failureKind(reason)
    if type(reason) ~= "string" or reason == "" then return "unknown" end

    if reason == "no readable content" or reason == "no_content" then return "no_content" end
    if reason == "not_configured" then return "not_configured" end
    if reason == "network_error" then return "network" end
    if reason == "unsupported file type" or reason == "missing file" then return "unsupported" end
    if reason == "io_error" then return "write" end
    if reason == "http_error" or reason == "json_error" then return "server" end

    local status = reason:match("HTTP (%d%d%d)")
    if status then
        return status == "403" and "http_403" or "http"
    end

    if reason:find("zip_open_failed", 1, true)
        or reason:find("could not write", 1, true)
        or reason:find("archive is only", 1, true)
        or reason:find("rename_failed", 1, true)
        or reason:find("could not save", 1, true) then
        return "write"
    end

    return "unknown"
end

--- Replace JSON nulls with nil throughout a decoded response.
--
-- KOReader's JSON decoder represents null as a *function*, because a nil would
-- simply vanish from the table and the key would be indistinguishable from one
-- that was never sent. A function is truthy, so without this every
-- `bookmark.title or fallback` silently keeps the sentinel instead of falling
-- through, and it goes on to reach string formatting or a URL. Karakeep marks a
-- lot of fields nullable -- title, note, author, htmlContent, datePublished and
-- nextCursor among them -- so this is applied once to every decoded response.
--
-- A decoded JSON value can never legitimately be a function, so testing the type
-- is enough to identify the sentinel.
--
-- @tparam any value Decoded JSON.
-- @tparam[opt=0] number depth Recursion guard.
-- @treturn any The same value with nulls removed.
function ArticleUtil.stripJsonNulls(value, depth)
    if type(value) ~= "table" then
        if type(value) == "function" then return nil end
        return value
    end

    depth = (depth or 0) + 1
    if depth > 32 then return value end

    if value[1] ~= nil then
        -- Array-like: rebuild it, so that removing a null cannot leave a hole
        -- that would silently truncate a later ipairs().
        local out = {}
        for _, item in ipairs(value) do
            if type(item) ~= "function" then
                table.insert(out, ArticleUtil.stripJsonNulls(item, depth))
            end
        end
        return out
    end

    for key, item in pairs(value) do
        if type(item) == "function" then
            value[key] = nil
        elseif type(item) == "table" then
            value[key] = ArticleUtil.stripJsonNulls(item, depth)
        end
    end

    return value
end

--- Percent-encode a string for use in a URL query value.
-- @tparam string s
-- @treturn string
function ArticleUtil.urlEncode(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("[^%w%-%_%.%~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

--- Build a query string from a table, skipping anything that is not a scalar.
--
-- Keys are sorted so the output is stable and testable. Only strings, numbers
-- and booleans can be encoded; anything else is dropped rather than run through
-- tostring(), which would put a literal "table: 0x55f3…" on the wire and fail in
-- a thoroughly baffling way. Callers that care -- pagination, in particular --
-- must notice the value went missing; see Karaoke:fetchBookmarks().
--
-- @tparam table params
-- @treturn string Empty string, or "?a=1&b=2".
function ArticleUtil.buildQuery(params)
    if type(params) ~= "table" then return "" end

    local keys = {}
    for key, value in pairs(params) do
        local kind = type(value)
        if kind == "string" or kind == "number" or kind == "boolean" then
            table.insert(keys, key)
        end
    end
    table.sort(keys)

    local parts = {}
    for _, key in ipairs(keys) do
        local value = params[key]
        if type(value) == "boolean" then value = value and "true" or "false" end
        table.insert(parts, ArticleUtil.urlEncode(key) .. "=" .. ArticleUtil.urlEncode(tostring(value)))
    end

    if #parts == 0 then return "" end
    return "?" .. table.concat(parts, "&")
end

--- Normalise a user-entered server URL: strip trailing slashes and a trailing
-- "/api/v1" that people paste in from the Karakeep docs.
-- @tparam string|nil url
-- @treturn string
function ArticleUtil.normaliseServerUrl(url)
    if type(url) ~= "string" then return "" end

    url = url:gsub("^%s+", ""):gsub("%s+$", "")
    url = url:gsub("/+$", "")
    url = url:gsub("/api/v1$", "")
    url = url:gsub("/+$", "")

    return url
end

return ArticleUtil
