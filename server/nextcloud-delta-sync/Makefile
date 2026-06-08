# Makefile for CrispCloud Delta Sync Nextcloud app
#
# Usage:
#   make release    — build a signed release tarball
#   make install    — install to local Nextcloud instance
#   make clean      — remove build artifacts

APP_ID = crispcloud_delta
VERSION = $(shell grep '<version>' appinfo/info.xml | sed 's/.*<version>//' | sed 's/<.*//')
TARBALL = $(APP_ID)-$(VERSION).tar.gz
NC_PATH ?= /var/www/nextcloud

.PHONY: release install clean sign

# Build release tarball
release: clean
	@echo "Building $(TARBALL)..."
	@mkdir -p build
	@tar czf build/$(TARBALL) \
		--transform 's,^,$(APP_ID)/,' \
		--exclude='build' \
		--exclude='Makefile' \
		--exclude='.git*' \
		--exclude='*.swp' \
		appinfo/ lib/ README.md
	@echo "Created build/$(TARBALL)"
	@echo ""
	@echo "To publish to Nextcloud App Store:"
	@echo "  1. Create an account at https://apps.nextcloud.com"
	@echo "  2. Register app ID '$(APP_ID)'"
	@echo "  3. Sign the tarball: openssl dgst -sha512 -sign ~/.nextcloud/certificates/$(APP_ID).key build/$(TARBALL) | openssl base64 -A"
	@echo "  4. Upload the tarball + signature at https://apps.nextcloud.com/developer/apps/releases/new"

# Install to local Nextcloud
install:
	@echo "Installing to $(NC_PATH)/apps/$(APP_ID)..."
	@sudo rm -rf $(NC_PATH)/apps/$(APP_ID)
	@sudo mkdir -p $(NC_PATH)/apps/$(APP_ID)
	@sudo cp -r appinfo lib README.md $(NC_PATH)/apps/$(APP_ID)/
	@sudo chown -R www-data:www-data $(NC_PATH)/apps/$(APP_ID)
	@sudo -u www-data php $(NC_PATH)/occ app:enable $(APP_ID)
	@echo "Done. Verify: curl -u admin:pass http://localhost/index.php/apps/$(APP_ID)/api/status"

clean:
	@rm -rf build
