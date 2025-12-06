## 🚀 Pós‑Formatação Windows — Script PowerShell

Um utilitário **pós‑formatação** para Windows 11/10, escrito em PowerShell, com **menu interativo** e funções modulares. Ele utiliza o **Winget** para instalação em lote e permite a gestão da lista de pacotes via um arquivo externo no GitHub.

> **Observação:** O script verifica e garante a execução com privilégios de **Administrador**.

---

### 📥 Como Executar

Execute o comando abaixo no CMD para baixar e iniciar o script com privilégios elevados de administrador:

```CMD
powershell.exe Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -Command "& ([ScriptBlock]::Create((irm ''https://raw.githubusercontent.com/renato95souza/pos-formatacao/main/post-install.ps1'')))"'
