# stream-app aggregate build
#
# Builds streamd + StreamControl.app, embeds streamd into the app bundle, and
# packages a TrollStore-compatible .tipa at packages/StreamControl.tipa.

APP_NAME := StreamControl
APP_BUNDLE := StreamControl.app
TIPA := packages/$(APP_NAME).tipa
PAYLOAD_DIR := _payload/Payload

.PHONY: all streamd app embed package clean

all: package

streamd:
	$(MAKE) -C streamd stage FINALPACKAGE=1

app:
	$(MAKE) -C app stage FINALPACKAGE=1

embed: streamd app
	@set -e; \
	APP="app/.theos/_/Applications/$(APP_BUNDLE)"; \
	if [ ! -d "$$APP" ]; then \
	  APP=$$(find app/.theos/_ -maxdepth 8 -name '$(APP_BUNDLE)' -type d | head -n1); \
	fi; \
	STREAMD="streamd/.theos/_/usr/bin/streamd"; \
	if [ ! -f "$$STREAMD" ]; then \
	  STREAMD=$$(find streamd/.theos -maxdepth 8 -type f -name 'streamd' ! -path '*/dSYM/*' | head -n1); \
	fi; \
	if [ -z "$$APP" ] || [ ! -d "$$APP" ]; then \
	  echo "ERROR: $(APP_BUNDLE) not found"; exit 1; \
	fi; \
	if [ -z "$$STREAMD" ] || [ ! -f "$$STREAMD" ]; then \
	  echo "ERROR: streamd executable not found"; exit 1; \
	fi; \
	if [ ! -f "$$APP/Info.plist" ]; then \
	  cp app/Info.plist "$$APP/Info.plist"; \
	fi; \
	cp "$$STREAMD" "$$APP/streamd"; \
	chmod 755 "$$APP/streamd"; \
	if command -v ldid >/dev/null 2>&1; then \
	  ldid -Sstreamd/entitlements.plist "$$APP/streamd"; \
	  ldid -Sapp/entitlements.plist "$$APP/$(APP_NAME)"; \
	fi; \
	test -f "$$APP/Info.plist"; \
	test -x "$$APP/$(APP_NAME)"; \
	test -x "$$APP/streamd"; \
	echo "Embedded streamd into $$APP"

package: embed
	@set -e; \
	APP="app/.theos/_/Applications/$(APP_BUNDLE)"; \
	if [ ! -d "$$APP" ]; then \
	  APP=$$(find app/.theos/_ -maxdepth 8 -name '$(APP_BUNDLE)' -type d | head -n1); \
	fi; \
	rm -rf _payload packages; \
	mkdir -p "$(PAYLOAD_DIR)" packages; \
	cp -R "$$APP" "$(PAYLOAD_DIR)/$(APP_BUNDLE)"; \
	test -f "$(PAYLOAD_DIR)/$(APP_BUNDLE)/Info.plist"; \
	test -x "$(PAYLOAD_DIR)/$(APP_BUNDLE)/$(APP_NAME)"; \
	test -x "$(PAYLOAD_DIR)/$(APP_BUNDLE)/streamd"; \
	( cd _payload && zip -qr9 ../$(TIPA) Payload ); \
	echo "Created $(TIPA)"

clean:
	-$(MAKE) -C streamd clean
	-$(MAKE) -C app clean
	rm -rf _payload packages
