# Runbook — o WSL sobe com o Windows, sem ninguém abrir terminal

> **O que este documento resolve:** a stack roda dentro do WSL2. A VM do WSL **desliga quando o
> último processo dela termina** — fechar o terminal é desligar o servidor. Este runbook ancora a VM
> no boot do Windows, e diz como desfazer.
>
> É o item **R1** de `docs/plano-resiliencia.md`. Tudo aqui é configuração **da máquina**, não do
> repositório: nada disto entra em `compose.yaml` ou em `scripts/`.

> ⚠️ **Leia primeiro a seção "Quem ancora é o systemd, não a tarefa", no fim.** A tarefa do Windows
> sozinha **não** mantém a máquina de pé: ela dispara no logon e só. Quem ancora é
> `wsl-ancora.service`.

## O que já está pronto do lado Linux

Medido e correto:

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

Ela cobre "o Windows reiniciou". Não cobre o resto da cadeia:

| Falha | O que fazer | Onde |
|---|---|---|
| Faltou luz e o PC não religou | **Restore on AC Power Loss = Power On** | BIOS/UEFI |
| Religou e parou na tela de login | **login automático** — ver a seção abaixo | Windows |
| O PC dormiu sozinho | `powercfg /change standby-timeout-ac 0` e `powercfg /change hibernate-timeout-ac 0` | PowerShell admin |

**Windows Update não entra nessa lista, e é bom entender por quê.** Em 09/09/2026 ele reiniciou a
máquina duas vezes às 02:39 e 02:41, e o Linux ficou **9 h 41 min** fora. A tentação é configurar
"horário ativo" para adiar o reinício — **não resolve.** O reinício já foi às 02:39, fora de qualquer
expediente: o horário ativo teria **aprovado** aquele reboot. O problema nunca foi *quando* a máquina
reinicia; é que depois de reiniciar **ninguém loga**. Quem conserta isso é o login automático, e ele
conserta a queda de luz junto. Adiar patch numa máquina que termina webhook de produção seria troca
ruim de qualquer jeito.

## Login automático — o procedimento que funciona

Fechado em 09/09/2026 (item **R5.1** do plano de resiliência). Resultado medido: **4 segundos** entre
o `6005` do Windows e o `7001` do logon, sem ninguém tocar no teclado; **19 segundos** do boot frio até
os 25 containers de pé.

⚠️ **Não remova o PIN antes de ter uma senha comprovadamente boa.** Enquanto só o PIN funciona, ele é
a única chave da máquina que hospeda a central, o `.env` e o backup.

1. *Contas → Opções de entrada* → **desligar** "Para maior segurança, permita apenas a entrada do
   Windows Hello para contas da Microsoft" (põe `DevicePasswordLessBuildVersion` em `0`).
2. Baixar o **Autologon** da Sysinternals e rodar como admin com a forma **explícita de conta
   Microsoft** — o nome local **não** serve:
   ```
   Username : <email da conta Microsoft>
   Domain   : MicrosoftAccount
   Password : a senha da CONTA MICROSOFT (não o PIN)
   ```
3. Reiniciar. A área de trabalho tem de aparecer sem você encostar em nada.

**Por que não `netplwiz`:** com conta Microsoft ele grava `AutoAdminLogon=1` e deixa o
`DefaultUserName` **vazio** — o Winlogon não sabe em qual conta logar e cai na tela de login.

**Por que a senha "certa" era recusada:** o que se digita no dia a dia é o **PIN**, não a senha.
`LastLoggedOnProvider = {D6886603-9D2F-4EB2-B667-1971041FA96B}` é o **NGC Credential Provider**
(Windows Hello). O PIN é local do aparelho, guardado no TPM, e não pode ser reproduzido como senha.
Quem só usa PIN há anos costuma não ter a senha real à mão — redefina em `account.microsoft.com` e
**entre uma vez com ela nesta máquina** (bloquear → *Opções de entrada* → senha) antes de configurar,
senão o cache local segue com a antiga.

**Dois diagnósticos que economizam reboots:**

- Se a senha estivesse errada, o Windows **zera** o `AutoAdminLogon` para não entrar em loop.
  Continuar em `1` depois de um boot que parou no login prova que ele **nem tentou** — é
  `DefaultUserName` vazio, não senha.
- O Autologon **valida** a credencial (foi ele que recusou a combinação com o nome local). Logo,
  "successfully configured" quer dizer **aceita**, não apenas gravada.

**Conferir depois:** `AutoLogonCount` tem de estar **ausente** no `Winlogon`. Se existir, o autologon
vale só N vezes e para sozinho — funciona no teste e falha semanas depois.

> **A senha fica cifrada nos LSA secrets** — recuperável por quem tem admin na máquina. É troca
> consciente de segurança física da sala. Mitigação que não custa disponibilidade: bloqueio por
> ociosidade (`control desk.cpl,,@screensaver` → 15 min → marcar *"Ao reiniciar, exibir tela de
> logon"*). **Bloquear não desloga** — a sessão continua viva, com WSL, Docker e os containers de pé.

## Conferir que valeu

Depois de um reboot **sem abrir terminal nenhum**, entre no WSL e confira:

```bash
uptime                                    # tem de bater com o boot do Windows
systemctl is-active wsl-ancora.service    # a âncora, não o cron
docker compose ps                         # containers de pé
systemctl list-timers 'central-*'         # e a coluna LAST preenchida
```

E o número que fecha o item, do lado Windows — a diferença tem de ser de **segundos**:

```powershell
Get-WinEvent -FilterHashtable @{LogName='System'; Id=6005} -MaxEvents 1 | Select TimeCreated   # boot
Get-WinEvent -FilterHashtable @{LogName='System'; Id=7001} -MaxEvents 1 | Select TimeCreated   # logon
```

É o item **R5** do plano de resiliência: R1 sem esse teste é suposição, não disponibilidade.

## Quem ancora é o systemd, não a tarefa

**A tarefa do Windows só SOBE a distro no logon. Quem a mantém viva é uma unidade do systemd**,
`wsl-ancora.service`, com `Restart=always`. A divisão importa:

| | Faz | Não faz |
|---|---|---|
| Tarefa `WSL-Always-On` (Windows) | acorda a distro quando você loga | não segura nada depois; dispara `-AtLogOn` e só |
| `wsl-ancora.service` (systemd) | mantém a VM viva **em toda subida da distro**, com ou sem logon, e volta sozinha se morrer | não liga a máquina |

### Por que não bastava a tarefa

Medido em 2026-09-04: a tarefa foi criada e provada de manhã; à tarde a VM tinha **5 h de uptime,
25 containers e zero âncora**. Um `wsl --shutdown` no meio do dia derrubou a âncora, e ela não
voltou porque **não houve novo logon**. O estado engana — máquina de pé, tudo verde — mas segurada
só pelo terminal que estivesse aberto.

E a tarefa, do jeito que está, **abre uma janela**: o `sleep` dela fica preso a um `pts`. Fechar a
aba mataria aquela âncora. Com a unidade no lugar, **a aba pode ser fechada**.

### Por que systemd, e não `setsid`/`nohup` disparado pela tarefa

Testado no mesmo dia, três variantes: **o WSL mata a árvore de processos da invocação de interop
quando o `wsl.exe` sai.**

| Tentativa | Resultado |
|---|---|
| `sh -c 'setsid sleep infinity &'` | ✗ morreu junto |
| `bash -c 'nohup ... & disown'` | ✗ morreu junto |
| `systemd-run --unit=… sleep infinity` | ✓ **sobreviveu** |

A unidade sobrevive porque quem a possui é o **PID 1**, não a invocação.

### A unidade

`/etc/systemd/system/wsl-ancora.service` — `ExecStart=/bin/sleep infinity`, `Restart=always`,
`WantedBy=multi-user.target`. Custo: um processo dormindo, sem CPU.

```bash
systemctl status wsl-ancora              # conferir
sudo systemctl disable --now wsl-ancora  # reverter (a VM volta a depender de terminal aberto)
sudo systemctl enable  --now wsl-ancora  # religar
```

**Provado ao vivo:** `kill -9` na âncora → `NRestarts=1` e pid novo em ~1 s.

O `monitorar-canais.sh` cobra `systemctl is-active wsl-ancora` de hora em hora (sinal 7) e avisa no
sino do Nexus. Ele **não** cobre a VM já desligada — aí nada roda, inclusive ele. Cobre a janela em
que ela está viva e frágil, que é quando ainda dá para agir.

