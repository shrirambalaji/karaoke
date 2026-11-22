LUA ?= $(shell command -v lua5.1 || command -v luajit || command -v lua)
LUAC ?= $(shell command -v luac5.1 || command -v luac)

PLUGIN_SOURCES := $(wildcard karaoke.koplugin/*.lua) $(wildcard spec/*.lua)
# tools/ runs inside KOReader and must set G_reader_settings, which is a global
# by KOReader's design, so it gets the syntax check but not the globals check.
ALL_SOURCES := $(PLUGIN_SOURCES) $(wildcard tools/*.lua)

# Single source of truth for the version: _meta.lua, which is also what the
# plugin logs at startup to identify itself.
VERSION := $(shell sed -n 's/.*version = "\([^"]*\)".*/\1/p' karaoke.koplugin/_meta.lua)
DIST := karaoke.koplugin-v$(VERSION).zip

.PHONY: test check all dist check-version clean

all: check test

test:
	@$(LUA) spec/all.lua

# luac -p catches syntax errors; the SETGLOBAL grep catches accidental globals,
# which Lua otherwise accepts silently and fails on much later.
check:
	@status=0; \
	for f in $(ALL_SOURCES); do \
		if ! out=$$($(LUAC) -p "$$f" 2>&1); then \
			echo "syntax: $$f: $$out"; status=1; \
		fi; \
	done; \
	for f in $(PLUGIN_SOURCES); do \
		if $(LUAC) -l -p "$$f" 2>/dev/null | grep -q SETGLOBAL; then \
			echo "global assignment in $$f:"; \
			$(LUAC) -l -p "$$f" | grep SETGLOBAL; status=1; \
		fi; \
	done; \
	[ $$status -eq 0 ] && echo "check: $(words $(ALL_SOURCES)) files OK"; \
	exit $$status

# The release zip. Unzips to "karaoke.koplugin/", so it can be extracted straight
# into KOReader's plugins directory with nothing to rearrange.
#
# Only *.lua is copied, deliberately: karaoke.conf may legitimately sit next to
# the plugin and holds an API token in plain text, so a glob that swept the
# whole directory would publish somebody's key.
dist: check test
	@rm -rf build "$(DIST)"
	@mkdir -p build/karaoke.koplugin
	@cp karaoke.koplugin/*.lua build/karaoke.koplugin/
	@cp LICENSE README.md build/karaoke.koplugin/
	@cd build && zip -q -r "../$(DIST)" karaoke.koplugin
	@rm -rf build
	@echo "built $(DIST):"
	@unzip -Z1 "$(DIST)" | sed 's/^/  /'

# Guards a release against a tag that disagrees with _meta.lua. The version the
# plugin logs is how a stale install gets spotted, so it has to be true.
#   make check-version TAG=v0.6.0
check-version:
	@test -n "$(TAG)" || { echo "usage: make check-version TAG=v1.2.3"; exit 1; }
	@test "$(TAG)" = "v$(VERSION)" || { \
		echo "tag $(TAG) does not match _meta.lua version $(VERSION)"; \
		echo "update karaoke.koplugin/_meta.lua, or retag"; exit 1; }
	@echo "version: $(TAG) matches _meta.lua"

clean:
	@rm -rf build karaoke.koplugin-v*.zip
