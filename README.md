# Pós‑Formatação Windows — Script PowerShell

Um utilitário **pós‑formatação** para Windows 11/10, escrito em PowerShell, com **menu interativo** e funções modulares para:

* Criar ponto de restauração do sistema
* Executar o **Win11Debloat** (modo `-RunDefaults`)
* Habilitar **`sudo`** no Windows 11
* Instalar o **Chocolatey**
* Instalar uma lista de **aplicativos via Chocolatey** e garantir **PyWin32**

> **Observação:** o script verifica/garante execução com privilégios de **Administrador**.

---

## 🚀 Começando

```powershell
# 1) Clone o repositório
git clone https://github.com/<seu-usuario>/<seu-repo>.git
cd <seu-repo>

# 2) Execute como Administrador
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\post-install.ps1
```

> Se preferir, abra o **Windows PowerShell (Admin)** e arraste o arquivo `post-install.ps1` para a janela.

---

## 🧭 Menu de Opções

| Nº | Ação                        | Descrição                                                                                           |
| -: | :-------------------------- | :-------------------------------------------------------------------------------------------------- |
|  1 | **Ponto de Restauração**    | Cria um **System Restore Point** (evita duplicar se houver um recente < 24h).                       |
|  2 | **Windebloat**              | Executa `& ([scriptblock]::Create((irm "https://debloat.raphi.re/"))) -RunDefaults`                 |
|  3 | **Habilitar `sudo`**        | Roda `sudo config --enable normal` no Windows 11.                                                   |
|  4 | **Instalar Chocolatey**     | Faz a instalação padrão do [Chocolatey](https://chocolatey.org/).                                   |
|  5 | **Instalar apps + PyWin32** | Instala a lista de pacotes (Chocolatey) e executa `py -m pip install pywin32` **antes** do sumário. |

---

## 🛠️ Personalização

A **lista de pacotes** fica **no topo do script** para facilitar a edição. Exemplo:

```powershell
$Global:ChocoPackages = @(
  'nano','advanced-ip-scanner','putty','python','yt-dlp','ffmpeg','flameshot',
  'adobereader','firefox','python3','teamviewer','notepadplusplus.install',
  'bitwarden','mobaxterm','vlc','winrar','wget','spotify','powertoys',
  'forticlientvpn','rufus','virtualbox'
)
```

> Adicione/remova os pacotes conforme necessário. Os nomes devem corresponder aos **IDs do Chocolatey**.

---

## 📋 Pré‑requisitos

* **Windows 11/10**
* **PowerShell 5.1+**
* Execução como **Administrador** (o script já tenta se auto‑elevar)
* Para a opção 5: Python disponível como `py` (instalado no próprio fluxo via Chocolatey, se estiver na lista)

---

## 🧩 Como funciona

* **Elevação/Admin**: se não estiver como admin, o script se reabre elevado.
* **Restauração (Opção 1)**:

  * Habilita a Proteção do Sistema se estiver desativada;
  * Verifica se existe um ponto de restauração recente (< 24h) para evitar duplicar;
  * Cria ponto `MODIFY_SETTINGS` caso necessário.
* **Windebloat (Opção 2)**: baixa e executa o script oficial com `-RunDefaults`.
* **`sudo` (Opção 3)**: habilita via `sudo config --enable normal` (requer Windows 11 compatível).
* **Chocolatey (Opção 4)**: instala com TLS 1.2 e define `ExecutionPolicy Bypass` para a sessão.
* **Apps + PyWin32 (Opção 5)**:

  * Instala os pacotes da lista (continua em caso de falhas individuais);
  * Executa `py -m pip install pywin32` **antes** de exibir o **sumário de sucessos/falhas**.

---

## 🔎 Solução de problemas

* **ExecutionPolicy**: se houver bloqueio, rode a sessão com **Admin** e use `-ExecutionPolicy Bypass` (como no exemplo de execução).
* **`py` não encontrado**: mantenha `python`/`python3`/`py` na lista de pacotes; após instalar, reabra a sessão ou garanta o PATH.
* **`sudo` indisponível**: alguns builds do Windows 11 podem não trazer o recurso. Verifique se seu sistema é compatível.
* **Falhas no Chocolatey**: a network/proxy pode interferir. Tente novamente e/ou valide o endpoint do Chocolatey.

---

## 📦 Estrutura sugerida

```
<seu-repo>/
├─ post-install.ps1      # Script principal com menu e funções
├─ README.md             # Este arquivo
└─ assets/               # (opcional) imagens, capturas de tela, etc.
```

---

## 🖼️ Capturas de tela (opcional)

> Adicione imagens do menu e da execução em `assets/` e referencie aqui:

```md
![Menu principal](assets/menu.png)
```

---

## 🤝 Contribuindo

1. Faça um **fork** do projeto
2. Crie uma **branch**: `git checkout -b feature/minha-melhoria`
3. **Commit**: `git commit -m "feat: descreva sua mudança"`
4. **Push**: `git push origin feature/minha-melhoria`
5. Abra um **Pull Request**

---

## 📄 Licença

Defina a licença do projeto (ex.: MIT). Crie um arquivo `LICENSE` na raiz do repositório.

---

## 🙏 Agradecimentos

* [Win11Debloat por @raphi364](https://debloat.raphi.re/)
* Comunidade Chocolatey

---

> Dúvidas ou sugestões? Abra uma **issue** no repositório! 😉
