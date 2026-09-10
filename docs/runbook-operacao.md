# Runbook — operar a central (EPIC-6)

> O EPIC-6 é quase todo **configuração**, e configuração apodrece sem ninguém ver: um clique desfaz o
> que o seed montou. Por isso tudo aqui tem um verificador que cobra ao vivo:
> `bash scripts/verificar-operacao.sh`.

## Pôr alguém para atender

```bash
bash scripts/criar-agente.sh --nome "Fulana" --email fulana@flashcapital.com.br --inbox "E-mail"
bash scripts/criar-agente.sh --listar
```

O script pede a senha e **não a ecoa** — ela vai por stdin para o container, é gravada com `umask 077`,
lida pelo Ruby e apagada no mesmo comando. Nunca em `argv`, nunca em variável de ambiente, nunca no
`.env`.

**Por que não usamos o convite nativo:** o `AgentBuilder` do Chatwoot cria a pessoa com senha aleatória
e conta com um **e-mail de convite** para ela trocá-la. Não há SMTP configurado nesta instalação — o
convite não chega e o agente nasceria inutilizável. Quando o SMTP transacional existir (pendência de
produção, `runbook-deploy.md`), o convite pela tela volta a ser o caminho natural.

**`--inbox` não é detalhe.** Sem ele o agente entra e a tela abre **vazia**: `assigned_inboxes` de um
agente é exatamente a interseção com `inbox_members`. E é essa mesma lista que decide o que ele alcança
de CPF/CNPJ — ver `runbook-lgpd.md`.

Papéis: só existem **dois**, `agent` e `administrator` (`--admin`). Papel customizado é premium e está
desligado; não há meio-termo.

## Atribuição: manual, por decisão

`enable_auto_assignment` está **desligado** nas duas inboxes, e o seed reconcilia isso a cada `up`.

Não é pendência, é decisão: com um operador só, round robin é ruído. E o flag ligado **mentia** — a fila
do `AutoAssignment::AssignmentService` sai de `inbox_members` ∩ agentes **online**, então com
`inbox_members` vazio ele nunca distribuiu nada, enquanto a tela dizia que sim.

Para ligar quando houver 2+ atendentes: troque o `false` no bloco de reconciliação do
`scripts/seed/chatwoot_seed.rb`, povoe `inbox_members` e conte com **até 30 minutos de atraso** — quem
dispara é o cron `periodic_assignment_job`, que roda `*/30`.

Assumir e reatribuir à mão continua funcionando sempre: `assignable_agents` soma os administradores
incondicionalmente, então o dropdown nunca fica vazio.

## Labels — dicionário fechado, aplicação manual

**Ninguém empurra label para a central.** O AD-13 carimba **atributos** no instante do disparo, e o
Serviço de Sync — que aplicaria labels de segmento — foi cancelado (EPIC-5). Toda label é marcação da
atendente.

O critério que define o dicionário: **label descreve o que a CONVERSA apurou, nunca o estado do
TÍTULO.** Estado de título é do monorepo (AD-1); repetir aqui criaria duas verdades que divergem no
primeiro pagamento não conciliado.

| Label | Quando aplicar |
|---|---|
| `promessa-pagamento` | o sacado se comprometeu com uma data |
| `negociacao` | pede parcelamento ou desconto — a decisão não é da atendente |
| `contestacao` | contesta mercadoria, nota ou valor. Volta ao cedente antes de cobrar de novo |
| `aguardando-comprovante` | diz que pagou; falta o comprovante para conferir com a conciliação |
| `contato-errado` | quem respondeu não é o responsável financeiro — trocar o contato na rede |
| `sem-retorno` | mandamos e não responde. É o que justifica escalar o canal |
| `escalar-alcada` | precisa de decisão acima da operação (recompra, protesto, jurídico) |

Label nova entra **no seed**, nunca só pela tela — senão ela some no próximo ambiente. Duas armadilhas
do model, medidas:

- `title` é forçado a **minúsculas** e **recusa espaço**;
- `show_on_sidebar` é *nullable sem default*: não setar deixa a label existente, aplicável e
  **invisível** na barra lateral. É a mesma classe de falha silenciosa do AD-13.

Renomear depois dispara `Labels::UpdateJob` para reescrever todas as taggings. Acerte na primeira vez.

## Respostas rápidas

Cinco, semeadas: `/prazo` · `/comprovante` · `/2via` · `/responsavel` · `/encerrar`. Chame com `/` na
composição.

Sem variável de propósito. O Chatwoot substitui `{{contact.name}}` no momento da inserção, então o
cliente nunca receberia a chave crua — mas o **nome do contato vem do canal** e é heterogêneo (medido:
"comercial", "Financeiro lokaforte", um rótulo de número). "Olá comercial," sai pior do que não saudar.

**O que não entra no seed:** dados de pagamento (chave PIX, conta). São dado de negócio, mudam sem
aviso, e uma chave errada versionada no repo vira dinheiro no lugar errado. Crie essa resposta pela
tela, em Configurações → Respostas rápidas.

## A janela de 24h — o que a tela faz sozinha

Comportamento **nativo**, e ele depende de um campo só: o `medium` do canal.

| Situação | O que a central faz |
|---|---|
| cliente falou há **< 24h** | `can_reply = true` → texto livre |
| **> 24h** em silêncio | `can_reply = false` → o editor **fecha**, aparece um banner em pt-BR e a UI só oferece os Content Templates aprovados |

⚠️ **A proteção é da TELA, não da API.** `Base::SendOnChannelService` e o `MessagesController` não
consultam `can_reply?`, e o `Twilio::SendOnTwilioService` não tem o fallback-para-template que o canal
WhatsApp Cloud tem. Quem posta **pela API** — o monorepo, um script, um bot — passa fora da janela, o
Chatwoot aceita, e só a Twilio recusa depois. Consertar exigiria fork (AD-7). **Quem chama a API é
responsável por checar antes.**

Nota de operação: a atendente responde pelo WhatsApp apenas enquanto a central tiver **URL pública**
(AD-11.1). Túnel caído ⇒ erro 21609 no envio. O monitor abaixo cobra isso.

## Os jobs do host

São de **dois tipos**, e a diferença é deliberada.

### Sonda de liveness — no cron

```
0 * * * *  … monitorar-canais.sh --executar  >> backups/monitor-canais.log
```

Com `flock` (execução única) e `cd` para a raiz do repo — cron roda com `cwd=$HOME`, e sem o `cd` o
`docker compose` não acha o `compose.yaml`. Fica no cron **porque é sonda de saúde**: recuperar uma
verificação atrasada não faz sentido, só interessa o estado de agora, e a próxima virada de hora já
traz. É também o único agendamento que comprovadamente rodava antes de 08/09/2026.

### Jobs de dado — timers do systemd

```
central-backup.timer          diário  12:10  → backup.sh  →(Wants)→ backup-offsite.sh
central-retencao.timer        dom     12:00  → retencao-conversas.sh --executar
central-restore-check.timer   sáb     12:40  → restore.sh --verificar
```

Unidades versionadas em `scripts/systemd/`; instala com `sudo bash scripts/systemd/instalar.sh`.

**Por que timer, e não cron.** Esta máquina é de expediente — liga ~11h, desliga ~19h, e passa o fim de
semana desligada. Cron não recupera hora perdida, e cron de usuário não é coberto por anacron. Medido em
08/09/2026 no `syslog`: `monitorar-canais` tinha **10 execuções** e os outros quatro tinham **zero**, em
três semanas. Os logs `backup.log`, `backup-offsite.log` e `restore-verificar.log` sequer existiam. Todo
timer tem `Persistent=true`: hora que passou com a máquina desligada é executada na próxima subida.

**A ordem é da unidade, não do relógio.** `central-retencao.service` declara
`Before=central-backup.service`; `central-offsite.service` e `central-restore-check.service` declaram
`After=central-backup.service`. Numa segunda-feira que recupera o fim de semana inteiro, sai
**expurgo → backup → offsite → ensaio**. Invertida, o snapshot semanal guardaria por quatro semanas a
conversa que a política acabou de apagar — no cron essa ordem dependia de 04:10 vir antes de 05:10, o
que não sobrevive a uma recuperação.

**Antes de rodar, espera a stack.** Na recuperação o job dispara com o Docker ainda subindo — os
timers entram no ar antes do `docker.service`. `scripts/lib/aguardar-stack.sh` segura até o daemon responder e o Postgres da central
ficar `healthy`, com teto de 5 min; estourou, o job **não** roda — melhor isso do que um dump truncado.
O offsite é o único sem essa espera: ele só lê arquivo e fala com o bucket, e exigir a stack de pé o
faria depender justamente do que ele existe para substituir.

A poda 7+4 dos artefatos é feita pelo próprio `backup.sh`: sem o job, nada é gerado **e** nada é podado.
O ensaio de restore não encosta na produção — sobe um Postgres efêmero, recompõe o último par
banco+anexos, confere as contagens e destrói tudo. É o que separa backup de esperança.

### O que o verificador cobra

`verificar-operacao.sh` faz **três** perguntas por job de dado, e a terceira é a que faltava:

1. o timer está habilitado e ativo;
2. tem `Persistent=true` — sem isso ele é cron com outro nome;
3. **quando foi a última execução** (5 dias para os diários, 10 para os semanais).

A asserção nova é a (3). Entre 17/08 e 08/09 este verificador ficou verde enquanto quatro jobs nunca
rodaram, porque a pergunta era *"a linha existe?"* — e existia. Evidência **inexistente** agora é
falha dura.

E a evidência é escolhida por job, o que não é detalhe. Para o **backup** ela é o artefato mais novo
(`backups/db_*.sql.gz`), não o log: quem redireciona para o log é a unidade, então um
`bash scripts/backup.sh` rodado à mão produziria o par banco+anexos **sem** tocar no log — e o
verificador diria "nunca executou" com o dump ali do lado. A pergunta que interessa é *"existe backup
recente?"*, e quem responde isso é o dump. Já o **expurgo** e o **ensaio de restore** não deixam
artefato — um apaga, o outro destrói o ambiente de teste no fim — então neles o log é a única
evidência que sobra.

A cópia offsite é cobrada **condicionalmente**, e a condição é o `.env`: preencheu `BACKUP_S3_BUCKET` e
`BACKUP_S3_ACCESS_KEY_ID`, o verificador passa a exigir o encadeamento `Wants=` **e** a
`BACKUP_OFFSITE_PASSPHRASE`. É o modo de falha que interessa — alguém configura o bucket, acha que está
protegido, e nada nunca sobe. Enquanto não configurar, o verificador diz que é opt-in e segue verde.

### Instalar, e como desfazer

```bash
sudo bash scripts/systemd/instalar.sh      # unidades + 3 timers + o cron do monitor
```

Cobre os **dois** mecanismos de propósito: os 3 timers e também a linha de cron do monitor. Deixar o
cron de fora faria uma máquina nova subir com backup agendado e **nenhuma sonda** — e nada acusaria,
porque a falta de um agendamento é silêncio, não erro.

Idempotente: rodar de novo sobrescreve as unidades, reenlaça os timers e não duplica a linha de cron.
Precisa de `sudo` porque `/etc/systemd/system/` é do sistema — não porque seja arriscado.
Ele **não** apaga nada, não toca em banco, conversa ou backup, e não reinicia serviço nenhum.

Desfazer:

```bash
sudo bash scripts/systemd/desinstalar.sh --pausar     # desliga os timers, mantém os arquivos
sudo bash scripts/systemd/desinstalar.sh --remover    # desliga e apaga as unidades
```

Existe um script para isso, e não só três nomes de unidade para digitar, porque **um nome errado
desliga metade dos jobs e deixa a outra metade rodando** — o pior dos dois mundos, e em silêncio.

> A âncora da VM **não** é unidade do systemd: é a janela da tarefa `WSL-Always-On` do Windows
> (`docs/runbook-wsl-autostart.md`). Instalar ou desinstalar estas unidades não mexe nela.

**Desligar não é neutro.** Sem os timers, esta máquina para de gerar backup (e de podar os antigos,
porque quem poda é o próprio `backup.sh` no fim da rodada), para de subir o offsite, para de testar
se o backup abre, e para de aplicar o expurgo da LGPD — a central volta a guardar CPF/CNPJ e
histórico de cobrança para sempre. O monitor de canais continua, porque ele está no cron.

Enquanto estiver desligado, o que importa roda à mão — os scripts são os mesmos:

```bash
bash scripts/backup.sh
bash scripts/backup-offsite.sh --executar
bash scripts/restore.sh --verificar
bash scripts/verificar-operacao.sh          # e ele vai acusar os timers ausentes
```

**Voltar para o cron não é a saída.** Foi medido em 08/09/2026: ali os quatro jobs tinham zero
execuções. O cron não é pior por acaso — ele não tem onde anotar que a hora passou.

### O que o monitor observa

Sete sinais de **liveness** — coisa que muda sozinha, ao contrário das invariantes de configuração que
os `verificar-*.sh` cobram:

1. a central responde e o `/api` diz Postgres e Redis `ok`;
2. a **URL pública chega na nossa central** — a prova é o `/api` devolver a mesma versão, não "respondeu
   alguma coisa": um ngrok morto devolve **404**, idêntico ao 404 legítimo do Rails;
3. o agendador do IMAP enfileirou há menos de 3 min — parado, a atendente **para de responder e-mail** em até
   1h, com falha dentro de um job e nada na tela;
4. o canal de e-mail não pede reautorização;
5. nenhuma mensagem `failed` nas últimas 24h (é o **único** sinal de saúde do canal WhatsApp: o
   `Channel::TwilioSms` não inclui `Reauthorizable`, então "canal desconectado" não existe para ele);
6. o `central-retencao.timer` continua ativo — é o expurgo LGPD;
7. a âncora da VM está conectada — o `sleep infinity` da janela da tarefa `WSL-Always-On`. Sem ela, a
   VM fica segura só por algum terminal ou pelo VS Code, e cai 15 s depois que o último fechar,
   containers e agendamentos junto. Religa-se com `Start-ScheduledTask -TaskName "WSL-Always-On"`.

Quando o estado **muda**, o monitor posta um alerta no **sino do Nexus**, no painel do monorepo
(`POST /notificacoes/alerta`, header `X-Monitor-Token`). Notifica na transição, não a cada tick: uma
queda de 6h gera 2 avisos, não 6. Volta ao normal → aviso `success`.

Chaves envolvidas: `MONITOR_URL` e `MONITOR_TOKEN` no `.env` daqui; `MONITOR_TOKEN` **com o mesmo
valor** no `.env` do monorepo.

> O painel só mostra o aviso se a API do monorepo estiver no ar — e o alerta some do radar se **esta
> máquina** estiver desligada. É o mesmo limite do expurgo, e ele só cai quando a central sair para um
> host que fica de pé.

## Checagem

```bash
bash scripts/verificar-operacao.sh        # 15 invariantes da operação
bash scripts/monitorar-canais.sh --simular
bash scripts/criar-agente.sh --listar
```
