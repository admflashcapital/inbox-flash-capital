# Runbook — Backup e Restore da Central

> **Story:** 1.4 · **FR-3** · LGPD
> A central é o repositório de PII mais denso da Flash: conversa de cliente com CPF/CNPJ, valor em
> aberto e situação de inadimplência. O backup dela **é** dado sensível.

## As duas metades

Um backup da central são **dois artefatos com o mesmo timestamp**:

| Artefato | O que é | Sem ele |
|---|---|---|
| `db_<data>.sql.gz` | banco `chatwoot_production`: conversas, contatos, labels, config, inboxes | não há central |
| `storage_<data>.tar.gz` | volume `storage_data`: **anexos** (nota fiscal, contrato, comprovante) | conversas restauram com anexo quebrado |

`scripts/backup.sh` gera os dois no mesmo par. Restaurar só o banco produz uma central que
*parece* íntegra até alguém clicar num anexo.

## Rodar o backup

```bash
bash scripts/backup.sh        # = scripts/backup.sh
```

- Grava em `BACKUP_DIR` (`.env`; default `./backups`, permissão `700`, arquivos `600`).
- **Retenção: 7 diários + 4 semanais** por artefato (domingo ganha sufixo `_weekly`).
- O `pg_dump` roda **dentro** do container, pelo socket local — nenhuma senha trafega em linha de
  comando nem aparece em `ps`.

### Agendar em produção (cron do host)

```cron
# 03:10 todo dia — backup da central
10 3 * * *  cd /srv/inbox-flash-capital && BACKUP_DIR=/srv/backups/inbox scripts/backup.sh >> /var/log/inbox-backup.log 2>&1
```

**Passo manual, e é o que salva a empresa:** o backup local morre junto com o host. Copie
`BACKUP_DIR` para fora da máquina (outro provedor, ou Drive/S3), **criptografado**:

```bash
age -r <chave-pública> -o backup.tar.gz.age backup.tar.gz     # ou gpg -c
```

Backup de conversa de cliente subindo sem criptografia para storage de terceiro é vazamento de PII
por conta própria. A chave privada **não** mora no mesmo host do backup.

## Restaurar

### Ensaio — o que prova que o backup presta (rode toda semana)

```bash
bash scripts/restore.sh --verificar      # = scripts/restore.sh --verificar
```

Sobe um Postgres **limpo e efêmero**, restaura o último par (dump + anexos), confere que
inboxes/contatos/conversas/mensagens vieram e que **cada anexo do banco tem o arquivo correspondente
no tar** — e destrói o ambiente de teste. **Não encosta na produção**, então pode rodar sem medo.

> Um backup nunca testado não é backup, é esperança. Este comando é a diferença.

### Restore de verdade (destrutivo)

```bash
scripts/restore.sh --producao
```

Derruba a stack, **apaga** o banco e o volume de anexos atuais e recompõe a partir do último backup.
Pede confirmação digitada. Depois, confira a UI antes de liberar o atendimento.

Restaurando num host novo: leve junto o `.env` (o `SECRET_KEY_BASE` **tem** que ser o mesmo,
senão as sessões e os tokens integrados quebram) e o par de backup.

## Retenção de conversa (LGPD)

O Chatwoot CE não expurga conversa por idade. Sem política, a central guarda CPF/CNPJ e histórico de
inadimplência para sempre — o oposto da minimização exigida pela LGPD.

```bash
bash scripts/retencao-conversas.sh                                      # simula (não apaga nada)
scripts/retencao-conversas.sh --executar    # apaga de verdade
```

Apaga conversas **resolvidas** mais velhas que `RETENCAO_CONVERSAS_DIAS` (default **1825 dias = 5
anos**), com mensagens e anexos. Conversa aberta ou pendente nunca é tocada.

> ⚠️ **Decisão pendente do jurídico.** A central guarda a conversa de **cobrança**: apagar cedo
> demais destrói a prova da negociação de uma dívida; tarde demais viola a LGPD. O default de 5 anos
> segue a prescrição civil comum, mas **precisa ser confirmado** antes de ir para o cron. O
> agendamento definitivo é da **STORY-6.3**, junto com o direito de exclusão do titular.

Lembre-se (AD-1): apagar o contato na central **não** apaga a verdade no Twenty/Supabase. Pedido de
titular atinge os **dois** lados.

## Registro dos ensaios de restore

| Data | Backup testado | Resultado |
|---|---|---|
| 2026-07-13 | `db_2026-07-13` + `storage_2026-07-13` | ✅ ambiente limpo: 1 inbox, 1 contato, 1 conversa, 1 mensagem, 1 anexo (arquivo presente) |
