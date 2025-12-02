.DEFAULT_GOAL := stylua-run

ifeq ($(shell uname -s),Darwin)
    UNAME ?= MACOS
else
    UNAME ?= LINUX
endif

STYLUA_PLATFORM_MACOS := macos-aarch64
STYLUA_PLATFORM_LINUX := linux-x86_64
STYLUA_PLATFORM := $(STYLUA_PLATFORM_$(UNAME))

STYLUA_VERSION := v0.18.2
STYLUA_ZIP := stylua-$(STYLUA_PLATFORM).zip
STYLUA_URL_BASE := https://github.com/JohnnyMorganz/StyLua/releases/download
STYLUA_URL := $(STYLUA_URL_BASE)/$(STYLUA_VERSION)/$(STYLUA_ZIP)

.INTERMEDIATE: $(STYLUA_ZIP)
$(STYLUA_ZIP):
	wget $(STYLUA_URL)

stylua: $(STYLUA_ZIP)
	unzip $<

LUA_FILES = $(shell find lua -name '*.lua')
LUA_TEST_FILES = $(shell find test -name '*.lua')
LUA_FORMAT_FILES = $(LUA_FILES) $(LUA_TEST_FILES)

.PHONY: format-check
format-check: stylua
	@./stylua --check $(LUA_FORMAT_FILES)

.PHONY: format
format: stylua
	@./stylua $(LUA_FORMAT_FILES)
	@perl -0pi -e 's/^---@/--- @/gm' $(LUA_FORMAT_FILES)

.PHONY: test
test:
	./bin/nvim-test test --coverage
	# $(MAKE) -C example test LOCAL=1

NVIM_TEST_RUNTIME=$(XDG_DATA_HOME)/nvim-test/nvim-test-nightly/share/nvim/runtime

.PHONY: emmylua-check
emmylua-check:
	VIMRUNTIME=$(NVIM_TEST_RUNTIME) \
		emmylua_check lua --config .emmyrc.json
