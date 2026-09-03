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

## Os dois jobs do host

```
10 4 * * 0  … retencao-conversas.sh --executar   >> backups/retencao.log
0  * * * *  … monitorar-canais.sh   --executar   >> backups/monitor-canais.log
```

Ambos com `flock` (execução única) e `cd` para a raiz do repo.

### O que o monitor observa

Seis sinais de **liveness** — coisa que muda sozinha, ao contrário das invariantes de configuração que
os `verificar-*.sh` cobram:

1. a central responde e o `/api` diz Postgres e Redis `ok`;
2. a **URL pública chega na nossa central** — a prova é o `/api` devolver a mesma versão, não "respondeu
   alguma coisa": um ngrok morto devolve **404**, idêntico ao 404 legítimo do Rails;
3. o cron do IMAP enfileirou há menos de 3 min — parado, a atendente **para de responder e-mail** em até
   1h, com falha dentro de um job e nada na tela;
4. o canal de e-mail não pede reautorização;
5. nenhuma mensagem `failed` nas últimas 24h (é o **único** sinal de saúde do canal WhatsApp: o
   `Channel::TwilioSms` não inclui `Reauthorizable`, então "canal desconectado" não existe para ele);
6. o cron do expurgo LGPD continua registrado.

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
bash scripts/verificar-operacao.sh        # 12 invariantes da operação
bash scripts/monitorar-canais.sh --simular
bash scripts/criar-agente.sh --listar
```
