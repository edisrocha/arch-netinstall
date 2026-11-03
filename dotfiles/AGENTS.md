# AGENTS.md — Workspace NexMatch

Workspace root para o sistema **NexMatch** (ex-MatchVagas).

## Projeto ativo

`~/Projetos/Nexmatch/` — repositório clonado do GitHub (`edisrocha/mv3`).

- Stack: **Go 1.25** (Chi, pgx) + **React 18** (Vite, Tailwind) + **PostgreSQL 16**
- Deploy: Render.com
- Docs completos: `~/Projetos/Nexmatch/AGENTS.md` (orquestração, comandos, arquitetura)
- Config OpenCode: `~/Projetos/Nexmatch/opencode.json`

> Antes o workspace apontava para `~/Projetos/Mv3/`, que **não existe** mais.
> O repositório ativo é `~/Projetos/Nexmatch/`.

## Análise de produto (entrada única + motor de match)

`~/Projetos/nexmatch-analysis/` — análise separada do código do produto.

- Índice: `~/Projetos/nexmatch-analysis/README.md`
- Conceito: `conceito/entrada-unica.md`
- Técnico: `tecnico/motor-de-match.md`
- Negócio: `negocio/analise-mercado.md`
- Roadmap: `roadmap/plano-acao.md`

## Biblioteca geral

`~/Projetos/biblioteca/` — base de conhecimento reutilizável para qualquer projeto com agentes.

- Índice: `~/Projetos/biblioteca/README.md`
- Linux: `~/Projetos/biblioteca/linux/fundamentos-linux.md`

## HD auxiliar de backup

`/dev/sdb1` — HD auxiliar (WD 500 GB, ext4, 5400 rpm) montado em
`/run/media/rocha/6fda6bf9-590a-499f-a5b1-15ff10048db8`

> ⚠️ O dispositivo correto é **`/dev/sdb1`**. O `/dev/sda1` é a partição **EFI**
> (`/efi`). A montagem é "na hora" (udisks), **não persistente no boot**.

### Conteúdo útil

| Caminho | Descrição |
|---------|-----------|
| `Mv1/` | Versão histórica (Node/Express) — 28/abr |
| `Mv2/` | Versão intermediária (Python/FastAPI) — 12/mai; usar só como evidência de experimentos de IA |
| `Mv3/` | **Cópia desatualizada** (10/jun) — a versão viva é `~/Projetos/Nexmatch/` (04/out) |
| `backups/mv3_2026-05-19.dump` | Dump PostgreSQL |

> ⚠️ Nada no HD é fonte de verdade. Sempre trabalhar em `~/Projetos/Nexmatch/`.

Montar: `udisksctl mount -b /dev/sdb1`

## Setup instalado

| Ferramenta | Versão |
|------------|--------|
| Go | 1.26.4 |
| Node.js | 26.2.0 |
| npm | 11.16.0 |
| Docker | 29.5.2 |
| Docker Compose | 5.1.4 |

> Docker: você precisa estar no grupo `docker` (`sudo usermod -aG docker $USER` + relogar).

Pendente: `psql` se for restaurar dump do backup.

## Backup automático do banco

O backup roda **2 minutos após ligar o notebook** e depois a cada 24h via systemd timer:

```bash
# Script: ~/Projetos/Nexmatch/scripts/backup-db.sh
# Timer:  ~/.config/systemd/user/nexmatch-backup.timer
# Destino: HD auxiliar em /backups/mv3_*.dump.gz
# Retenção: 14 dias

# Ver status do timer
systemctl --user status nexmatch-backup.timer

# Rodar manualmente agora
systemctl --user start nexmatch-backup.service
```

## Limpeza automática de caches (alívio do SSD)

Dois timers mantêm o SSD enxuto removendo **somente caches regeneráveis**:

```bash
# Cache do pacman (sistema, semanal, domingo) — mantém 1 versão por pacote
systemctl status paccache.timer

# Caches do usuário (semanal, domingo 03:00)
# Script: ~/.local/bin/limpar-caches.sh
# Timer:  ~/.config/systemd/user/limpar-caches.timer
# Log:    ~/.local/state/limpar-caches.log
# Limpa: ~/.cache/{pip,go-build,mozilla,chromium*,mesa_shader_cache,...} + npm cache
# NÃO limpa: modelos baixados (huggingface, ms-playwright) para evitar re-download
systemctl --user status limpar-caches.timer
systemctl --user start limpar-caches.service   # rodar agora
```

## Migração de dados para o HD auxiliar

Dados **frios** ficam no HD (`/dev/sdb1`); projetos **ativos** ficam no SSD
(velocidade). Já migrados:

| Origem (SSD) | Destino (HD) |
|---|---|
| `~/Documentos/{Manual, video, software / 说明书，视频，软件教学}` | `HD/ssd-offload/Documentos/` |
| `~/Projetos/archdistro/out/*.iso` | `HD/ssd-offload/projetos-archdistro/` |
| `~/Downloads` (**symlink**) | `HD/Downloads/` |

> ⚠️ `~/Downloads` é um **link** para o HD. Se o HD não estiver montado, o link
> fica quebrado. Reverter: `rm ~/Downloads && mkdir ~/Downloads`.

## Comandos rápidos (do projeto)

```bash
cd ~/Projetos/Nexmatch
make test          # testes Go + scripts
make test-go       # só testes Go
make local-up      # sobe stack completa (Docker + API + frontend + worker)
```

## Laboratório de engenharia reversa

`~/Projetos/re-lab/` — exercícios de RE (radare2, rizin, gdb/gef/pwndbg, Ghidra).

- Índice: `~/Projetos/re-lab/README.md`
