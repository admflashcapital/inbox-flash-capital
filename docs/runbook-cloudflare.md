# Runbook — Cloudflare, primeira vez

> **Para executar quando o domínio novo estiver comprado.** Nada aqui foi feito ainda; nada aqui
> toca `flashcapital.com.br`. O objetivo do Passo 1 é **descobrir números**, não configurar: seis
> itens do plano gratuito que, se não couberem, mudam o desenho da Fase 4.
>
> **Contexto:** `docs/fase-4-premissas.md` (por que existe) · `deploy/ngrok-policy.yml` (a mesma
> especificação, na sintaxe de dev que morre aqui) · `docs/runbook-deploy.md` §Antes de expor.

## Vocabulário — são DOIS painéis, e confundi-los custa meia hora

| Painel | URL | O que mora nele |
|---|---|---|
| **Dashboard** (a *zona*) | `dash.cloudflare.com` | DNS, WAF/Custom Rules, Transform Rules, Notifications |
| **Zero Trust** | `one.dash.cloudflare.com` | Tunnels, Access (Applications, Policies), Service Auth |

Regra prática: **borda e tráfego** ficam no Dashboard; **identidade e túnel** ficam no Zero Trust.

---

## Passo 0 — pôr o domínio na Cloudflare

1. Criar conta em **dash.cloudflare.com** (grátis, e-mail + senha).
2. **+ Add** → **Connect a domain** → digitar o domínio novo → escolher o plano **Free**.
3. A Cloudflare devolve **dois nameservers** (`<nome>.ns.cloudflare.com`). Copiar os dois.
4. Trocar os NS **do domínio novo** no registrador:
   - `.com` comprado na GoDaddy → painel da GoDaddy, *Nameservers* → *Custom*.
   - `.com.br` → a troca acontece no painel do **Registro.br**, mesmo tendo sido comprado por
     revenda. Exige acesso ao CNPJ titular.
5. Esperar a zona ficar **Active** (minutos a horas; a Cloudflare avisa por e-mail).

> **Isto é risco zero.** O domínio novo não tem nada apontado para lugar nenhum — não há tráfego para
> quebrar, não há janela de propagação para temer. `flashcapital.com.br` não é tocado em momento
> algum: são duas zonas independentes, e a delegação de NS é por domínio.

⚠️ Ligar **auto-renovação** e conferir que o domínio está no CNPJ da empresa, não numa conta pessoal.
A partir da Fase 4 ele vira dependência de produção: domínio vencido derruba tudo de uma vez.

---

## Passo 1 — os seis números (só leitura, não configura nada)

Anotar o resultado de cada um. Dois deles podem mudar o desenho.

| # | Item | Onde clicar | Anotar |
|---|---|---|---|
| 1 | **Custom Rules** (WAF) | `dash` → domínio → **Security** → **WAF** → aba **Custom rules** → *Create rule* | o contador "X of **Y** rules used" |
| 2 | **Transform Rules** | `dash` → domínio → **Rules** → **Transform Rules** → **Modify Response Header** | mesmo contador |
| 3 | **Access — assentos** | `one.dash` → **Settings** → **Plans** | quantos usuários o free permite |
| 4 | **Service Auth / Bypass** ⚠️ | `one.dash` → **Access** → **Service Auth** → *Create Service Token*; depois **Access** → **Applications** → criar uma app de teste → **Policies** | (a) o token **cria**? (b) as *Actions* oferecem **Bypass** e **Service Auth**? |
| 5 | **Limite de tamanho de corpo** | não é tela — é atributo do plano, na doc de limites da Cloudflare | o número em MB |
| 6 | **Tunnels** | `one.dash` → **Networks** → **Tunnels** → *Create a tunnel* → tipo **Cloudflared** | quantos túneis/conexões o free permite |

### O que fazer se algum não couber

| Item | Se estourar |
|---|---|
| 1 · Custom Rules | juntar as regras numa expressão só (`or` entre paths) |
| 2 · Transform Rules | um único rule injetando os três headers |
| 3 · assentos | equipe de 2–8 pessoas; qualquer limite plausível é folga |
| **4 · Service Auth** | **não há contorno.** É o que deixa passar a máquina sem identidade humana — sem ele, a Fase 4 não fecha no plano gratuito |
| 5 · corpo | é ganho líquido: hoje **nada** impõe teto (requisito #4 do runbook-deploy) |
| 6 · túneis | **não** agrupar inbox e CRM num túnel só (AD-10 / ADR-010 proíbem o porteiro compartilhado, e não há rota entre os dois composes). Se o free só permitir um, o CRM fica de fora desta rodada |

**O item 4 é o único risco de verdade.** Traga a resposta dele antes de qualquer outra decisão.

---

## Passo 2 — o desenho alvo (para reconhecer as telas)

Não executar antes de fechar o Passo 1.

### 2.1 Tunnel — **um `cloudflared` por compose**, não um compartilhado

⚠️ **Não crie um túnel único servindo `inbox.` e `n8n.`.** Isso é exatamente o porteiro compartilhado
que o **AD-10** deste repo e o **ADR-010 #4** do CRM proíbem — foi o Caddy que a refatoração de setembro
apagou. Além de proibido, não funciona: os dois composes não compartilham rede, então um `cloudflared`
no compose do inbox **não tem rota** para o n8n.

```
compose do INBOX                       compose do CRM
  cloudflared ──▶ chatwoot-web:3000      cloudflared ──▶ n8n:5678
  inbox.<novodominio>                    n8n.<novodominio>
```

**São dois túneis, um por repo.** É por isso que o item 6 do Passo 1 (quantos túneis o free permite)
importa: se o limite for 1, o desenho muda.

⚠️ **O destino é o nome do container, não `localhost`.** Rodando dentro do compose, `localhost` é o
próprio `cloudflared`. O alvo é `http://chatwoot-web:3000` (e `http://n8n:5678` no CRM).

Conexão é **de dentro para fora**: sem port forward, sem IP fixo, sem mexer no roteador.

> `api.flashcapital.com.br` **não** entra aqui: a API está no Railway e resolve com um CNAME na zona
> antiga. Ver `fase-4-premissas.md` §2.1.

### 2.2 Access → **Applications** — dois furos, de naturezas diferentes

**Três** aplicações. A Cloudflare avalia a mais específica primeiro:

```
App 1  inbox.<dominio>/twilio/delivery_status  → Bypass          (a Twilio)
App 2  inbox.<dominio>/twilio/callback         → Service Auth    (o espelho)
       inbox.<dominio>/api/*                   → Service Auth    (o espelho)
App 3  inbox.<dominio>                         → Allow, e-mails da equipe
```

⚠️ **A Twilio precisa de Bypass, não de Service Auth.** Service Auth exige que o chamador mande
`CF-Access-Client-Id` e `CF-Access-Client-Secret`; a configuração de StatusCallback da Twilio aceita
**só uma URL**, sem headers. Pôr Service Auth ali devolve 403 em todo callback → a Twilio recusa o
envio com **21609** → a atendente para de responder pelo WhatsApp. Se quiser estreitar, estreite por
**IP** (faixas publicadas da Twilio), nunca por credencial.

⚠️ **O espelho não usa só `/twilio/callback`.** O outbound passa por `_get`/`_post` em
`/api/v1/accounts/{id}/contacts/search`, `/conversations` e nos atributos
(`chatwoot_mirror.py::_garantir_contato`, `_garantir_conversa`, `_carimbar_atributos`). Deixar `/api/*`
sob a App 3 faz o espelho receber a **página de login** e **nenhum disparo é espelhado** — em silêncio,
porque `_get` só chama `raise_for_status()` e a exceção do `.json()` cai no `except` largo.

O espelho **pode** mandar os headers de Service Auth: é código nosso. Por isso ele é Service Auth e a
Twilio é Bypass.

### 2.3 WAF → **Custom rules** — o que o Access não faz

O `/twilio/callback` do Chatwoot **não valida assinatura nenhuma**, e com o monorepo fora da máquina
o relay deixou de ser tráfego interno. Quem barra o resto do mundo é a App 2 do Access.

> **Não replique o `X-Relay-Token` numa expressão do WAF.** Seria uma **quarta cópia** do segredo
> (`.env` do inbox, `.env` do monorepo, header, e o painel da Cloudflare), rotacionada fora do `.env` —
> a mesma armadilha de "três cópias que precisam bater" que produziu o incidente 63019. O Service Auth
> da App 2 já faz esse papel, com credencial que a Cloudflare gerencia e rotaciona.

O WAF fica para o que é regra de tráfego, não de identidade — por exemplo a restrição de path do n8n
(`^/webhook(-test)?/` + catch-all 403) na zona do CRM.

### 2.4 Transform Rules → os headers que o Chatwoot não emite

`Rules` → `Transform Rules` → **Modify Response Header** → *Set static*:
`X-Content-Type-Options: nosniff` · `Referrer-Policy: strict-origin-when-cross-origin` ·
`X-Frame-Options: SAMEORIGIN`.

São os mesmos três do `deploy/ngrok-policy.yml`. **A sintaxe do ngrok morre; as regras vão.**

### 2.5 Notifications → o vigia externo

`dash` → clicar no **nome da conta** (não na zona) → **Notifications** → **Add** → evento de
**Tunnel Health** → e-mail.

O túnel morre exatamente quando a máquina do escritório morre. Este é o único alerta que vem **de
fora** — todo o resto do monitoramento roda dentro da coisa monitorada. Ver `docs/plano-resiliencia.md`.

---

## As três armadilhas, todas já medidas ou registradas

1. **Access mal configurado devolve a página de login em HTML com status 200.** O
   `raise_for_status()` do espelho **passa**, e ele conclui que deu certo — em `relay_inbound`
   (`chatwoot_mirror.py:288`) e igualmente em `_get` (`:405`) e `_post` (`:415`), que carregam o
   outbound. Sem retry nem backfill, vira buraco no painel, em silêncio. **Antes** de ligar o Access,
   o espelho precisa de asserção de `content-type` nos **três** pontos — `plano-resiliencia.md` §F3.
2. **Política de máquina tem de ser avaliada ANTES da de humano.** Exigir login no
   `/twilio/delivery_status` quebra a chamada da Twilio e traz o 21609 de volta.
3. **Um ngrok morto devolve 404, igual ao 404 legítimo do Rails.** Vale para qualquer borda: a prova
   de vida é `GET /api` devolver a **mesma versão** que o local, nunca "respondeu alguma coisa".
   É o que o `monitorar-canais.sh` já faz.

---

## O que trazer de volta

Depois do Passo 1, atualizar `docs/fase-4-premissas.md` §8 com os seis números reais, substituindo as
premissas. Só então planejar a execução.
