.PHONY: check publish qemu reboot sync help

help:
	@echo "make check    - valida sintaxe dos scripts (bash -n)"
	@echo "make publish  - copia para o pendrive Ventoy + snapshot"
	@echo "make qemu     - sobe a VM de teste (UEFI) com o ISO do Arch"
	@echo "make reboot   - boota o sistema instalado na VM (sem ISO)"
	@echo "make sync     - diff entre esta máquina e packages/*.txt"

check:
	@for f in install.sh 04-optional.sh sync-manifest.sh test-qemu.sh \
	          test-reboot.sh publish-usb.sh lib/common.sh phases/*.sh; do \
	  bash -n "$$f" || exit 1; \
	done
	@echo "sintaxe ok"

publish:
	@bash publish-usb.sh

qemu:
	@bash test-qemu.sh

reboot:
	@bash test-reboot.sh

sync:
	@bash sync-manifest.sh
