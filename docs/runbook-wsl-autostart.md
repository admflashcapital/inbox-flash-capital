# Runbook — o WSL sobe com o Windows, sem ninguém abrir terminal

> **O que este documento resolve:** a stack roda dentro do WSL2. A VM do WSL **fica de pé enquanto
> houver pelo menos um cliente do Windows conectado a ela** e desliga ~15 s depois que o último sai —
> fechar o último terminal é desligar o servidor. Este runbook ancora a VM no logon do Windows, e diz
> como desfazer.
>
> É o item **R1** de `docs/plano-resiliencia.md`. Tudo aqui é configuração **da máquina**, não do
> repositório: nada disto entra em `compose.yaml` ou em `scripts/`.

> ⚠️ **A âncora é a janela `C:\Windows\System32\wsl.exe` que a tarefa abre no logon. Ela fica
> aberta — minimize, nunca feche.** Nada dentro do Linux segura a VM. Leia a seção "Quem ancora é a
> janela da tarefa", no fim.

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
| `-LogonType Interactive` | sessão do usuário, onde o WSL funciona sem surpresa — é também o que faz a janela aparecer |
| `-ExecutionTimeLimit Zero` | sem isto o Windows mata a tarefa em 3 dias, e a VM cai junto |
| `-AllowStartIfOnBatteries` | o padrão **não roda na bateria** — num nobreak isso derruba tudo |

O único gatilho é o de logon, de propósito (ver "O que não se usa", no fim).

Testar sem reiniciar:

```powershell
Start-ScheduledTask -TaskName "WSL-Always-On"
Get-ScheduledTaskInfo -TaskName "WSL-Always-On" | Select-Object LastRunTime, LastTaskResult
```

`LastTaskResult` **267009** (`SCHED_S_TASK_RUNNING`) é o resultado **esperado e correto**: a tarefa
não termina de propósito. Um **0** aqui seria a má notícia — significaria que o comando saiu, e a VM
vai cair junto.

A prova que vale mais que o código de retorno é o `sleep` da tarefa existir dentro do WSL:

```bash
pgrep -u root -fx 'sleep infinity'    # tem de devolver um PID
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
| Alguém fechou a janela da tarefa, ou rodou `wsl --shutdown` | `Start-ScheduledTask -TaskName "WSL-Always-On"` | PowerShell |

**Windows Update não entra nessa lista, e é bom entender por quê.** Em 09/09/2026 ele reiniciou a
máquina duas vezes às 02:39 e 02:41, e o Linux ficou **9 h 41 min** fora. A tentação é configurar
"horário ativo" para adiar o reinício — **não resolve.** O reinício já foi às 02:39, fora de qualquer
expediente: o horário ativo teria **aprovado** aquele reboot. O problema nunca foi *quando* a máquina
reinicia; é que depois de reiniciar **ninguém loga**. Quem conserta isso é o login automático, e ele
conserta a queda de luz junto. Adiar patch numa máquina que termina webhook de produção seria troca
ruim de qualquer jeito.

## Orçamento da máquina — memória e disco do WSL

Enquanto a máquina era desligada todo dia, um vazamento de memória se resolvia sozinho no
desligamento. **Ela agora fica de pé 24/7 e volta sozinha em 19 s — esse conserto deixou de existir.**
O que segura o ecossistema passou a ser o orçamento, e ele mora no `.wslconfig` do Windows
(`C:\Users\<user>\.wslconfig`), não neste repo.

Medido em 09/09/2026, com os 25 containers dos quatro projetos de pé:

| | |
|---|---|
| RAM do host | 15,9 GB |
| Soma dos 25 containers | 4,1 GB |
| VM inteira (containers + kernel + processos) | 5,5 GB |
| Windows (o Docker roda dentro da VM) | ~3,9 GB |

**`memory=` é teto, não reserva — mas o WSL2 não devolve sozinho.** A VM cresce até o teto,
segura o cache e não solta. Com `memory=12GB` num host de 16 GB isso deixaria ~3,9 GB para o
Windows: exatamente o que ele consome, sem folga nenhuma. Por isso o teto generoso só é seguro
acompanhado de `autoMemoryReclaim=gradual`, que devolve ao Windows o que a VM parou de usar:

```ini
[wsl2]
memory=12GB
processors=8
swap=4GB

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
```

Vale depois de `wsl --shutdown` — que derruba Docker, containers, túneis **e a âncora**: religue a
tarefa (`Start-ScheduledTask -TaskName "WSL-Always-On"`) e refaça os túneis.

**Nenhum container tem limite de memória.** É aceitável enquanto a soma é 4,1 GB de 12, e deixa de
ser no dia em que um vazamento levar a VM ao teto: o kernel mata **quem ele escolher**, que pode ser
o Postgres de um projeto por culpa de outro. Se acontecer, o remédio é `mem_limit` no serviço
culpado, não subir o teto.

**Disco: liberar espaço dentro do WSL não devolve espaço ao Windows.** Em 09/09/2026, depois de um
`docker builder prune` que liberou 35 GB, o Linux via 41 GB usados e o `ext4.vhdx` no Windows
continuava com **81,3 GB**. O arquivo virtual só cresce, e hoje não há conversão segura: o WSL 2.7.8
recusa `wsl --manage Ubuntu-24.04 --set-sparse true` com *"O suporte a VHD esparso está atualmente
desativado devido a possível corrupção de dados"* (`Wsl/Service/E_INVALIDARG`, medido em 2026-09-10
com a distro parada). **Não use o `--allow-unsafe` que ele sugere** — é o disco de produção. O
`sparseVhd=true` do `.wslconfig` não mexe no disco atual.

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
> logon"*). **Bloquear não desloga** — a sessão continua viva, com a janela da tarefa, o WSL, o
> Docker e os containers de pé. O PIN que se digita ao voltar é desbloqueio, não logon.

## Conferir que valeu

Depois de um reboot **sem abrir terminal nenhum**, entre no WSL e confira:

```bash
uptime                                    # tem de bater com o boot do Windows
pgrep -u root -fx 'sleep infinity'        # o sleep da tarefa: a âncora
docker compose ps                         # containers de pé
systemctl list-timers 'central-*'         # e a coluna LAST preenchida
```

E o número que fecha o item, do lado Windows — a diferença tem de ser de **segundos**:

```powershell
Get-WinEvent -FilterHashtable @{LogName='System'; Id=6005} -MaxEvents 1 | Select TimeCreated   # boot
Get-WinEvent -FilterHashtable @{LogName='System'; Id=7001} -MaxEvents 1 | Select TimeCreated   # logon
```

É o item **R5** do plano de resiliência: R1 sem esse teste é suposição, não disponibilidade.

## Quem ancora é a janela da tarefa

**A VM fica de pé enquanto houver pelo menos um cliente do Windows conectado a ela — e só isso.**
Cliente é qualquer `wsl.exe` vivo no Windows:

| Cliente | Existe enquanto |
|---|---|
| a janela `C:\Windows\System32\wsl.exe` da tarefa `WSL-Always-On` | ninguém a fechar, do logon em diante — **é a âncora** |
| uma aba Ubuntu do Windows Terminal (inclusive a do Claude Code) | a aba estiver aberta |
| o VS Code com Remote-WSL | a janela estiver conectada |

Quando o último sai, o WSL encerra a instância **15 s depois** — com containers, cron e timers junto.
**Nada dentro do Linux conta como cliente**: nem unidade do systemd, nem Docker, nem os containers.

**Medido em 2026-09-10, em A/B isolado:** distro subida por `wsl -u root -e true` (a sessão sai na
hora), nenhum terminal nem VS Code, e uma unidade do systemd rodando `sleep infinity` com
`Restart=always` ativa → `The system will power off now!` exatamente 15 s depois. Foi assim a queda
de 09/09: das 18:57 às 15:27 do dia seguinte, com o Windows de pé. É o comportamento do WSL desde a
2.6.1 (microsoft/WSL#13416); esta máquina roda a 2.7.8.

### A regra

- **A janela da tarefa fica aberta.** Minimize; não feche. Terminal e VS Code fecham à vontade.
- **Fechou a janela, ou rodou `wsl --shutdown`:** a âncora não volta sozinha — a tarefa só dispara
  no logon. Religue na hora:

  ```powershell
  Start-ScheduledTask -TaskName "WSL-Always-On"
  ```

- **Reinício do Windows** não pede nada: o login automático dispara a tarefa. Medido em 2026-09-10:
  logon 4 s depois do boot, e a janela abriu no mesmo segundo.

`LastTaskResult` não diz **quem** encerrou a tarefa: `3221225786` (`0xC000013A`) sai tanto quando
alguém fecha a janela quanto quando ela é encerrada por fora. Com a tarefa já rodando, um segundo
`Start-ScheduledTask` é recusado com `0x800710E0` — é o `MultipleInstances=IgnoreNew`, inofensivo.
A prova é o processo, não o código (`pgrep`, na seção "Criar a tarefa").

### O que não se usa

- **Gatilho periódico na tarefa** (religar a cada N minutos): decisão — com a regra da janela aberta
  ele é redundante.
- **`[general] instanceIdleTimeout=-1` no `.wslconfig`**: faria a VM sobreviver com zero cliente.
  Redundante com a janela aberta, e também não religaria uma VM já parada.
- **Âncora dentro do Linux** (unidade do systemd, `setsid`, `nohup`): não conta como cliente. E o WSL
  mata a árvore de processos de uma invocação de interop quando o `wsl.exe` dela sai — por isso o
  `sleep` é o próprio processo da tarefa (`exec sleep infinity`), preso à janela.

### Onde isso é cobrado

O `monitorar-canais.sh` confere de hora em hora (sinal 7) que o `sleep` da tarefa está vivo e avisa
no sino do Nexus quando ele some — o estado frágil em que a VM ainda está de pé, segura só por algum
terminal ou pelo VS Code. Ele **não** cobre a VM já desligada: aí nada roda, inclusive ele.
