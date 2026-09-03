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

### Agendamento (cron do host) — instalado

```cron
10 5 * * *  … backup.sh                >> backups/backup.log
40 5 * * 6  … restore.sh --verificar   >> backups/restore-verificar.log
```

Ambos com `flock` e com `cd` para a raiz do repo (cron roda com `cwd=$HOME`; sem o `cd`, o
`docker compose` não acha o `compose.yaml` e o log vai para o lugar errado). As quatro entradas
completas estão em `docs/runbook-operacao.md`.

**Por que 05:10 e não 03:10:** no domingo o expurgo LGPD roda às 04:10. Um backup feito **antes** dele
congelaria por quatro semanas exatamente a conversa que a política acabou de apagar. Rodando depois, o
snapshot semanal já nasce expurgado.

**Por que a poda depende do cron:** a retenção 7+4 é executada *pelo próprio* `backup.sh`, no fim da
rodada. Sem o job agendado, nada é gerado **e** nada é podado — os artefatos antigos ficam para sempre.
`verificar-operacao.sh` cobra as duas entradas.

Ao mudar de host, reveja o `BACKUP_DIR`: fora do repo, e num disco que não seja o mesmo que morre com a
máquina.

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

> **Decidido e agendado.** Os 5 anos foram aprovados por escrito pelo operador em 2026-09-02 e o
> expurgo está no cron do host (domingo 04:10, com `flock`, log em `backups/retencao.log`). A tensão
> que motivou a decisão continua valendo como critério: apagar cedo demais destrói a prova da
> negociação de uma dívida; tarde demais viola a minimização.

Lembre-se (AD-1): apagar o contato na central **não** apaga a verdade no Twenty/Supabase. Pedido de
titular atinge os **dois** lados — o procedimento completo está em `docs/runbook-lgpd.md`.

## Registro dos ensaios de restore

| Data | Backup testado | Resultado |
|---|---|---|
| 2026-07-13 | `db_2026-07-13` + `storage_2026-07-13` | ✅ ambiente limpo: 1 inbox, 1 contato, 1 conversa, 1 mensagem, 1 anexo (arquivo presente) |
