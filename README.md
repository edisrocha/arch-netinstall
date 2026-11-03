# arch-netinstall

Instalação **one-shot e reprodutível** de Arch Linux a partir do live ISO oficial:
boota a ISO, roda um script, e sai com o sistema configurado (XFCE + i3, autologin,
Docker, Go/Node, timers de backup/cache, dotfiles).

Feito para reproduzir a máquina `bot` (EndeavourOS → Arch puro) sem depender de
nenhum pacote AUR no sistema base.

---

## 1. O que ele faz

| Fase | O quê |
|---|---|
| `00-preflight` | valida UEFI, rede, NTP, ranqueia espelhos (reflector) e **confere os 225 nomes de pacote antes de apagar o disco** |
| `10-disk` | GPT com ESP 2G + swap 8G + raiz ext4 (resto), monta em `/mnt` e `/mnt/boot` |
| `20-pacstrap` | instala base + manifesto, gera `fstab`, copia o instalador para `/mnt/root/netinstall` |
| `30-chroot` | locale/tz/teclado, usuário + sudo, serviços, lightdm, mkinitcpio, systemd-boot, dotfiles, timers, repos |
| `40-post` | (como usuário) dotfiles com backup, unidades `systemd --user`, `git config`, clones |
| `90-verify` | confere pacotes, serviços, boot, locale e grupos |

Diferenças conscientes em relação à máquina de origem:

- **ESP montada em `/boot`** (antes `/efi`), com kernel+initramfs na própria ESP —
  é o layout padrão do Arch quando se usa `systemd-boot` + `mkinitcpio`.
  Com `kernel-install-for-dracut` o EOS copiava os kernels para `/efi/<machine-id>`;
  aqui a `ESP` já é o `/boot`, sem hooks extras e sem AUR.
- 22 pacotes do repo `endeavouros` foram removidos/substituídos (branding, `welcome`,
  `eos-*`, `dracut`). Os ajustes que importavam (i3, tema, terminal) estão em `dotfiles/`.
- `yay` e pacotes AUR (`downgrade`, `qogir-icon-theme`, `arc-gtk-theme`) ficam para
  `04-optional.sh`, porque `makepkg` não roda como root dentro do chroot.

## 2. Uso

### 2.1 Preparar o pendrive

```bash
cd ~/Projetos/arch-netinstall
bash publish-usb.sh          # copia para o Ventoy + snapshot + sha256
```

O pendrive (Ventoy) fica com:

```
archlinux-2026.11.01-x86_64.iso
netinstall/                  <- este repositório
netinstall-YYYYMMDD.tar.zst  <- snapshot íntegro (preserva permissões)
```

### 2.2 Instalar

No live ISO:

```bash
mount /dev/disk/by-label/Ventoy /mnt/usb
nvim /mnt/usb/netinstall/config.env     # disco, hostname, usuário, kernel...
bash /mnt/usb/netinstall/install.sh --dry-run
bash /mnt/usb/netinstall/install.sh --disk /dev/sda
```

Wi-Fi (o live ISO não pergunta):

```bash
bash /mnt/usb/netinstall/install.sh --wifi "SUA_REDE" "SENHA" --disk /dev/sda
```

A senha do usuário é pedida interativamente na fase 30 (não fica em arquivo).

### 2.3 Depois do primeiro boot

```bash
bash ~/Projetos/arch-netinstall/04-optional.sh   # npm globals, AUR, ollama
```

## 3. Teste em VM (antes de tocar no SSD)

```bash
bash test-qemu.sh            # instala qemu/OVMF se faltar, cria disco de 40G, boota
bash test-reboot.sh          # boota o sistema instalado sem ISO
```

Dentro da VM o disco é `/dev/vda` e o instalador está no segundo CD-ROM:

```bash
mount /dev/sr1 /mnt/usb
bash /mnt/usb/install.sh --disk /dev/vda
```

Critério de aceite: systemd-boot com `Arch Linux (linux-lts)` como default, lightdm
com autologin no i3, `docker run hello-world`, timers `--user` ativos.

## 4. Manutenção

```bash
bash sync-manifest.sh          # diff entre o sistema atual e os manifests
bash sync-manifest.sh --write   # atualiza packages/*.txt
```

Assim o repositório continua sendo um **espelho vivo** da máquina, não uma foto.

## 5. Estrutura

```
install.sh            orquestrador (--disk --dry-run --yes --from --only --wifi)
config.env            todas as decisões (disco, hostname, kernels, desktop)
lib/common.sh         log, run/retry, confirmações, helpers de disco
phases/               00 preflight · 10 disco · 20 pacstrap · 30 chroot
                      chroot-system.sh (dentro do chroot) · 40 post · 90 verify
packages/             base.txt · desktop.txt · dev.txt · extra.txt · aur.txt
services/system.list  unidades habilitadas no sistema
units/                cpu-governor.service (custom) + unidades --user
dotfiles/             árvore do $HOME (i3, xfce4, dunst, rofi, gtk, bash, wallpapers)
scripts de apoio      04-optional.sh · sync-manifest.sh · test-qemu.sh
                      test-reboot.sh · publish-usb.sh
```

## 6. Segurança

- `--dry-run` não escreve nada no disco; use sempre primeiro.
- A fase 10 exige digitar `APAGAR`; `--yes` só deve ser usado em VM.
- O script recusa o disco que contém a mídia de instalação e discos com partição montada.
- Tudo é logado em `logs/install-*.log` (no pendrive, quando roda de lá).

## 7. Hardware de referência

Sandy Bridge (2C), Intel HD 2000, Atheros AR9485, 9,6 GB RAM, SSD 120 GB,
UEFI sem Secure Boot. `intel-ucode` + módulo `i915` no initramfs.
