# Runbook — Upgrade do Chatwoot

> **Story:** 1.3 · **FR-2** · **AD-7** (Community Edition, imagem oficial, **sem fork**)

## A regra

A versão do Chatwoot é **fixada por tag** em `deploy/.env` (`CHATWOOT_TAG`). Nunca `latest`:
`latest` significa que um `docker compose pull` num dia qualquer troca a versão da central sem
ninguém pedir — e migração de banco não tem botão de desfazer.

**Tag atual: `v4.15.1-ce`.** O sufixo `-ce` é obrigatório: é a Community Edition. As tags sem sufixo
carregam a pasta `enterprise/`, cujas features exigem licença comercial (AD-7). O `make check` falha
se alguém trocar por uma tag não-`-ce` ou por `latest`.

## Antes de subir de versão

1. Leia o **release notes** e o **CHANGELOG** entre a sua tag e a nova:
   https://github.com/chatwoot/chatwoot/releases — procure por `breaking`, mudança de env var e
   migração pesada.
2. **Backup verificado** (não basta ter backup — tem que ter restaurado):
   ```bash
   make backup
   make restore-check     # restaura num ambiente limpo e confere conversas + anexos
   ```
3. Confira se a nova versão mexe em algo de que a central depende: **integração Evolution**
   (EPIC-2), **canal Twilio/WhatsApp** (EPIC-3), **canal IMAP/e-mail** (EPIC-4) ou a **API de
   contatos/labels/atributos** que o Serviço de Sync usa (EPIC-5). Mudança na API de contatos quebra
   o Sync em silêncio — o enriquecimento simplesmente para de aparecer.

## O procedimento (staging → produção)

Sempre em **staging primeiro** (FR-2). Staging é a mesma composição, com `.env` próprio.

```bash
# 1. staging: bumpe a tag no .env de staging (só o nome da chave, sem tocar em segredo)
sed -i 's|^CHATWOOT_TAG=.*|CHATWOOT_TAG=vX.Y.Z-ce|' deploy/.env

# 2. puxe a imagem nova e aplique as migrações (o chatwoot-init é one-shot e idempotente)
docker compose -f deploy/docker-compose.yml --env-file deploy/.env pull
make migrate

# 3. suba
make up

# 4. valide
make check                       # tag fixa, -ce, isolamento, portas
make ps                          # todos healthy
```

**Fumaça funcional em staging** — o que realmente prova que o upgrade não quebrou a central:

- login na UI e abrir uma conversa existente (com anexo);
- mandar uma mensagem por cada inbox conectada;
- confirmar que o Serviço de Sync ainda empurra label/atributo (EPIC-5) — o contato enriquecido
  continua mostrando `cnpj`/`status_operacao` na barra lateral?

Só então repita os mesmos passos em produção, **em janela de baixo movimento** (a central é o canal
de cobrança; migração longa = atendimento parado).

## Rollback

Migração de banco **não volta sozinha**. Voltar a tag da imagem sem voltar o banco costuma quebrar
pior do que o upgrade. O rollback real é:

```bash
sed -i 's|^CHATWOOT_TAG=.*|CHATWOOT_TAG=<tag-anterior>|' deploy/.env
deploy/scripts/restore.sh --producao      # restaura o backup PRÉ-upgrade (destrutivo, pede confirmação)
```

Por isso o passo 2 da seção anterior (backup **verificado**) não é burocracia: é o rollback.

## Registro

Toda subida de versão vira uma linha aqui:

| Data | De | Para | Ambiente | Notas |
|---|---|---|---|---|
| 2026-07-13 | — | `v4.15.1-ce` | dev | instalação inicial (STORY-1.1) |
