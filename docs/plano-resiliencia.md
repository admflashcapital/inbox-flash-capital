# Plano de resiliência — sobreviver a queda de luz, de internet e de máquina

> A central vai rodar numa máquina do escritório, ligada 24h. Este doc responde a uma pergunta só:
> **quando ela cair, o que se perde e como se volta?** Nada aqui está implementado.
>
> **Boa parte não depende do domínio novo** e pode ser feita hoje — está marcado item a item.
>
> **Contexto:** `docs/fase-4-premissas.md` (topologia) · `docs/runbook-cloudflare.md` (o vigia
> externo) · `PROGRESS.md` §Dívida técnica (AD-12).

---

## 1. O que uma queda custa — e a fronteira ainda NÃO se mudou

> **MEDIDO em 2026-09-03, direto na API da Twilio.** O número de produção `+553123916846` tem
> `sms_url` **e** `status_callback` apontando para `b021-…​.ngrok-free.app` — um túnel da **máquina do
> escritório**. O monorepo tem deploy no Railway, mas **a fronteira pública continua aqui**.
>
> Isso inverte a conclusão. Enquanto o webhook não mudar, **uma queda do escritório derruba o caminho
> do dinheiro**, não só o painel.

### Hoje — o webhook termina na máquina do escritório

| Caminho | Numa queda | Recuperável? |
|---|---|---|
| **E-mail** (IMAP) | nada se perde | ✅ **sozinho.** É *polling de saída*: as mensagens esperam na INBOX e são buscadas quando a máquina volta (`SINCE` ontem). Queda > 1 dia → `backfill-email.sh 30` |
| **Twilio → monorepo** (confirmação de sacado) | ❌ **a resposta do cliente não chega** | ❌ a Twilio não retenta indefinidamente. A confirmação de sacado, que é o que **não pode falhar**, falha |
| **Link do boleto** (`/b/…`) | ❌ o cliente não baixa | ❌ a URL está no túnel desta máquina |
| **Mídia dos templates** | ❌ a Twilio não busca o PDF → **63019** | ❌ idem |
| **Status de entrega** | a régua não sabe se entregou | ✅ `reconciliar_status_twilio.py --dia AAAA-MM-DD`. Idempotente |
| **Espelho → Chatwoot** | não aparece no painel | ❌ **perde para sempre** (AD-12) |

### Depois de apontar o webhook para o Railway

| Caminho | Numa queda | Recuperável? |
|---|---|---|
| **Twilio → monorepo**, boleto e mídia | **nada se perde** | ✅ **deixam de depender do escritório** |
| **Régua / fila de disparo** | roda no Railway | ✅ *(confirmar se o planner recupera atraso ou pula a janela)* |
| **Espelho → Chatwoot** | não aparece no painel | ❌ ainda perde — é o que o **F1** endereça |

**A conclusão que organiza o plano, e ela mudou:** o item de maior valor não é autostart nem fila — é
**mover a fronteira pública para o Railway** (§B0). É o único que tira a receita da dependência de uma
máquina de escritório, e **não depende do domínio novo**: é CNAME na zona que já existe.

Só depois disso a frase "a queda ameaça o painel, não o negócio" passa a ser verdadeira. Aí o conserto
do painel fica barato, porque o remetente (Railway) continua vivo e **pode guardar o que não conseguiu
entregar** — o buraco do AD-12 passa a ser por **falta de fila**, não por falta de dado.

---

## 2. A cadeia de retomada automática

Três dos quatro elos já funcionam. Verificado em 2026-09-03:

```
Windows liga
  └─ ❌ WSL2 NÃO sobe sozinho            ← o único elo faltando
       └─ ✅ systemd            (wsl.conf: systemd=true)
            └─ ✅ docker         (systemd: enabled + active)
                 └─ ✅ containers (restart: unless-stopped nos 4)
                      └─ ✅ cron   (enabled; provado ao vivo — o monitor rodou às 18:00 sozinho)
```

Um reboot do Windows (update de madrugada) derruba tudo e **nada volta até alguém logar**.

---

## 3. O buraco conceitual

**Todo o monitoramento roda dentro da coisa monitorada.** O `monitorar-canais.sh` é bom e cobre seis
sinais de liveness — mas se a máquina morre, ele morre junto, e o silêncio fica indistinguível de
"está tudo bem". Falta um vigia **de fora**.

---

## 4. O plano

Ordenado por retorno, não por dificuldade. Nada iniciado.

### Bloco B0 — tirar a receita da máquina do escritório *(o mais valioso; independe do domínio)*

| # | Item | Repo | Esforço | Por que |
|---|---|---|---|---|
| **B0.1** | ⬜ **`api.flashcapital.com.br` → Railway** (CNAME na zona que já existe; `www.`/`app.`/`internal.` já moram lá — ADR-0002) | monorepo | 1 h | é o nome estável para onde o webhook vai apontar |
| **B0.2** | ⬜ **Repontar `sms_url` e `status_callback`** do `+553123916846` para `api.flashcapital.com.br` no console da Twilio | monorepo | 15 min | **medido**: hoje apontam para o ngrok desta máquina. Enquanto não mudar, queda de escritório = confirmação de sacado quebrada |
| **B0.3** | ⬜ Conferir que `SUPABASE_PUBLIC_URL` está **ausente** (ou igual a `SUPABASE_URL`) no Railway | monorepo | 15 min | herdar o valor de dev reescreve a URL da mídia para `localhost:54321` → Twilio **63019** |
| **B0.4** | ⬜ Tirar do `tuneis-manha.sh` o `:8001`, o `:54321` **e o `:3001`** — os três do `ENV_MAP` (`:79-82`), mais a escrita no console da Twilio | monorepo | 30 min | depois de B0.2, deixar o script rodando **desfaz** o B0.2 toda manhã |

> ⚠️ **B0.4 não é limpeza, é correção — e o `:3001` é o mais perigoso dos três.**
> 1. O `tuneis_twilio.py` **escreve** o webhook no console da Twilio a cada rodada — e desde
>    2026-09-04 escreve nos **dois** recursos (`IncomingPhoneNumber` e o **WhatsApp Sender**, que é o
>    que vale para `whatsapp:`). Sem desligá-lo, o próximo `tuneis-manha.sh` devolve o webhook de
>    produção para o ngrok, em silêncio. O desligamento **já existe**: `TUNEIS_TWILIO=conferir` faz o
>    script conferir e gritar sem escrever — é o modo a adotar quando a produção for dona do número.
> 2. O `ENV_MAP` reescreve `CENTRAL_URL_PUBLICA` no `.env` do inbox **e recria `chatwoot-web` +
>    `chatwoot-sidekiq`** (`:223-226`). Como esse valor vira o `FRONTEND_URL` do Chatwoot, a central de
>    **produção** trocaria o hostname estável da Cloudflare por uma URL de ngrok que morre no dia
>    seguinte — levando junto o `status_callback` que ela anexa em todo envio (o 21609 do AD-11.1).

### Bloco R — retomada automática *(independe do domínio — pode começar hoje)*

| # | Item | Repo | Esforço | Por que |
|---|---|---|---|---|
| **R1** | ⬜ **Autostart do WSL2** — tarefa `WSL-Always-On` no Agendador do Windows, ancorando a VM com `sleep infinity`. Procedimento completo, com o comando de reverter: **`docs/runbook-wsl-autostart.md`** | — | 15 min | é o elo que falta. Sem ele, "ligada 24h" é intenção, não disponibilidade |
| **R2** | ⬜ **Nobreak** | — | compra | o valor não é aguentar horas: é sobreviver a piscadas, que são a causa mais frequente. E dá tempo de desligamento limpo |
| **R3** | ⬜ **Backup fora da máquina** — cópia cifrada (`age`/`gpg`) do `BACKUP_DIR` para storage externo, no fim do `backup.sh` | inbox | 2 h | hoje o backup grava **no mesmo disco**. Um `ext4.vhdx` corrompido leva backup e produção juntos. Já prometido em `runbook-backup.md`, nunca feito |
| **R4** | ⬜ **`scripts/retomar.sh`** — recebe a data da queda, roda `compose ps` + monitor + verificadores, dispara a reconciliação de status e o backfill de e-mail, e no fim **diz o que ficou irrecuperável** | inbox | 3 h | hoje a sequência existe na cabeça de quem lembra |
| **R5** | ⬜ **Teste de queda real**: reiniciar o Windows e provar, sem logar em nada, que a central voltou e o cron disparou | — | 30 min | R1 sem teste é suposição |

### Bloco F — acabar com o buraco permanente *(o de maior retorno; independe do domínio)*

| # | Item | Repo | Esforço | Por que |
|---|---|---|---|---|
| **F1** | ⬜ **Fila de reenvio no espelho.** Em vez de logar e descartar, persistir a chamada que falhou (tabela `internal.espelho_pendente`: payload, tentativas, último erro) e drenar por task do worker com backoff | monorepo | 1–2 dias | **repeala o AD-12 nesta direção**: "buraco permanente" vira "atraso". É o único item que muda a classificação do painel de *amostral* para *completo* |
| **F2** | ⬜ **Persistir o corpo do inbound** no monorepo | monorepo | 4 h | dívida já registrada: hoje o corpo é usado para a confirmação e **descartado**. Sem ele, F1 não tem o que reenviar do inbound — só na Twilio e no aparelho do cliente |
| **F3** | ⬜ **Asserção anti-"login HTML 200"** no espelho: checar `content-type` (ou header `cf-access-*`), não só `raise_for_status()`. **Nos TRÊS pontos**: `relay_inbound` (`chatwoot_mirror.py:288`) e também `_get` (`:405`) e `_post` (`:415`), por onde passam `mirror_outbound` e `_carimbar_atributos` | monorepo | 1 h | **pré-condição de pôr o Access na frente.** Access mal configurado devolve login em HTML com **200**, o espelho passa e acha que entregou. Corrigir só o `relay_inbound` deixaria o **outbound** com o mesmo defeito e o item marcado como pronto |
| **F4** | ⬜ **Idempotência do replay** — confirmar que reenviar o mesmo `MessageSid` no `/twilio/callback` não duplica a mensagem na central | inbox | 2 h | F1 sem isso troca "perder" por "duplicar" |

### Bloco V — vigia externo *(depende do domínio + Cloudflare)*

| # | Item | Esforço | Por que |
|---|---|---|---|
| **V1** | ⬜ **Notificação de Tunnel Health** da Cloudflare por e-mail | 10 min | o túnel morre exatamente quando a máquina morre. É o **único** alerta que vem de fora, e vem de graça |
| **V2** | ⬜ Revisar o horário dos 4 crons para a janela do host definitivo | 15 min | o `04:10` foi escolhido para uma máquina de expediente |

---

## 5. Ordem sugerida

```
PRIMEIRO ─────────────────────────────────────────────────────────────
  B0.1 → B0.2 → B0.3 → B0.4   mover a fronteira pública para o Railway
                              enquanto isso não acontece, todo o resto
                              protege o painel e deixa a RECEITA exposta

depois, e ainda sem domínio ──────────────────────────────────────────
  R1  autostart          15 min, mata o pior modo de falha restante
  R5  teste de queda     prova o R1
  F3  asserção do Access 1 h, e é pré-condição da Fase 4
  R3  backup off-site    a lacuna mais séria do arranjo local

quando houver folga ──────────────────────────────────────────────────
  F2 → F1 → F4           a fila; é o que muda a natureza do painel
  R4  retomar.sh

com o domínio ────────────────────────────────────────────────────────
  V1  Tunnel Health
  V2  horário dos crons
```

**O B0 vem antes de tudo, e a ordem importa: `B0.2` sem `B0.4` se desfaz sozinha** na manhã seguinte,
quando o `tuneis_twilio.py` reescrever o `SmsUrl` de volta para o ngrok.

Depois dele, **R1 e F3** são os que eu não deixaria para depois. O primeiro custa 15 minutos e responde
sozinho pela maior parte do risco de indisponibilidade restante. O segundo é barato agora e caro
depois: se o Access entrar antes dele, o espelho passa a mentir que entregou — em silêncio.

---

## 6. O que este plano não resolve

- **Internet do escritório fora, máquina de pé.** O `cloudflared` reconecta sozinho, o Chatwoot
  continua rodando e o e-mail se recupera; mas o espelho fica cego até voltar — que é exatamente o
  que o F1 endereça. Nenhuma configuração de rede substitui a fila.
- **Perda de dado já ocorrida antes do F1.** O que se perdeu, perdeu. Reconstruir o passado exigiria
  varrer a Messages API da Twilio por janela — possível, mas é projeto separado e não está previsto.
- **Disponibilidade real de escritório.** Ligada 24h com nobreak e autostart ainda é menos disponível
  que uma VPS. O plano reduz o custo de cada queda; não reduz a frequência delas. Essa parte é a
  decisão de *onde executar*, e ela segue reversível (`docs/fase-4-premissas.md` §1).
