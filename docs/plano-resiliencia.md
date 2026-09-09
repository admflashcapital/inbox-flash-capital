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

> **MEDIDO na API da Twilio (2026-09-03, reconfirmado em 2026-09-04).** O número de produção
> `+553123916846` tem inbound **e** status callback apontando para um túnel ngrok da **máquina do
> escritório** — o subdomínio muda todo dia, o destino não. O monorepo tem deploy no Railway e ele
> **envia** de lá, mas **a fronteira pública de VOLTA continua aqui**.
>
> Isso inverte a conclusão. Enquanto o webhook não mudar, **uma queda do escritório derruba o caminho
> do dinheiro**, não só o painel.
>
> ⚠️ São **dois** recursos na Twilio, e o do WhatsApp é o que decide: `IncomingPhoneNumber` governa
> SMS/voz, e o **WhatsApp Sender** governa o `whatsapp:`. Em 2026-09-04 eles estavam divergentes — o
> número no túnel do dia, o sender num de dois dias antes, morto. Ver
> `docs/runbook-canal-oficial.md`.

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

Ordenado por retorno, não por dificuldade. **B0.1 e R1 concluídos em 2026-09-04**; o resto não iniciado.

### Bloco B0 — tirar a receita da máquina do escritório *(o mais valioso; independe do domínio)*

| # | Item | Repo | Esforço | Por que |
|---|---|---|---|---|
| **B0.1** | ✅ **FEITO — já estava.** `api.flashcapital.com.br` é CNAME para `bps2k9e9.up.railway.app`; `GET /health` devolve 200 e os cabeçalhos são `server: railway-hikari`. Verificado em 2026-09-04 | monorepo | — | o nome estável para onde o webhook vai apontar **já existe** |
| **B0.2** | ⬜ **Repontar os DOIS recursos** do `+553123916846` para `api.flashcapital.com.br`: `IncomingPhoneNumber` (SMS/voz) **e o WhatsApp Sender** (`whatsapp:`, o que decide). ⚠️ **Bloqueado pelo merge**, não pela infra: a `main` tem a rota de inbound mas **não tem o espelho do Chatwoot** — repontar antes do merge pararia de popular o painel | monorepo | 15 min | **medido**: hoje apontam para o ngrok desta máquina. Enquanto não mudar, queda de escritório = confirmação de sacado quebrada |
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

> **📌 Medido no reboot de 2026-09-04, e é o argumento mais concreto deste bloco.** A máquina se
> recompôs sozinha — VM, âncora, 25 containers, 5 crons — **mas voltou sem túnel**. Os túneis são
> passo manual (`tuneis-manha.sh`), e enquanto o webhook de produção da Twilio apontar para cá, cada
> minuto entre o boot e alguém rodar o script é inbound de cliente caindo numa URL morta — buraco
> **permanente**, não atraso (AD-12). Um reboot às 3h vira 6 h de buraco.
>
> **Automatizar o túnel no boot NÃO é a saída**, e por dois motivos: o passo perigoso não é subir o
> túnel, é **escrever o webhook na Twilio** — que depois do merge passaria a sequestrar o inbound de
> produção em silêncio; e o AD-15 **apaga o mecanismo inteiro** (o `cloudflared` vira container com
> política de restart e hostname estável, sem URL diária, sem reescrita de `.env`, sem escrita na
> Twilio). Investir em automação aqui é investir no que já está marcado para demolição — item **2.8**
> do rastreio da Fase 4. A saída é este bloco B0.

### Bloco R — retomada automática *(independe do domínio — pode começar hoje)*

| # | Item | Repo | Esforço | Por que |
|---|---|---|---|---|
| **R1** | ✅ **FEITO em 2026-09-04**, em duas metades — a tarefa `WSL-Always-On` **acorda** a distro no logon, e a unidade **`wsl-ancora.service`** (`Restart=always`) a **mantém** viva. A tarefa sozinha não bastava: dispara `-AtLogOn` e só, então um `wsl --shutdown` no meio do dia derrubava a âncora sem volta. Procedimento e reversão: **`docs/runbook-wsl-autostart.md`** | — | 15 min | é o elo que falta. Sem ele, "ligada 24h" é intenção, não disponibilidade |
| **R2** | ⬜ **Nobreak** | — | compra | o valor não é aguentar horas: é sobreviver a piscadas, que são a causa mais frequente. E dá tempo de desligamento limpo |
| **R3** | ✅ **FEITO em 2026-09-04** — `scripts/backup-offsite.sh` cifra em AES256 (`gpg --symmetric`) e espelha no Supabase Storage por `rclone sync`, encadeado no backup (`Wants=central-offsite.service`). Credencial **escopada a storage** (S3 Access Keys), nunca a `service_role` (AD-9). Provado com restore **a partir do bucket**: as duas metades byte-a-byte idênticas ao original | inbox | 2 h | hoje o backup gravava **no mesmo disco**. Um `ext4.vhdx` corrompido levaria backup e produção juntos |
| **R3.1** | ✅ **FEITO em 2026-09-08** — os 4 jobs de dado saíram do cron e viraram **timers do systemd com `Persistent=true`** (`scripts/systemd/`, instalados por `sudo bash scripts/systemd/instalar.sh`). Hora perdida com a máquina desligada é executada na próxima subida; a ordem expurgo → backup → offsite → ensaio passou a ser garantida por `Before=`/`After=`, não pelo relógio; e `scripts/lib/aguardar-stack.sh` segura o job até o Docker responder, porque a recuperação dispara com o Desktop ainda subindo. O monitor **fica no cron** de propósito: sonda de liveness não se recupera | inbox | 2 h | **o backup não existia.** Medido no `syslog`: em três semanas, `monitorar-canais` teve 10 execuções e os outros quatro tiveram **zero** — `backup.log`, `backup-offsite.log` e `restore-verificar.log` sequer existiam. Cron não recupera hora perdida, e esta máquina vive das ~11h às ~19h e some no fim de semana |
| **R4** | ⬜ **`scripts/retomar.sh`** — recebe a data da queda, roda `compose ps` + monitor + verificadores, dispara a reconciliação de status e o backfill de e-mail, e no fim **diz o que ficou irrecuperável** | inbox | 3 h | hoje a sequência existe na cabeça de quem lembra |
| **R5** | 🟡 **PARCIAL — testado em 2026-09-04, e o resultado tem uma ressalva que importa.** Reboot real do Windows: a VM subiu, `wsl-ancora.service` ativo com `NRestarts=0`, **25 containers de volta**, os 4 da central `healthy`, **5 crons** registrados, e invariantes/operação/e-mail verdes. **O que NÃO foi provado, e era o enunciado do item:** "sem logar em nada". O gatilho da tarefa é `MSFT_TaskLogonTrigger` e o `AutoAdminLogon` do Windows está **vazio** — sem logon, o WSL não sobe e nada disso acontece. **E os túneis não voltam**: são passo manual (ver B0). | — | 30 min | R1 sem teste é suposição |
| **R5.1** | ⬜ **Fechar o "sem logar em nada"**: só o **login automático** resolve — ver abaixo por que a rota `-AtStartup` está descartada. ⚠️ Decisão de segurança física da sala, não técnica: a máquina guarda o `.env` com Twilio, `refresh_token` do Gmail, chave S3 e a frase do offsite | — | 15 min | **medido duas vezes, por duas causas diferentes.** (1) Corte de energia em 04/09 17:50 — 3 d 19 h parada, e o BIOS não tem *Restore on AC Power Loss*. (2) **Windows Update em 09/09 02:39 e 02:41** (`TrustedInstaller.exe` e `MoUsoCoreWorker.exe`, motivo "atualização (planejada)", com `6006` limpo nos dois) — o Windows voltou às 02:42 e o Linux só subiu às 12:23, no logon: **9 h 41 min com o PC ligado e o servidor morto**. Esta segunda causa é a que assusta: é mensal, e a máquina *parece* ligada |

> **Por que `-AtStartup` com credencial armazenada não serve** — medido em 09/09/2026. Uma tarefa
> "executar estando o usuário conectado ou não" roda na **sessão 0**, que é não interativa: ela não
> loga ninguém. E o **Docker Desktop é aplicativo de sessão de usuário** — não existe modo headless.
> A prova está no relógio do dia: o Windows subiu **02:42** e os containers só nasceram **12:32**,
> logo depois do logon das 12:23. Ou seja, essa rota levantaria o WSL e **não** levantaria os 25
> containers — resolveria a metade que não importa. Sobra o login automático.

> **E "horário ativo" do Windows Update também não serve.** Ele adia o *reboot*, não a atualização —
> mas o reboot de 09/09 já foi às **02:39**, fora de qualquer horário de trabalho. O horário ativo
> teria **aprovado** esse reboot. O problema nunca foi *quando* a máquina reinicia; é que depois de
> reiniciar **ninguém loga**.

> **Nota prática, para não perder 20 min:** a conta desta máquina é **MicrosoftAccount** e
> `HKLM\…\PasswordLess\Device\DevicePasswordLessBuildVersion = 2`, valor que **esconde** a caixa
> "Os usuários devem digitar um nome de usuário e senha" do `netplwiz`. Tem de ir a **0** antes, ou a
> caixa não aparece. E **bloquear a tela (`Win+L`) não desloga**: dá para ter login automático no boot
> *e* tela bloqueada por ociosidade — a sessão continua viva, com WSL, Docker e containers de pé. |

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
| **V2** | ✅ **sem objeto desde 08/09/2026** — timers com `Persistent=true` recuperam hora perdida, então o horário virou preferência, não aposta | — | o `04:10` era escolha para uma máquina de expediente que **nunca** estava acordada às 04:10 |

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
