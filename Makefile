PREFIX ?= /usr/local
SHARE_DIR = $(PREFIX)/share/ralph

.PHONY: install uninstall

install:
	mkdir -p $(SHARE_DIR)/lib
	mkdir -p $(SHARE_DIR)/templates
	cp lib/*.sh $(SHARE_DIR)/lib/
	cp templates/* $(SHARE_DIR)/templates/
	cp bin/ralph $(PREFIX)/bin/ralph
	chmod +x $(PREFIX)/bin/ralph
	sed -i '' 's|RALPH_ROOT=.*|RALPH_ROOT="$(SHARE_DIR)"|' $(PREFIX)/bin/ralph
	@echo "Installed ralph to $(PREFIX)/bin/ralph"

uninstall:
	rm -f $(PREFIX)/bin/ralph
	rm -rf $(SHARE_DIR)
	@echo "Uninstalled ralph"
