PLUGIN_NAME = fylr-plugin-ubhd-3d-viewer
BUILD_DIR = build
PACKAGE_STAGE_DIR = $(BUILD_DIR)/.package/$(PLUGIN_NAME)
VIEWER_DIR = lib/ubhd-3d-viewer
VIEWER_DIST_DIR = $(VIEWER_DIR)/dist
VIEWER_DIST_ASSETS_DIR = $(VIEWER_DIST_DIR)/assets
SRC_DIR = src
SRC_WEBFRONTEND_DIR = $(SRC_DIR)/webfrontend
SRC_VIEWER_DIST_DIR = $(SRC_WEBFRONTEND_DIR)/viewer-dist
COFFEE_SOURCE = $(SRC_WEBFRONTEND_DIR)/UBHD3DViewerPlugin.coffee
COFFEE_JS = $(SRC_WEBFRONTEND_DIR)/UBHD3DViewerPlugin.coffee.js
COFFEE_BIN = node_modules/.bin/coffee
HOST_CSS = $(SRC_WEBFRONTEND_DIR)/fylr-plugin-ubhd-3d-viewer.css
PACKAGE_WEBFRONTEND_DIR = $(BUILD_DIR)/$(PLUGIN_NAME)/webfrontend
PACKAGE_VIEWER_DIST_DIR = $(PACKAGE_WEBFRONTEND_DIR)/viewer-dist
PACKAGE_JS = $(PACKAGE_WEBFRONTEND_DIR)/fylr-plugin-ubhd-3d-viewer.js
PACKAGE_CSS = $(PACKAGE_WEBFRONTEND_DIR)/fylr-plugin-ubhd-3d-viewer.css

all: build


build: clean code viewer-dist
	mkdir -p $(BUILD_DIR)/$(PLUGIN_NAME)/lib/ubhd-3d-viewer $(PACKAGE_WEBFRONTEND_DIR)
	if [ -d src ]; then cp -r src $(BUILD_DIR)/$(PLUGIN_NAME); fi
	if [ -d l10n ]; then cp -r l10n $(BUILD_DIR)/$(PLUGIN_NAME); fi
	if [ -d fas_config ]; then cp -r fas_config $(BUILD_DIR)/$(PLUGIN_NAME); fi
	cp -r $(VIEWER_DIST_DIR) $(BUILD_DIR)/$(PLUGIN_NAME)/lib/ubhd-3d-viewer/
	rm -rf $(PACKAGE_VIEWER_DIST_DIR)
	cp -r $(SRC_VIEWER_DIST_DIR) $(PACKAGE_VIEWER_DIST_DIR)
	cp $(COFFEE_JS) $(PACKAGE_JS)
	cp $(HOST_CSS) $(PACKAGE_CSS)

code: $(COFFEE_JS)

$(COFFEE_BIN): package.json package-lock.json
	npm ci

viewer-dist:
	@if [ ! -f $(COFFEE_SOURCE) ]; then \
		echo "Missing viewer host entry $(COFFEE_SOURCE)."; \
		exit 1; \
	fi
	@if [ ! -f $(HOST_CSS) ]; then \
		echo "Missing viewer host stylesheet $(HOST_CSS)."; \
		exit 1; \
	fi
	@if [ ! -d $(VIEWER_DIR) ]; then \
		echo "Missing viewer submodule at $(VIEWER_DIR). Run 'git submodule update --init --recursive'."; \
		exit 1; \
	fi
	@if [ ! -f $(VIEWER_DIR)/package.json ]; then \
		echo "Missing viewer package.json in $(VIEWER_DIR)."; \
		exit 1; \
	fi
	npm --prefix $(VIEWER_DIR) ci
	npm --prefix $(VIEWER_DIR) run build
	rm -rf $(SRC_VIEWER_DIST_DIR)
	mkdir -p $(SRC_VIEWER_DIST_DIR)
	cp $(VIEWER_DIST_DIR)/index.html $(SRC_VIEWER_DIST_DIR)/index.html
	cp -r $(VIEWER_DIST_ASSETS_DIR) $(SRC_VIEWER_DIST_DIR)/
	if [ -d $(VIEWER_DIST_DIR)/draco ]; then cp -r $(VIEWER_DIST_DIR)/draco $(SRC_VIEWER_DIST_DIR)/; fi
	sed -i 's|"/draco/"|new URL("../draco/", import.meta.url).href|g' $(SRC_VIEWER_DIST_DIR)/assets/index.js
	@if [ ! -f $(VIEWER_DIST_DIR)/index.html ]; then \
		echo "Missing viewer build output $(VIEWER_DIST_DIR)/index.html after npm run build."; \
		exit 1; \
	fi
	@if [ ! -f $(VIEWER_DIST_ASSETS_DIR)/index.js ]; then \
		echo "Missing viewer build output $(VIEWER_DIST_ASSETS_DIR)/index.js after npm run build."; \
		exit 1; \
	fi
	@if [ ! -f $(VIEWER_DIST_ASSETS_DIR)/index.css ]; then \
		echo "Missing viewer build output $(VIEWER_DIST_ASSETS_DIR)/index.css after npm run build."; \
		exit 1; \
	fi

zip: build
	mkdir -p $(PACKAGE_STAGE_DIR)
	cp manifest.master.yml $(PACKAGE_STAGE_DIR)/manifest.yml
	cp -r $(BUILD_DIR)/$(PLUGIN_NAME)/* $(PACKAGE_STAGE_DIR)/
	cd $(BUILD_DIR)/.package && zip -r ../$(PLUGIN_NAME).zip $(PLUGIN_NAME)
	rm -rf $(BUILD_DIR)/.package

$(COFFEE_JS): $(COFFEE_SOURCE) $(COFFEE_BIN)
	mkdir -p $(dir $@)
	$(COFFEE_BIN) -b -p --compile "$<" > "$@" || ( rm -f "$@" ; false )

clean:
	rm -rf $(BUILD_DIR)/$(PLUGIN_NAME) $(BUILD_DIR)/$(PLUGIN_NAME).zip $(BUILD_DIR)/.package
	rm -rf $(BUILD_DIR)/ubhd-3d-viewer $(BUILD_DIR)/ubhd-3d-viewer.zip
	rm -rf $(SRC_VIEWER_DIST_DIR)
