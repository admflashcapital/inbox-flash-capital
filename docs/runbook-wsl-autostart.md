# Runbook — o WSL sobe com o Windows, sem ninguém abrir terminal

> **O que este documento resolve:** a stack roda dentro do WSL2. A VM do WSL **desliga quando o
> último processo dela termina** — fechar o terminal é desligar o servidor. Este runbook ancora a VM
> no boot do Windows, e diz como desfazer.
>
> É o item **R1** de `docs/plano-resiliencia.md`. Tudo aqui é configuração **da máquina**, não do
> repositório: nada disto entra em `compose.yaml` ou em `scripts/`.

## O que já está pronto do lado Linux

Nada a fazer aqui — está medido e correto:

```
/etc/wsl.conf   → [boot] systemd=true
systemctl is-enabled docker cron   → enabled  enabled
compose.yaml    → restart: unless-stopped nos serviços de longa duração
```

Ou seja: **assim que a VM sobe, Docker, cron e os containers sobem sozinhos.** O elo que falta é só
manter a VM de pé.

## Por que a tarefa é assim, e não do jeito "óbvio"

Duas armadilhas medidas em 2026-09-04. As duas fazem a tarefa ser criada **e não funcionar**, que é
pior do que não criar.

**1. Não use `/ru SYSTEM`.** As distros do WSL são registradas **por usuário do Windows**:

```
HKCU\…\Lxss            (usuário flash) → Ubuntu-24.04
HKU\S-1-5-18\…\Lxss    (SYSTEM)        → a chave nem existe
```

Rodando como SYSTEM, o `wsl.exe` procura na colmeia do SYSTEM, não acha distro nenhuma e falha com
*"There is no distribution with the supplied name"*. A tarefa aparece como criada, o histórico
mostra execução, e a VM continua desligada.

**2. O comando tem de ficar vivo.** `wsl.exe -d Ubuntu-24.04 /bin/true` sobe a VM e **encerra no mesmo
instante** — a VM cai logo em seguida. O que ancora é um processo que não termina: `sleep infinity`.

## Criar a tarefa

PowerShell **como administrador**. Uma linha só:

```powershell
Register-ScheduledTask -TaskName "WSL-Always-On" -Force -Action (New-ScheduledTaskAction -Execute "C:\Windows\System32\wsl.exe" -Argument '-d Ubuntu-24.04 -u root -e sh -c "exec sleep infinity"') -Trigger (New-ScheduledTaskTrigger -AtLogOn -User "PC-FLASH01\flash") -Principal (New-ScheduledTaskPrincipal -UserId "PC-FLASH01\flash" -LogonType Interactive -RunLevel Highest) -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero))
```

Confira o nome da distro antes com `wsl -l -v` — o argumento `-d` tem de bater exatamente.

| Escolha | Por quê |
|---|---|
| `-AtLogOn` do usuário `flash` | é a colmeia onde a distro existe; dispensa guardar senha |
| `-LogonType Interactive` | sessão do usuário, onde o WSL funciona sem surpresa |
| `-ExecutionTimeLimit Zero` | sem isto o Windows mata a tarefa em 3 dias, e a VM cai junto |
| `-AllowStartIfOnBatteries` | o padrão **não roda na bateria** — num nobreak isso derruba tudo |

Testar sem reiniciar:

```powershell
Start-ScheduledTask -TaskName "WSL-Always-On"
Get-ScheduledTaskInfo -TaskName "WSL-Always-On" | Select-Object LastRunTime, LastTaskResult
```

`LastTaskResult` **267009** (`SCHED_S_TASK_RUNNING`) é o resultado **esperado e correto**: a tarefa
não termina de propósito. Um **0** aqui seria a má notícia — significaria que o comando saiu, e a VM
vai cair junto.

A prova que vale mais que o código de retorno é a âncora existir dentro do WSL:

```bash
pgrep -x sleep    # tem de devolver um PID
```

Medido em 2026-09-04: `LastTaskResult 267009` + `sleep infinity` vivo no PID do WSL.

## Desativar e reverter

```powershell
# 1. Pausar sem apagar (a tarefa continua cadastrada, mas não dispara mais)
Disable-ScheduledTask -TaskName "WSL-Always-On"

# 2. Voltar a valer
Enable-ScheduledTask -TaskName "WSL-Always-On"

# 3. Soltar a âncora AGORA, sem mexer no cadastro
Stop-ScheduledTask -TaskName "WSL-Always-On"

# 4. Remover de vez
Unregister-ScheduledTask -TaskName "WSL-Always-On" -Confirm:$false
```

`Disable` e `Unregister` **não derrubam** a VM que já está de pé — só impedem a próxima subida. Para
desligar na hora, depois do passo 3:

```powershell
wsl --shutdown
```

> ⚠️ `wsl --shutdown` mata os containers **sem** parada limpa. Se houver job em andamento, prefira
> `docker compose stop` dentro do WSL antes.

## O que a tarefa NÃO resolve

Ela cobre "o Windows reiniciou". Não cobre o resto da cadeia — e sem estes quatro, "ligada 24h"
continua sendo intenção:

| Falha | O que fazer | Onde |
|---|---|---|
| Faltou luz e o PC não religou | **Restore on AC Power Loss = Power On** | BIOS/UEFI |
| Religou e parou na tela de login | login automático (`netplwiz` → desmarcar *"Os usuários devem digitar…"*) | Windows |
| Windows Update reiniciou de madrugada | definir **horário ativo** cobrindo a janela dos crons (04h–06h) | Windows Update |
| O PC dormiu sozinho | `powercfg /change standby-timeout-ac 0` e `powercfg /change hibernate-timeout-ac 0` | PowerShell admin |

> O login automático guarda a senha da conta como segredo da LSA. É uma troca consciente: sem ele,
> uma queda de luz de madrugada só se resolve com alguém indo até a máquina.

## Conferir que valeu

Depois de um reboot **sem abrir terminal nenhum**, entre no WSL e confira:

```bash
uptime                       # deve bater com o boot do Windows, não com a hora que você abriu
systemctl is-active docker cron
docker compose ps            # containers de pé
tail -3 backups/monitor-canais.log
```

É o item **R5** do plano de resiliência: R1 sem esse teste é suposição, não disponibilidade.

## ⚠️ A tarefa dispara no LOGON — e só

Esta é a limitação que mais importa saber, porque ela falha **em silêncio**.

O gatilho é `-AtLogOn`. Se a VM do WSL cair no meio do dia — um `wsl --shutdown`, um
`docker` que trava, um upgrade —, a âncora morre junto e **não volta sozinha**: não há novo
logon. A partir daí a máquina fica num estado enganoso — de pé, containers rodando, tudo
verde — mas segurada apenas pelo terminal que estiver aberto. Fechou o terminal, cai tudo:
os 25 containers e os cinco crons.

**Medido em 2026-09-04.** A tarefa foi criada e provada de manhã; à tarde a VM tinha 5 h de
uptime e **zero** âncora. Só apareceu porque alguém foi olhar.

**Por isso o `monitorar-canais.sh` ganhou o sinal 7**, que roda de hora em hora e avisa no
sino do Nexus: `pgrep -x sleep` vazio ⇒ falha. Ele **não** cobre a VM já desligada — aí nada
roda, inclusive ele. Cobre a janela em que ela está viva e frágil, que é quando ainda dá
para agir.

Para religar sem reiniciar o Windows, no PowerShell:

```powershell
Start-ScheduledTask -TaskName "WSL-Always-On"
```

E para conferir de dentro do Linux:

```bash
pgrep -x sleep && echo "ancorada" || echo "SEM ÂNCORA — a VM morre com o último terminal"
```

