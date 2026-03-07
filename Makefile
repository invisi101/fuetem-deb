PREFIX    ?= $(HOME)/.local
BINDIR    = $(PREFIX)/bin
LIBDIR    = $(PREFIX)/lib/fuetem
SHAREDIR  = $(PREFIX)/share/fuetem
APPDIR    = $(PREFIX)/share/applications

DESTDIR   ?=
DEPS      = bash iproute2 coreutils systemd dnsutils curl deborphan debsums debsecan smartmontools nmap lm-sensors

.PHONY: install install-files uninstall deps

deps:
	sudo apt-get update
	sudo apt-get install -y $(DEPS)

install: deps install-files

install-files:
	install -d $(DESTDIR)$(BINDIR) $(DESTDIR)$(LIBDIR) $(DESTDIR)$(SHAREDIR)
	install -m 755 bin/fuetem $(DESTDIR)$(BINDIR)/fuetem
	install -m 644 lib/lib.sh $(DESTDIR)$(LIBDIR)/lib.sh
	install -m 644 lib/main.sh $(DESTDIR)$(LIBDIR)/main.sh
	install -m 755 lib/vpncheck.sh $(DESTDIR)$(LIBDIR)/vpncheck.sh
	install -m 755 lib/scan-secrets.sh $(DESTDIR)$(LIBDIR)/scan-secrets.sh
	install -m 755 lib/integrity_check.sh $(DESTDIR)$(LIBDIR)/integrity_check.sh
	install -m 755 lib/sysmonitor.sh $(DESTDIR)$(LIBDIR)/sysmonitor.sh
	install -m 644 assets/arch.png $(DESTDIR)$(SHAREDIR)/arch.png
	install -d $(DESTDIR)$(APPDIR)
	sed 's|Icon=.*|Icon=$(SHAREDIR)/arch.png|' assets/fuetem.desktop > $(DESTDIR)$(APPDIR)/fuetem.desktop
	chmod 644 $(DESTDIR)$(APPDIR)/fuetem.desktop
	@echo ""
	@echo "Installed to $(PREFIX). Make sure $(BINDIR) is in your PATH."

uninstall:
	rm -f $(BINDIR)/fuetem
	rm -rf $(LIBDIR)
	rm -rf $(SHAREDIR)
	rm -f $(APPDIR)/fuetem.desktop
	@echo "Uninstalled fuetem from $(PREFIX)."
