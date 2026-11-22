--[[--
Specs for the size cap that stops an oversized download mid-transfer.

api.lua talks to luasocket, which the specs cannot use, so `socket.http.request`
is replaced here by a fake that behaves the way luasocket does around a sink:
chunks are pushed into `request.sink`, and a sink that answers nil is an aborted
transfer, which makes request() return `nil, err`.

The bug this pins down: the plugin used to save a whole 300 MB PDF and only then
notice it was over the limit and delete it. Filling a Clara's storage to find out
something is too big is not a discoverable failure, so the sink now refuses the
chunk that would pass the limit.
]]

local Runner = require("spec.runner")

local describe, it = Runner.describe, Runner.it
local assertEqual, assertTrue = Runner.assertEqual, Runner.assertTrue

local TMP = os.tmpname()

-- Chunks the fake request will push. Set by each test.
local chunks = {}

local function readFile(path)
    local handle = io.open(path, "r")
    if not handle then return nil end
    local body = handle:read("*a")
    handle:close()
    return body
end

-- Stand-ins for the KOReader modules api.lua requires at load time.
package.preload["ltn12"] = function()
    return {
        sink = {
            -- Pass-through: api.lua's sink handles the nil end-of-stream itself.
            new = function(send) return function(chunk, err) return send(chunk, err) end end,
            table = function(t)
                return function(chunk)
                    if chunk then table.insert(t, chunk) end
                    return 1
                end
            end,
        },
        source = { string = function(body) return body end },
    }
end
package.preload["logger"] = function()
    return setmetatable({}, { __index = function() return function() end end })
end
package.preload["json"] = function()
    return { encode = function() return "{}" end, decode = function() return {} end }
end
package.preload["socketutil"] = function()
    return { set_timeout = function() end, reset_timeout = function() end }
end
package.preload["socket"] = function()
    return {
        -- skip(n, ...) drops the first n values, like socket.skip
        skip = function(n, ...)
            local args = { ... }
            return unpack(args, n + 1)
        end,
        sleep = function() end,
    }
end
package.preload["socket.http"] = function()
    return {
        request = function(req)
            assert(req.sink, "the test only covers requests with a sink")
            for _, chunk in ipairs(chunks) do
                local ok, err = req.sink(chunk)
                if not ok then
                    -- What luasocket does when a sink refuses a chunk.
                    return nil, err
                end
            end
            req.sink(nil)
            return 1, 200, {}, "HTTP/1.1 200 OK"
        end,
    }
end

local ArticleUtil = require("articleutil")
local KarakeepApi = require("api")

local function api()
    return KarakeepApi:new{ server_url = "https://karakeep.example.com", api_token = "tok" }
end

local function bytes(n, char)
    return string.rep(char or "x", n)
end

describe("downloadAsset size cap", function()
    it("stops mid-transfer and leaves no file when the body passes the limit", function()
        chunks = { bytes(40, "a"), bytes(40, "b"), bytes(40, "c") } -- 120 bytes
        os.remove(TMP)

        local ok, err = api():downloadAsset("asset1", TMP, true, 100)

        assertTrue(not ok, "an oversized body must not be reported as downloaded")
        assertEqual(err, "too_large")
        assertEqual(readFile(TMP), nil)
    end)

    it("stops before writing the chunk that crosses the limit", function()
        -- 3 chunks of 40 against a 100 byte limit: the third is refused, so the
        -- file never grows past the limit while it exists.
        chunks = { bytes(40, "a"), bytes(40, "b"), bytes(40, "c") }
        os.remove(TMP)

        api():downloadAsset("asset1", TMP, true, 100)
        assertEqual(readFile(TMP), nil)
    end)

    it("downloads a body exactly at the limit", function()
        chunks = { bytes(50, "a"), bytes(50, "b") } -- exactly 100
        os.remove(TMP)

        local ok, path = api():downloadAsset("asset1", TMP, true, 100)

        assertTrue(ok)
        assertEqual(path, TMP)
        assertEqual(#readFile(TMP), 100)
    end)

    it("downloads a body under the limit in full", function()
        chunks = { bytes(30, "a"), bytes(30, "b") }
        os.remove(TMP)

        assertTrue(api():downloadAsset("asset1", TMP, true, 100))
        assertEqual(readFile(TMP), bytes(30, "a") .. bytes(30, "b"))
    end)

    it("is unlimited when no cap is given", function()
        chunks = { bytes(500, "a"), bytes(500, "b") }
        os.remove(TMP)

        assertTrue(api():downloadAsset("asset1", TMP, true))
        assertEqual(#readFile(TMP), 1000)
    end)

    it("removes a partial file when the connection drops", function()
        chunks = { bytes(10, "a") }
        os.remove(TMP)

        local dropping = require("socket.http")
        local real_request = dropping.request
        dropping.request = function(req)
            req.sink(bytes(10, "a"))
            return nil, nil -- no response at all, as when the connection drops
        end

        local ok, err = api():downloadAsset("asset1", TMP, true, 1000)
        dropping.request = real_request

        assertTrue(not ok)
        assertEqual(err, "network_error")
        assertEqual(readFile(TMP), nil)
    end)
end)

os.remove(TMP)
