PLUGIN_NAME = fylr-plugin-ubhd-3d-viewer

COFFEE_FILES = \
	src/webfrontend/UBHD3DViewerPlugin.coffee
BUILD_DIR = build
LIB_DIR = lib
JS = $(BUILD_DIR)/$(PLUGIN_NAME)/webfrontend/$(PLUGIN_NAME).js

.PHONY: help l10n

L10N_FILES = l10n/$(PLUGIN_NAME).csv

CSS = src/webfrontend/$(PLUGIN_NAME).css
ZIP_NAME ?= $(PLUGIN_NAME).zip

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

all: build

zip: build ## build zip file for publishing
	cd $(BUILD_DIR) && zip $(ZIP_NAME) -r $(PLUGIN_NAME)

build: code css l10n copylib ## build all (creates build folder)
	mkdir -p $(BUILD_DIR)/$(PLUGIN_NAME)
	cp manifest.master.yml $(BUILD_DIR)/$(PLUGIN_NAME)/manifest.yml

copylib:
	mkdir -p $(BUILD_DIR)/$(PLUGIN_NAME)
	cp -r $(LIB_DIR)/* $(BUILD_DIR)/$(PLUGIN_NAME)/

code: $(JS)

l10n:
	mkdir -p $(BUILD_DIR)/$(PLUGIN_NAME)/l10n
	cp $(L10N_FILES) $(BUILD_DIR)/$(PLUGIN_NAME)/l10n/

clean: ## clean build files
	rm -rf $(BUILD_DIR)

css:
	mkdir -p $(BUILD_DIR)/$(PLUGIN_NAME)/webfrontend
	cp $(CSS) $(BUILD_DIR)/$(PLUGIN_NAME)/webfrontend/$(PLUGIN_NAME).css

${JS}: $(subst .coffee,.coffee.js,${COFFEE_FILES})
	mkdir -p $(dir $@)
	cat $^ > $@

%.coffee.js: %.coffee
	coffee -b -p --compile "$^" > "$@" || ( rm -f "$@" ; false )