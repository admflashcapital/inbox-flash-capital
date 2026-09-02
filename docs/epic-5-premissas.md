# EPIC-5 — Premissas, requisitos e dívida a resolver antes de construir

> Levantamento feito em 2026-07-14 **lendo os três repos e medindo os bancos reais**, antes de
> escrever qualquer linha do Serviço de Sync. Nada aqui é suposição: cada número foi contado, cada
> formato foi verificado, cada arquivo citado foi lido.
>
> Este doc **não** substitui `architecture.md` (AD-1..AD-9) nem `epics-and-stories.md` (as 5 stories).
> Ele responde: *o terreno aguenta o que a gente projetou?*

---

## Veredito em uma linha

**A regra do AD-3 (merge automático só com telefone E documento) é viável — 76% dos sacados e 60% dos
cedentes têm as duas chaves.** Mas o EPIC-5 **não é só deste repo**: os dois domínios **não empurram
evento nenhum hoje**, e construir esses emissores é pré-requisito, em código dos *outros* repos.

---

## 1. O que foi medido (não estimado)

### Supabase (monorepo) — a fonte de cedente/sacado/cobrança

| Tabela | Total | Com documento | Com telefone | **Com os DOIS** |
|---|---|---|---|---|
| `internal.cedentes` | 110 | 110 (100%) | 66 | **66 (60%)** |
| `internal.sacados` | 2.153 | 2.153 (100%) | 1.644 | **1.644 (76%)** |

**Formato — e a boa notícia do levantamento:**

- **Telefone:** os 1.644 estão **todos no mesmo padrão** — `55DDDNUMERO`, 13 dígitos, **sem `+`**.
  Virar E.164 é prefixar `+`. Zero sujeira.
- **Documento:** **só dígitos, sem máscara**, comprimento 11–14.

**A coluna se chama `cnpj`, mas guarda CPF também:**

| Tipo | Quantidade |
|---|---|
| CNPJ (14 dígitos) — pessoa jurídica | 1.743 |
| **CPF (11 dígitos) — pessoa física** | **410 (19%)** |

### Twenty (CRM) — a fonte de lead

Não está no ar; o schema foi lido em `scripts/seed_pipeline.py` (não há migrations — o schema é
código-como-seed, criado via metadata API GraphQL).

- **Objetos padrão (Person/Company) estão DESATIVADOS.** Só existe o custom object **`lead`**, que é
  empresa + contato **achatados numa entidade só**.
- **Telefone** — campo `responsavelTelefone`, tipo composto `PHONES`. **Guardado PARTIDO:**
  `primaryPhoneNumber` = `31999998888` (nacional, **sem DDI**) + `primaryPhoneCallingCode` = `+55`.
  O E.164 só existe **em trânsito** (`scripts/identificacao.py:40-57`).
- **Documento** — campo custom `cnpj`, tipo `TEXT`, **MASCARADO** (`XX.XXX.XXX/XXXX-XX`).
  `scripts/cnpj.py:22-31` sabe normalizar, **mas não é aplicado na escrita**.
- **CPF NÃO EXISTE no Lead.** Só como `devedorSolidarioCpf` no objeto `Contrato`.
- **Nada é NOT NULL e nada é UNIQUE** (`grep isNullable/isUnique` = zero). A doc do CRM afirma
  `cnpj text NOT NULL unique` — **isso é intenção, não as-built. Não confie.**

### Os três formatos de telefone que o Sync vai ter que conciliar

| Sistema | Como guarda | Exemplo (fictício) |
|---|---|---|
| Supabase | dígitos com DDI, sem `+` | `5531999998888` |
| Twenty | **partido** (nacional + calling code) | `31999998888` + `+55` |
| Chatwoot | **E.164** | `+5531999998888` |

---

## 2. A dívida que BLOQUEIA o EPIC-5

### 🔴 B-1. Nenhum dos dois domínios empurra evento. O AD-2 não existe na prática.

O AD-2 diz: *"o domínio empurra; a central nunca consulta em runtime"*. Hoje **ninguém empurra**.

**Twenty:** os **webhooks de saída estão QUEBRADOS** neste setup — bug de cache `flatWebhookMaps` no
v2.12, documentado em `crm/docs/02_Arquitetura.md:21`. O Plano B é **polling**: o
`WF-01-001_poll_twenty_leads` consulta a records API a cada 2 min. Mas:
- ele está **`"active": false`**;
- ele **termina num Code node e não notifica ninguém**;
- e a query dele **não traz `cnpj`, `telefone` nem `email`** — só `id, razaoSocial, etapa, status,
  updatedAt`. **O payload atual não carrega as chaves de identidade.**

**Monorepo:** **não existe outbox, trigger de auditoria nem publish.** O status de cobrança muda em
`api/repositories/boletos_itau_repository.py:186` (`upsert_from_itau`) e ninguém é avisado.

**Consequência:** o EPIC-5 exige **código nos outros dois repos**:
- no CRM: estender o `WF-01-001` (campos de identidade na query + nó HTTP → Sync), ou um workflow novo;
- no monorepo: um emissor na transição de estado do boleto (o lugar mais barato é dentro do
  `upsert_from_itau`, detectando `aVencer` → `vencido`).

Isso **não estava dimensionado** nas 5 stories do EPIC-5. É trabalho novo, e é fora deste repo.

### 🔴 B-2. `dias_atraso` e `valor_em_aberto` NÃO EXISTEM no domínio

O gate do EPIC-5 exige empurrar os atributos `cnpj`, `status_operacao`, `dias_atraso`,
`valor_em_aberto`. Os dois últimos **não existem em lugar nenhum** para títulos/cobrança (só há
homônimos em *debêntures*, domínio não relacionado). Precisam ser **derivados**:

- `dias_atraso` ← `hoje − boletos.data_vencimento`, para os vencidos
- `valor_em_aberto` ← `boletos.valor − boletos.valor_pago`, filtrando `status = 'vencido'`

**Isso é regra de negócio nova, e precisa do seu aval** — não é decisão de engenharia.

### 🔴 B-3. `status_operacao` não tem vocabulário canônico

Existem **dois** vocabulários, e nenhum bate com o dicionário fechado de labels do PRD:

| Fonte | Valores |
|---|---|
| `internal.boletos.status` | `aVencer` / `vencido` — **cru da API do Itaú** |
| `public.operacao_desconto.operation_status` | outro vocabulário |
| Twenty `lead.etapa` | `PROSPECCAO` → `PRE_ANALISE` → `ANALISE_CREDITO` → `NEGOCIACAO_FINAL` → `CONTRATO_GERADO` / `PERDIDO` |
| **Labels do PRD (dicionário FECHADO)** | `lead-frio`, `lead-qualificado`, `cliente-ativo`, `em-cobranca`, `regua-etapa-N`, `inadimplente`, `nao-identificado` |

**Falta o mapa entre eles.** É decisão de negócio, não de código. Sem ele, a STORY-5.3 (push de labels)
não tem o que empurrar.

---

## 3. Os dois buracos que a regra do AD-3 não cobre (e é preciso aceitar de olhos abertos)

### ⚠️ F-1. Leads de WhatsApp **nunca** darão merge automático

O `WF-04-002_identificacao_lead_telefone` **cria um Lead novo a cada número desconhecido**, gravando
**só** `etapa`, `origem=WHATSAPP`, `responsavelTelefone` e talvez o nome. **Sem CNPJ, sem e-mail.**

Ou seja: o canal que **mais gera duplicata** é exatamente o que a regra (telefone **E** documento)
**não** resolve sozinha. Todos vão para a **fila de sugestão** (`pending`).

Isso está **correto** por AD-3 — mas significa que a fila de sugestões será alimentada
majoritariamente por leads de WhatsApp, e **alguém vai ter que trabalhá-la**. Se ninguém trabalhar, a
duplicata continua, só que agora com um `pending` pendurado. **É requisito de operação, não de código.**

### ⚠️ F-2. 410 sacados são pessoa física (CPF) e **não têm contraparte no Twenty**

O Lead do Twenty só tem `cnpj`. Os 410 sacados com CPF (19%) **jamais** casarão com um Lead.

Provavelmente é aceitável — o Twenty cuida de **lead/cedente** (pessoa jurídica) e o sacado vive no
Supabase. Mas **precisa ser dito explicitamente**, senão vira bug-fantasma: "por que esse contato
nunca enriquece?"

---

## 4. O achado que simplifica tudo: o Chatwoot já tem chave única

```
uniq_identifier_per_account_contact  (identifier, account_id) UNIQUE   ← índice ÚNICO no banco
uniq_email_per_account_contact       (email, account_id)      UNIQUE
```

O `Contact` do Chatwoot tem um campo **`identifier`** com **índice único de verdade, no Postgres**
(não só validação de model).

**Proposta de desenho:** o Sync grava `identifier = documento normalizado (só dígitos)`.
Consequência: **o próprio banco impede dois contatos com o mesmo documento.** A deduplicação deixa de
ser lógica de aplicação e vira **garantia de integridade** — a corrida entre dois eventos simultâneos
não consegue criar duplicata nem em teoria.

`email` também é único por conta. `phone_number` **não** tem índice único no banco (só validação de
model, `contact.rb:54-55`) — então **não dá** para confiar nele como chave forte.

> Isto ainda **não** é uma decisão travada. É a melhor alavanca que o levantamento encontrou, e vira
> um AD novo se você aprovar.

---

## 5. Reuso: o que já existe e não deve ser reescrito

| O quê | Onde | Observação |
|---|---|---|
| Cliente HTTP autenticado do Chatwoot | `monorepo: api/integrations/chatwoot/chatwoot_mirror.py:240-261` | `httpx`, header `api_access_token`. **Reuse o cliente.** |
| Find-or-create de contato | idem, `_garantir_contato`, :204-220 | É o **esqueleto** do resolver — mas busca **só por telefone**, pega o **primeiro hit** (`achados[0]`) sem desempate e **não escreve `custom_attributes`**. Serve de base, não de solução. |
| Normalização de telefone para E.164 | `monorepo: common/phone.py:10-28` (`to_e164_br`) | **A correta**, stdlib-only. Recusa-se a adicionar o "9" cegamente. |

**NÃO reuse:**
- `worker/etl/.../transformers.py:151-176` (`normalizar_telefone`) — **adiciona o "9" cegamente** em
  números de 8 dígitos, corrompendo telefone **fixo**. E arrasta pandas.
- A **política de erro** do `chatwoot_mirror` (engole tudo e vira `False`). Correta para espelho de
  cobrança; **errada** para sync de identidade — um merge falho passaria silencioso.

⚠️ **Risco herdado:** como o pipeline gravou os telefones com `normalizar_telefone`, um fixo de 8
dígitos **já pode ter sido corrompido em celular** na escrita. Medi: **todos os 1.644 têm 13 dígitos**
(= celular com o 9). Ou não há fixo na base, ou os fixos já foram corrompidos — **não dá para
distinguir a posteriori**.

---

## 6. Dívida herdada que respinga no EPIC-5

| Dívida | Impacto aqui |
|---|---|
| **`internal.confirmacoes_contatos` está VAZIA** | Seria a melhor fonte de telefone (documento+telefone `NOT NULL` nos dois, com `uso_count` para desempate). Está vazia **porque a confirmação de sacado nunca funcionou em produção** — o webhook do Twilio apontava para um túnel ngrok morto (dívida achada no EPIC-3). **Consertar aquilo enche esta tabela** e melhora a identidade. |
| **Espelho do monorepo não está na `main`** (`feat/espelho-chatwoot`) | O Sync vai querer reusar o cliente Chatwoot que vive nessa branch. Precisa de merge, ou o código nasce órfão. |
| **`/whatsapp-dispatch` sem autenticação** (`monorepo: api/api_main.py:256`) | Não bloqueia o EPIC-5, mas continua aberto e dispara **cobrança em massa**. |
| **Retenção LGPD sem cron** | Agora a central ingere PII real (canal de e-mail vivo). Vira bloqueador de go-live. |
| **Cross-DB proibido (AD-9)** | Confirmado no CRM: `CHATWOOT_IMPORT_DATABASE_CONNECTION_URI` foi **deliberadamente omitido**. O Sync fala **só por API**. Sem atalho por banco. |

---

## 7. Decisões que dependem de VOCÊ (não são de engenharia)

1. **Mapa `etapa`/`status` → labels do dicionário fechado.** Sem isso a STORY-5.3 não roda.
2. **Fórmula de `dias_atraso` e `valor_em_aberto`.** Proponho derivar de `boletos`; precisa do aval.
3. **Quem trabalha a fila de sugestões de merge?** Ela vai encher de lead de WhatsApp (F-1).
4. **Aceitar que os 410 sacados PF não enriquecem pelo Twenty** (F-2).
5. **Aprovar o `identifier = documento` como chave única** (§4) — vira AD novo.

---

## 8. Ordem sugerida de ataque

1. **Fechar o mapa de labels e as fórmulas** (decisões acima) — sem isso, metade das stories não tem
   requisito.
2. **Construir os emissores** (B-1): o workflow do CRM e o hook do monorepo. **É trabalho nos outros
   repos, e não estava nas 5 stories.**
3. **Aí sim** o `sync-service/` (5.1 → 5.5), com TDD, neste repo.
