local _ = require("gettext")
return {
    -- "Karaoke" rather than "Karakeep" so this is distinguishable in the plugin
    -- list from AlgusDark's karakeep.koplugin, which sends bookmarks and
    -- clippings the other way and can be installed alongside this one. It was
    -- "KaraKo" up to 0.8.0, which is the release that renamed it.
    fullname = _("Karaoke (Karakeep reader)"),
    description = _([[Downloads unread Karakeep articles for offline reading, saves uploaded PDFs and images unchanged, adds links from the device, and sends read status, tags and highlights back.]]),
    version = "0.10.0",
}
