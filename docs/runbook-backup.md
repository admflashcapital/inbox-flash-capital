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

### Agendamento (timers do systemd) — instalado

```
central-backup.timer          diário  12:10   → backup.sh, e puxa o offsite
central-restore-check.timer   sáb     12:40   → restore.sh --verificar
central-retencao.timer        dom     12:00   → retencao-conversas.sh --executar
```

Unidades versionadas em `scripts/systemd/`; instala com `sudo bash scripts/systemd/instalar.sh`.

**Por que timer e não cron, e por que meio-dia.** Esta máquina é de expediente: liga por volta das 11h,
desliga por volta das 19h, e passa o fim de semana desligada. Cron não recupera hora perdida (e cron de
usuário não é coberto por anacron), então um job de madrugada aqui simplesmente **nunca roda** — medido
em 08/09/2026, foram **zero execuções em três semanas** para backup, offsite, ensaio de restore e
expurgo. Todo timer tem `Persistent=true`: se a hora marcada passou com a máquina desligada, ele executa
na próxima vez que ela subir. O horário deixa de ser uma aposta sobre quando a máquina estará ligada.

**Por que o ensaio de restore continua marcado no sábado** mesmo com a máquina sempre desligada no fim
de semana: com `Persistent=true` ele roda na segunda, logo após o backup do dia. Uma vez por semana,
como sempre foi a intenção — o que mudou é que agora acontece.

**A ordem é garantida pela unidade, não pelo relógio.** `central-retencao.service` declara
`Before=central-backup.service`, e `central-restore-check.service` declara `After=`. Assim, quando uma
segunda-feira recupera os três de uma vez, sai expurgo → backup → offsite → ensaio. No cron essa ordem
dependia de 04:10 vir antes de 05:10, o que não sobrevive a uma recuperação.

**Por que a stack é esperada antes de rodar:** com recuperação no boot, o job dispara enquanto o Docker
Desktop ainda está subindo do lado do Windows. `scripts/lib/aguardar-stack.sh` segura até o daemon
responder e o Postgres da central ficar `healthy`, com teto de 5 min — melhor não rodar do que gravar
um dump truncado.

**Por que a poda depende do agendamento:** a retenção 7+4 é executada *pelo próprio* `backup.sh`, no fim
da rodada. Sem o job, nada é gerado **e** nada é podado — os artefatos antigos ficam para sempre.
`verificar-operacao.sh` cobra o timer **e a idade da última execução**, que é a asserção que faltava.

Ao mudar de host, reveja o `BACKUP_DIR`: fora do repo, e num disco que não seja o mesmo que morre com a
máquina.

**O backup local morre junto com o host** — quem resolve isso é o `backup-offsite.sh`, na seção
*Cópia offsite* abaixo. Ele cifra em AES256 antes de subir, porque backup de conversa de cliente indo
sem criptografia para storage de terceiro é vazamento de PII por conta própria.

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

## Cópia offsite — o backup que sobrevive à morte da máquina

O `backup.sh` grava **só em disco local**. Host morre, backup morre junto — e a central é o
repositório de PII mais denso da Flash. O `backup-offsite.sh` fecha esse buraco: cifra os artefatos
e os espelha num bucket S3-compatível (Supabase Storage).

```bash
bash scripts/backup-offsite.sh --simular    # default seguro: não sobe nada
bash scripts/backup-offsite.sh --executar   # cifra e sobe
```

### A credencial NÃO é a `service_role` — e isso não é detalhe

O `verificar-invariantes.sh` proíbe `SUPABASE_*` no `.env` desta central (**AD-9**, sem cross-DB).
A regra está certa: a `service_role` **fura RLS no projeto inteiro**, então guardá-la aqui daria à
central leitura e escrita no **banco de domínio**. Um backup não precisa disso.

O que se usa é a chave de **S3 Access Keys** — no painel: **Storage → S3 Access Keys** —, escopada a
storage e incapaz de tocar o banco. Por isso o prefixo no `.env` é `BACKUP_S3_`, não `SUPABASE_`: não
é credencial do Supabase como banco, é credencial de um object store que por acaso é dele.

| O que criar | Onde |
|---|---|
| bucket **privado** (ex.: `central-backups`) | Storage → New bucket, **Public = off** |
| par de chaves S3 | Storage → S3 Access Keys → New access key |
| `rclone` no host | **sem sudo:** baixar o zip de `downloads.rclone.org` e `install -m0755 rclone ~/.local/bin/` · **com sudo:** `curl https://rclone.org/install.sh \| sudo bash`. O script resolve o binário por caminho, então `~/.local/bin` funciona **no cron também** — `command -v` sozinho não funcionaria, porque o cron roda com PATH mínimo |

Depois preencha no `.env`: `BACKUP_S3_ENDPOINT`, `BACKUP_S3_REGION`, `BACKUP_S3_BUCKET`,
`BACKUP_S3_ACCESS_KEY_ID`, `BACKUP_S3_SECRET_ACCESS_KEY` e `BACKUP_OFFSITE_PASSPHRASE`.
**Com qualquer uma vazia o script avisa e sai com 0** — é opt-in, não falha.

### 🔑 A frase secreta tem de morar FORA desta máquina

Os artefatos sobem cifrados em **AES256** (`gpg --symmetric`), porque o dump carrega CPF/CNPJ, valor
em aberto, conteúdo de conversa **e o `refresh_token` do Gmail em texto puro**. Sem cifrar, o offsite
moveria tudo isso para um bucket de terceiro em claro.

A frase vive em `BACKUP_OFFSITE_PASSPHRASE`, no `.env` — **na mesma máquina que o backup existe para
proteger**. Se a máquina morrer e a frase só existir nela, o offsite está lá e é **ilegível**.
**Copie a frase para o gerenciador de senhas hoje**, não no dia do incêndio.

Restaurar um artefato de lá:

```bash
gpg --decrypt --output db_2026-09-04.sql.gz db_2026-09-04.sql.gz.gpg
# e daí em diante é o mesmo `restore.sh` da seção acima
```

### Por que `sync` e não `copy`

O remoto vira **espelho** do `BACKUP_DIR`, que o `backup.sh` já poda em 7 diários + 4 semanais. A
retenção offsite sai de graça e **idêntica** — sem uma segunda política para divergir em silêncio. E
um dia que falhou é recuperado na rodada seguinte, porque o sync olha o conjunto, não o dia.

Depois de subir, o script **pergunta ao bucket** quantos objetos existem e falha se o número não
bater com o que subiu: "sync OK" é a palavra do cliente; o que vale é o que o outro lado devolve.

### Provado em 2026-09-04, não só escrito

Primeira execução real: 8 artefatos cifrados, 8 confirmados no bucket. E o que importa mais —
**ensaio de restore a partir do BUCKET**, não do disco: as duas metades baixadas, decifradas e
comparadas com `cmp` contra o original. **Byte-a-byte idênticas**, com o dump abrindo 90 tabelas e o
tar listando os 19 anexos. Backup offsite que ninguém baixou de volta é esperança, igual ao local.

### Encadeada no backup, não agendada à parte

O offsite **não tem timer próprio**. `central-backup.service` declara
`Wants=central-offsite.service`, e o offsite declara `After=central-backup.service`. Assim a cópia
remota não pode divergir do dia que acabou de ser gerado — o que não está em disco não sobe, e o que
acabou de entrar em disco sobe na mesma rodada.

É `Wants` e não `Requires` de propósito: se o dump de hoje falhar, ainda vale subir os dias anteriores
que porventura não subiram. E é o único job dos quatro **sem** `aguardar-stack.sh` — ele só lê arquivo
e fala com o bucket. Exigir a stack de pé faria a cópia offsite depender justamente daquilo que ela
existe para substituir.

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
> expurgo roda pelo `central-retencao.timer` (domingo 12:00, com recuperação, log em
> `backups/retencao.log`). A tensão
> que motivou a decisão continua valendo como critério: apagar cedo demais destrói a prova da
> negociação de uma dívida; tarde demais viola a minimização.

Lembre-se (AD-1): apagar o contato na central **não** apaga a verdade no Twenty/Supabase. Pedido de
titular atinge os **dois** lados — o procedimento completo está em `docs/runbook-lgpd.md`.

## Registro dos ensaios de restore

| Data | Backup testado | Resultado |
|---|---|---|
| 2026-07-13 | `db_2026-07-13` + `storage_2026-07-13` | ✅ ambiente limpo: 1 inbox, 1 contato, 1 conversa, 1 mensagem, 1 anexo (arquivo presente) |
