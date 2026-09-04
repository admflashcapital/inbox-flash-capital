# Convenções — Inbox Flash Capital

> **Escopo: 19 stories** no inventário, das quais **11 vivas** (épicos 1, 3, 4 e 6) — os épicos 2 e 5 foram cancelados. `compose.yaml`, `.env` e `scripts/` na raiz; `docker compose up -d --wait` é o comando único; a central escuta em `127.0.0.1:3001` e fala com o monorepo pela rede `flash-espelho`. Decisões em `docs/architecture.md` (AD-10..AD-15).
>
> Não há Python neste repo. Bash em `scripts/` (com `scripts/lib/env.sh` para ler o `.env` sem `source`) e um seed Ruby em `scripts/seed/`, idempotente por contrato.


## Chatwoot (dicionário fechado — a consistência é o produto)

- **Labels:** kebab-case, **só** as do Glossário do PRD, e **todas manuais** — ninguém empurra label
  para a central (o AD-13 carimba atributos; o Sync foi cancelado).
  `promessa-pagamento` · `negociacao` · `contestacao` · `aguardando-comprovante` ·
  `contato-errado` · `sem-retorno` · `escalar-alcada`
  Critério: a label descreve o que a **conversa** apurou, nunca o estado do **título** — esse é do
  monorepo (AD-1). Label nova = atualizar o Glossário em `docs/prd.md` **e** o seed, nesta ordem.
  Sinônimo solto mata o filtro. ⚠️ O model força minúsculas, recusa espaço, e `show_on_sidebar` é
  nullable sem default: não setar deixa a label invisível na barra lateral.
- **Atributos custom:** snake_case. Quem os grava é o **monorepo**, no instante do disparo
  (AD-13) — a central não os deriva de nada:
  `titulo_id` · `cnpj` · `cedente` · `numero_nf` · `data_vencimento` · `valor_em_aberto` ·
  `dias_atraso` · `link_boleto`
- **Nomes de inbox:** fixos — `WhatsApp Oficial` · `E-mail`

## Dados e formatos

- **Telefone:** sempre **E.164** (`+5531999998888`). Normalize na borda, antes de casar.
  ⚠️ O Twenty guarda `primaryPhoneNumber` **nacional** + `primaryPhoneCallingCode` (`+55`) —
  a conversão E.164 ↔ shape do Twenty não é responsabilidade da central.
- **Documento:** **só dígitos** para casar (CPF/CNPJ sem máscara).
- **Timestamps:** UTC.

## Infra

- `compose.yaml` + `.env.example` + `scripts/`
- Imagem do Chatwoot **sempre com tag explícita** — `latest` é proibido (AD-7/FR-2)
- **O seed é idempotente por contrato:** rodar duas vezes seguidas cria **zero** objetos. Toda
  extensão dele entra por `find_or_initialize_by`/`find_or_create_by`, nunca por `create!` solto —
  o `up` roda o seed toda vez, e um `create!` derrubaria a subida inteira no segundo boot.
- Upgrade: bump da tag + migrações, **validado em staging antes de produção** — ⚠️ **staging ainda não
  existe** (dívida rastreada no `PROGRESS.md`); até existir, o upgrade é feito em dev e o risco é
  assumido explicitamente, não esquecido.

## Variáveis de ambiente

- `.env.example` sempre sincronizado: var nova → placeholder + comentário no `.env.example`
- Segredos só em `.env` (gitignored) — nunca no código, no compose, no runbook nem no chat
- Nunca logar valor de env var

## Git

- Conventional commits: `feat(EPIC-N): STORY-X.Y — descrição` | `fix` | `chore` | `test` | `docs`
- Uma story = um commit. `main` direto (MVP single-dev).

## Idioma

- Tudo em PT-BR: docs, mensagens de commit, comentários de código, labels visíveis ao operador.
