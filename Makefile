PREFIX    ?= $(HOME)/.local
BINDIR    = $(PREFIX)/bin
LIBDIR    = $(PREFIX)/lib/fuetem
SHAREDIR  = $(PREFIX)/share/fuetem
APPDIR    = $(PREFIX)/share/applications

.PHONY: install uninstall

install:
	install -d $(BINDIR) $(LIBDIR) $(SHAREDIR)
	install -m 755 bin/fuetem $(BINDIR)/fuetem
	install -m 644 lib/lib.sh $(LIBDIR)/lib.sh
	install -m 644 lib/main.sh $(LIBDIR)/main.sh
	install -m 755 lib/vpncheck.sh $(LIBDIR)/vpncheck.sh
	install -m 755 lib/scan-secrets.sh $(LIBDIR)/scan-secrets.sh
	install -m 755 lib/integrity_check.sh $(LIBDIR)/integrity_check.sh
	install -m 755 lib/sysmonitor.sh $(LIBDIR)/sysmonitor.sh
	install -m 644 assets/arch.png $(SHAREDIR)/arch.png
	install -d $(APPDIR)
	sed 's|Icon=.*|Icon=$(SHAREDIR)/arch.png|' assets/fuetem.desktop > $(APPDIR)/fuetem.desktop
	chmod 644 $(APPDIR)/fuetem.desktop
	@echo ""
	@echo "Installed to $(PREFIX). Make sure $(BINDIR) is in your PATH."

uninstall:
	rm -f $(BINDIR)/fuetem
	rm -rf $(LIBDIR)
	rm -rf $(SHAREDIR)
	rm -f $(APPDIR)/fuetem.desktop
	@echo "Uninstalled fuetem from $(PREFIX)."
