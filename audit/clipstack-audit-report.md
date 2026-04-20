# ClipStack - Relatorio de Auditoria de Seguranca, Privacidade e Qualidade
**Data:** 2026-04-20  
**Versao analisada:** 0.1.0; sem hash de commit, pois `/Users/noasantos/Documents/startapse/CopyCopy` nao e um repositorio git.  
**Coder:** Codex  
**Status:** DRAFT - aguardando revisao do pesquisador

## Tabela Executiva

| ID | Titulo | Categoria | Severidade | Confianca | Breaking Change | Decisao Humana Necessaria |
|----|--------|-----------|------------|-----------|-----------------|--------------------------|
| SEC-001 | Historico persistido em JSON sem criptografia/permissao explicita | Seguranca | P0 Critical | Media | Depende | Sim |
| SEC-002 | Sem deteccao/redacao de secrets | Seguranca | P0 Critical | Alta | Sim | Sim |
| SEC-003 | Sem App Sandbox | Seguranca | P1 High | Alta | Depende | Sim |
| SEC-004 | Hardened Runtime desabilitado em Release | Seguranca | P1 High | Alta | Depende | Sim |
| SEC-005 | Logs de persistencia nao vazam conteudo diretamente | Seguranca | P3 Low | Media | Nao | Nao |
| SEC-006 | Instalador usa curl pipe bash, remove quarantine e assina ad-hoc | Seguranca | P1 High | Alta | Sim | Sim |
| SEC-007 | Checksum hardcoded sem atestacao externa do instalador | Seguranca | P1 High | Alta | Depende | Sim |
| SEC-008 | Fallback sudo cp no instalador | Seguranca | P2 Medium | Media | Depende | Sim |
| PRIV-001 | Sem Pause Capture/Private Mode | Privacidade | P1 High | Alta | Sim | Sim |
| PRIV-002 | Sem TTL/expiracao automatica | Privacidade | P1 High | Alta | Sim | Sim |
| PRIV-003 | Sem clear-on-quit ou purge no lock screen | Privacidade | P2 Medium | Alta | Depende | Sim |
| PRIV-004 | Sem aviso in-app explicito de monitoramento continuo | Privacidade | P3 Low | Alta | Nao | Sim |
| PRIV-005 | ScreenshotWatcher inicia automaticamente sem opt-in | Privacidade | P1 High | Alta | Sim | Sim |
| PRIV-006 | Delecao remove JSON/array sem overwrite seguro | Privacidade | P3 Low | Alta | Depende | Sim |
| QUAL-001 | isSelfWriting depende de janela temporal fixa | Qualidade | P2 Medium | Media | Nao | Nao |
| QUAL-002 | Deduplicacao de imagem compara tiffRepresentation byte-a-byte | Qualidade | P2 Medium | Alta | Nao | Nao |
| QUAL-003 | Watcher GCD cruza para MainActor; isolamento incompleto | Qualidade | P2 Medium | Media | Nao | Nao |
| QUAL-004 | @unchecked Sendable em tipos com estado/NSImage | Qualidade | P2 Medium | Alta | Nao | Nao |
| QUAL-005 | NSImage(contentsOf:) sincrono executa no MainActor | Qualidade | P2 Medium | Alta | Nao | Nao |
| QUAL-006 | Sem limite de tamanho antes de carregar screenshots | Qualidade | P2 Medium | Alta | Nao | Nao |
| QUAL-007 | Versionamento existe, mas sem estrategia de migracao | Qualidade | P2 Medium | Alta | Depende | Sim |
| REL-001 | SHA-256 hardcoded; zip e verificado antes da extracao | Release | P2 Medium | Alta | Nao | Sim |
| REL-002 | Sem configuracao/documentacao de build reproduzivel | Release | P3 Low | Media | Depende | Sim |
| REL-003 | Placeholder FIXME_ORG/clipstack permanece na distribuicao | Release | P2 Medium | Alta | Nao | Nao |
| REL-004 | Sem mecanismo de auto-update | Release | P2 Medium | Alta | Sim | Sim |
| REL-005 | Sem threat model documentado | Release | P3 Low | Alta | Nao | Nao |
| TEST-001 | Sem testes de permissao do history.json | Testes | P2 Medium | Alta | Nao | Nao |
| TEST-002 | Sem teste de concorrencia/stress Monitor + Store | Testes | P2 Medium | Alta | Nao | Nao |
| TEST-003 | ScreenshotWatcher sem testes de PNG malformado/oversized | Testes | P2 Medium | Alta | Nao | Nao |
| TEST-004 | Sem teste especifico do timing de isSelfWriting | Testes | P2 Medium | Alta | Nao | Nao |
| TEST-005 | Sem teste/script de ausencia de trafego de rede | Testes | P3 Low | Alta | Nao | Nao |

## Findings Detalhados

## SEC-001 - `history.json` sem criptografia e sem restricao explicita de permissao

| Campo | Valor |
|-------|-------|
| **Categoria** | Seguranca |
| **Severidade** | P0 Critical |
| **Confianca** | Media (plaintext confirmado; permissao world-readable nao provada em runtime) |
| **Status** | Confirmado |
| **Arquivo(s)** | `ClipboardHistoryPersistence.swift`, linhas 42-47, 69-83 |
| **Breaking Change** | Depende |
| **Decisao Humana** | Sim (modelo de criptografia e migracao afetam produto/busca) |

### Trecho de Codigo Relevante
```swift
// ClipboardHistoryPersistence.swift, linhas 42-47, 79-83
fileURL: baseURL
    .appendingPathComponent("ClipStack", isDirectory: true)
    .appendingPathComponent("history.json")

let data = try encoder.encode(history)
try data.write(to: fileURL, options: [.atomic])
```

### Problema
O historico e serializado diretamente para JSON. Nao ha criptografia, `NSFileProtection*`, atributos de protecao, `chmod 600`, nem criacao atomica com permissao restrita.

### Por que importa neste projeto
ClipStack captura texto e imagens do clipboard por design. Esse fluxo pode incluir senhas, OTPs, tokens, chaves privadas, cartoes e documentos internos.

### Recomendacao
Definir politica: no minimo criar diretorio/arquivo com permissao `0700/0600`; para hardening real, criptografar o conteudo em repouso com chave no Keychain e migracao backward-compatible.

### Tradeoffs
Criptografia pode complicar busca semantica local, migracao, suporte e recuperacao apos perda de chave.

### Teste Sugerido
Teste unitario com persistencia temporaria: salvar item, verificar que o arquivo nao contem plaintext e que `FileManager.attributesOfItem` reporta permissao `0600`.

## SEC-002 - Sem deteccao/redacao de secrets antes de persistir ou exibir

| Campo | Valor |
|-------|-------|
| **Categoria** | Seguranca |
| **Severidade** | P0 Critical |
| **Confianca** | Alta (codigo confirma) |
| **Status** | Confirmado |
| **Arquivo(s)** | `ClipboardMonitor.swift`, linhas 49-55; `ClipboardStore.swift`, linhas 43-67; `ClipboardItem.swift`, linhas 37-43; `MenuBarView.swift`, linhas 227-232 |
| **Breaking Change** | Sim |
| **Decisao Humana** | Sim (falsos positivos e UX de override) |

### Trecho de Codigo Relevante
```swift
// ClipboardMonitor.swift, linhas 49-55
if let string = pasteboard.string(forType: .string), !string.isEmpty {
    store.add(.text(string))
    return
}

// ClipboardItem.swift, linhas 37-40
case .text(let text, id: _, timestamp: _):
    return text.truncatedPreview(maxLength: 60)
```

### Problema
Todo texto nao vazio do pasteboard entra no historico e aparece em preview truncado. Nao ha detector de secrets, redacao, allowlist, denylist, TTL especifico para secrets, nem opt-out por item.

### Por que importa neste projeto
Um clipboard manager captura exatamente os dados que usuarios copiam para autenticar, deployar, pagar ou acessar sistemas.

### Recomendacao
Adicionar camada de classificacao antes de `store.add`: padroes para tokens comuns, private keys, OTPs, cartoes via Luhn, credenciais em URLs e strings de alta entropia. Para P0, preferir "nao persistir por default" para matches fortes e exibir item redigido/temporario.

### Tradeoffs
Falsos positivos podem impedir historico esperado. Precisa de decisao de produto para "bloquear", "redigir", "expirar rapido" ou "perguntar".

### Teste Sugerido
Casos com `sk-...`, JWT, `-----BEGIN PRIVATE KEY-----`, OTP de 6 digitos contextual e numero de cartao valido por Luhn devem falhar antes e passar apos a correcao.

## SEC-003 - App Sandbox ausente

| Campo | Valor |
|-------|-------|
| **Categoria** | Seguranca |
| **Severidade** | P1 High |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | `ClipStack.xcodeproj/project.pbxproj`, linhas 396-420; artefato gerado `ClipStack.app.xcent` contem apenas `com.apple.security.get-task-allow` |
| **Breaking Change** | Depende |
| **Decisao Humana** | Sim (entitlements podem afetar ScreenshotWatcher) |

### Trecho de Codigo Relevante
```text
// project.pbxproj, linhas 399-407
CODE_SIGN_IDENTITY = "-";
CODE_SIGN_STYLE = Manual;
CODE_SIGNING_ALLOWED = YES;
CODE_SIGNING_REQUIRED = NO;
DEVELOPMENT_TEAM = "";
ENABLE_HARDENED_RUNTIME = NO;
```

### Problema
Nao ha arquivo `.entitlements`, nao ha `CODE_SIGN_ENTITLEMENTS`, e nao ha `com.apple.security.app-sandbox`.

### Por que importa neste projeto
Sem sandbox, qualquer bug no app roda com privilegios completos do usuario, incluindo leitura/escrita em locais fora do escopo necessario.

### Recomendacao
Introduzir entitlements minimos, habilitar `com.apple.security.app-sandbox` e modelar permissao para Desktop/Downloads via entitlement adequado ou bookmarks com escopo de seguranca.

### Tradeoffs
Pode quebrar acesso automatico ao Desktop e exigir consentimento/UX nova.

### Teste Sugerido
Verificar `codesign -d --entitlements :- ClipStack.app` em CI e assertar `com.apple.security.app-sandbox = true`.

## SEC-004 - Hardened Runtime desabilitado

| Campo | Valor |
|-------|-------|
| **Categoria** | Seguranca |
| **Severidade** | P1 High |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | `ClipStack.xcodeproj/project.pbxproj`, linhas 345-352, 400-407; `scripts/build.sh`, linhas 34-36, 56-59 |
| **Breaking Change** | Depende |
| **Decisao Humana** | Sim (pre-requisito para notarizacao/Developer ID) |

### Trecho de Codigo Relevante
```text
// project.pbxproj, linhas 400-407
CODE_SIGN_IDENTITY = "-";
CODE_SIGN_STYLE = Manual;
CODE_SIGNING_REQUIRED = NO;
ENABLE_HARDENED_RUNTIME = NO;

// scripts/build.sh, linha 59
codesign --deep --force --sign - "${APP_PATH}"
```

### Problema
Release desabilita Hardened Runtime e usa assinatura ad-hoc.

### Por que importa neste projeto
Hardened Runtime reduz superficie de injecao e e requisito para notarizacao Apple, relevante para distribuicao publica de app que acessa dados sensiveis.

### Recomendacao
Ativar `ENABLE_HARDENED_RUNTIME=YES`, assinar com Developer ID, auditar entitlements e notarizar o artefato.

### Tradeoffs
Exige conta Apple Developer e pode revelar dependencias/entitlements que hoje passam despercebidos.

### Teste Sugerido
Validar que `codesign -dv --verbose=4` inclui flag runtime e que `spctl --assess` passa no artefato notarizado.

## SEC-005 - Logs de persistencia nao parecem vazar conteudo do clipboard

| Campo | Valor |
|-------|-------|
| **Categoria** | Seguranca |
| **Severidade** | P3 Low |
| **Confianca** | Media |
| **Status** | Refutado |
| **Arquivo(s)** | `ClipboardHistoryPersistence.swift`, linhas 63-65, 84-86; `SemanticIndex.swift`, linhas 37-39 |
| **Breaking Change** | Nao |
| **Decisao Humana** | Nao |

### Trecho de Codigo Relevante
```swift
// ClipboardHistoryPersistence.swift, linhas 63-65, 84-86
} catch {
    NSLog("ClipStack failed to load clipboard history: \(error)")
}

} catch {
    NSLog("ClipStack failed to save clipboard history: \(error)")
}
```

### Problema
A hipotese especifica de vazamento de substrings do clipboard nao foi confirmada. Os logs interpolam o objeto `error`, nao os itens.

### Por que importa neste projeto
Logs do sistema podem ser coletados por ferramentas locais. Mesmo sem conteudo, paths e nomes de arquivos podem ser sensiveis.

### Recomendacao
Manter logs sem payload e considerar `Logger` com privacidade explicita (`privacy: .private`) para paths/erros.

### Tradeoffs
Menos detalhe pode dificultar debug de arquivos corrompidos.

### Teste Sugerido
Criar fixture JSON corrompido contendo string sensivel e confirmar que a mensagem registrada nao contem o payload.

## SEC-006 - Instalador usa curl pipe bash, remove quarantine e assina ad-hoc

| Campo | Valor |
|-------|-------|
| **Categoria** | Seguranca |
| **Severidade** | P1 High |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | `README.md`, linhas 7-9, 45-47; `RELEASING.md`, linhas 39-41, 48-54; `install.sh`, linhas 116-127 |
| **Breaking Change** | Sim |
| **Decisao Humana** | Sim (modelo de distribuicao) |

### Trecho de Codigo Relevante
```bash
# README.md, linhas 7-9
curl -fsSL https://raw.githubusercontent.com/FIXME_ORG/clipstack/main/install.sh | bash

# install.sh, linhas 116-125
xattr -dr com.apple.quarantine "${APP_DEST}" 2>/dev/null || true
codesign --deep --force --sign - "${APP_DEST}" 2>/dev/null
```

### Problema
O fluxo recomendado executa script remoto sem inspecao previa, remove quarantine e aplica assinatura local sem identidade.

### Por que importa neste projeto
E um vetor de supply chain para app que persiste clipboard. Se o script ou release for comprometido, o usuario executa a cadeia de instalacao localmente.

### Recomendacao
Substituir por release notarizado/Developer ID, Homebrew Cask com checksum, ou instalador baixado e inspecionavel. Evitar `xattr -dr` como caminho principal.

### Tradeoffs
Developer ID custa dinheiro e aumenta trabalho de release.

### Teste Sugerido
Teste de release que falha se README/RELEASING recomendarem `curl ... | bash` ou se `install.sh` remover quarantine em release oficial.

## SEC-007 - SHA hardcoded, mas instalador sem assinatura/atestacao externa

| Campo | Valor |
|-------|-------|
| **Categoria** | Seguranca |
| **Severidade** | P1 High |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | `install.sh`, linhas 16-17, 72-78; `RELEASING.md`, linhas 27-35 |
| **Breaking Change** | Depende |
| **Decisao Humana** | Sim |

### Trecho de Codigo Relevante
```bash
# install.sh, linhas 16-17, 73-78
EXPECTED_SHA256="f26d6f45769a88933f384d1253b2da1540f07d90d305dee3bc4c21e6acda54e3"
ACTUAL_SHA256=$(shasum -a 256 "${TMP_DIR}/${ZIP_NAME}" | awk '{print $1}')
if [ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]; then
  abort "SHA-256 mismatch..."
fi
```

### Problema
O zip e verificado antes da extracao, o que e bom. Mas o valor esperado vive no proprio script remoto nao assinado; um atacante que altera o script pode alterar tambem o checksum.

### Por que importa neste projeto
O checksum protege contra corrupcao do zip, nao contra comprometimento do canal/script de instalacao.

### Recomendacao
Publicar assinaturas detached, Sigstore/minisign/GPG, ou migrar para Developer ID/notarizacao. Se mantiver script, documentar verificacao fora de banda.

### Tradeoffs
Mais passos para usuarios e manutencao de chaves.

### Teste Sugerido
Checklist/CI que exige assinatura/atestacao anexada ao release e validacao antes da instalacao.

## SEC-008 - Fallback `sudo cp -r` no instalador

| Campo | Valor |
|-------|-------|
| **Categoria** | Seguranca |
| **Severidade** | P2 Medium |
| **Confianca** | Media |
| **Status** | Confirmado |
| **Arquivo(s)** | `install.sh`, linhas 95-107 |
| **Breaking Change** | Depende |
| **Decisao Humana** | Sim |

### Trecho de Codigo Relevante
```bash
# install.sh, linhas 95-107
rm -rf "${APP_DEST}" 2>/dev/null || sudo rm -rf "${APP_DEST}"
if cp -r "${APP_SRC}" "${INSTALL_DIR}/" 2>/dev/null; then
  success "Copied to ${INSTALL_DIR}"
else
  sudo cp -r "${APP_SRC}" "${INSTALL_DIR}/"
fi
```

### Problema
O instalador eleva privilegios para remover/copiar o app em `/Applications`. A hipotese "executa codigo baixado como root" nao e literalmente confirmada pelo `cp`, mas o script remoto controla operacoes root no filesystem.

### Por que importa neste projeto
Com `curl | bash`, qualquer comprometimento do script pode transformar o prompt sudo em execucao privilegiada arbitraria.

### Recomendacao
Preferir instalacao drag-and-drop, Homebrew Cask, pacote assinado, ou instalacao em `~/Applications` sem sudo.

### Tradeoffs
Instalacao por usuario pode ser menos familiar para alguns usuarios.

### Teste Sugerido
Lint de instalador que falha em uso de `sudo` no caminho recomendado.

## PRIV-001 - Sem Pause Capture / Private Mode

| Campo | Valor |
|-------|-------|
| **Categoria** | Privacidade |
| **Severidade** | P1 High |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | `AppDelegate.swift`, linhas 20-26; `MenuBarView.swift`, linhas 184-194 |
| **Breaking Change** | Sim |
| **Decisao Humana** | Sim |

### Trecho de Codigo Relevante
```swift
// AppDelegate.swift, linhas 20-26
let clipboardMonitor = ClipboardMonitor(store: store)
clipboardMonitor.start()
let screenshotWatcher = ScreenshotWatcher(store: store)
screenshotWatcher.start()

// MenuBarView.swift, linhas 184-194
GlassFooterButton(title: "Clear All", systemImage: "trash", ...)
GlassFooterButton(title: "Quit", systemImage: "power") { ... }
```

### Problema
Monitoramento inicia sempre no launch e a UI oferece Clear/Quit, mas nao pausa temporaria nem modo privado.

### Por que importa neste projeto
Usuarios precisam suspender captura antes de copiar senhas, codigos MFA ou conteudo confidencial.

### Recomendacao
Adicionar toggle de pausa com estado visual claro, opcao por tempo ("pausar por 5 min") e exclusao de persistencia enquanto ativo.

### Tradeoffs
Usuarios podem esquecer a pausa ativa e perder historico esperado.

### Teste Sugerido
Com pausa ativa, `pollOnce()` nao deve adicionar texto/imagem; ao desativar, captura volta.

## PRIV-002 - Sem TTL/expiracao automatica

| Campo | Valor |
|-------|-------|
| **Categoria** | Privacidade |
| **Severidade** | P1 High |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | `ClipboardStore.swift`, linhas 197-217; `ClipboardItem.swift`, linhas 16-21 |
| **Breaking Change** | Sim |
| **Decisao Humana** | Sim |

### Trecho de Codigo Relevante
```swift
// ClipboardStore.swift, linhas 197-217
for item in items {
    guard keptItems.count < maxItems else { break }
    if item.imageValue != nil {
        guard keptImageCount < maxImageItems else { continue }
    }
    keptItems.append(item)
}
```

### Problema
O unico mecanismo de retencao e limite por contagem: `maxItems` e `maxImageItems`. Timestamp existe, mas nao e usado para expirar.

### Por que importa neste projeto
Dados sensiveis permanecem indefinidamente ate serem removidos por contagem ou acao manual.

### Recomendacao
Adicionar politica configuravel de TTL global e TTL menor para itens classificados como sensiveis.

### Tradeoffs
Pode remover historico que usuarios esperam manter.

### Teste Sugerido
Criar itens com timestamps antigos e validar que reload/prune remove itens expirados.

## PRIV-003 - Sem clear-on-quit ou purge no lock screen

| Campo | Valor |
|-------|-------|
| **Categoria** | Privacidade |
| **Severidade** | P2 Medium |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | `AppDelegate.swift`, linhas 29-32; `ClipboardStore.swift`, linhas 69-76 |
| **Breaking Change** | Depende |
| **Decisao Humana** | Sim |

### Trecho de Codigo Relevante
```swift
// AppDelegate.swift, linhas 29-32
func applicationWillTerminate(_ notification: Notification) {
    clipboardMonitor?.stop()
    screenshotWatcher?.stop()
}
```

### Problema
Encerrar o app apenas para watchers. Nao ha chamada a `store.clear()` no quit nem observador de tela bloqueada.

### Por que importa neste projeto
Historico sensivel permanece em disco apos logout/quit/bloqueio, quando risco local aumenta.

### Recomendacao
Adicionar preferencias para clear-on-quit e purge-on-lock usando notificacoes de workspace/sessao, se a politica for aprovada.

### Tradeoffs
Pode causar perda de historico esperada.

### Teste Sugerido
Simular terminacao com preferencia ativa e verificar que persistencia fica vazia.

## PRIV-004 - Sem aviso explicito in-app de monitoramento continuo

| Campo | Valor |
|-------|-------|
| **Categoria** | Privacidade |
| **Severidade** | P3 Low |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | `AppDelegate.swift`, linhas 46-50; `MenuBarView.swift`, linhas 106-194; `README.md`, linhas 13-19 |
| **Breaking Change** | Nao |
| **Decisao Humana** | Sim |

### Trecho de Codigo Relevante
```swift
// AppDelegate.swift, linhas 46-50
let image = NSImage(systemSymbolName: "clipboard.fill", accessibilityDescription: "ClipStack")
button.image = image
button.toolTip = "ClipStack Clipboard History"
```

### Problema
README explica que monitora clipboard, mas o app em si nao mostra consentimento/onboarding/indicador textual alem do icone e tooltip.

### Por que importa neste projeto
Monitoramento continuo de clipboard e sensivel; usuarios podem nao perceber que tudo esta sendo capturado.

### Recomendacao
Adicionar onboarding/primeiro uso e estado visual de captura ativa/pausada.

### Tradeoffs
Mais friccao no MVP.

### Teste Sugerido
Teste UI/snapshot ou unitario de preferencia `hasSeenPrivacyNotice`.

## PRIV-005 - ScreenshotWatcher copia screenshots automaticamente sem opt-in

| Campo | Valor |
|-------|-------|
| **Categoria** | Privacidade |
| **Severidade** | P1 High |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | `AppDelegate.swift`, linhas 24-26; `ScreenshotWatcher.swift`, linhas 21-27, 137-146; `README.md`, linhas 15-17 |
| **Breaking Change** | Sim |
| **Decisao Humana** | Sim |

### Trecho de Codigo Relevante
```swift
// AppDelegate.swift, linhas 24-26
let screenshotWatcher = ScreenshotWatcher(store: store)
screenshotWatcher.start()

// ScreenshotWatcher.swift, linhas 140-146
guard let image = NSImage(contentsOf: url) else { return }
store.copyScreenshotImageToPasteboardAndHistory(image)
Self.postScreenshotNotification()
```

### Problema
O watcher usa Desktop por default e inicia no launch. Nao ha preferencia de opt-in, escopo escolhido pelo usuario ou exclusao do historico.

### Por que importa neste projeto
Screenshots podem conter documentos, chats, dados financeiros ou segredos. Auto-copiar tambem altera o pasteboard do usuario.

### Recomendacao
Tornar recurso opt-in, com toggle visivel, escopo configuravel e opcao "copiar sem salvar no historico".

### Tradeoffs
Muda comportamento de MVP e pode reduzir conveniencia.

### Teste Sugerido
Com preferencia default off, `ScreenshotWatcher` nao deve iniciar; com opt-in, deve copiar somente arquivos dentro do escopo autorizado.

## PRIV-006 - Delecao sem overwrite seguro

| Campo | Valor |
|-------|-------|
| **Categoria** | Privacidade |
| **Severidade** | P3 Low |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | `ClipboardStore.swift`, linhas 69-76, 82-95; `uninstall.sh`, linhas 19-21 |
| **Breaking Change** | Depende |
| **Decisao Humana** | Sim |

### Trecho de Codigo Relevante
```swift
// ClipboardStore.swift, linhas 87-89
items.removeAll { $0.id == id }
searchResults.removeAll { $0.id == id }
persist()

// uninstall.sh, linhas 19-21
rm -rf ~/Library/Application\ Support/ClipStack
```

### Problema
Itens sao removidos de memoria e JSON regravado; nao ha sobrescrita segura do conteudo antigo.

### Por que importa neste projeto
Em storage moderno/APFS/SSD, overwrite seguro nao e garantido, mas a expectativa de "delete" pode ser maior quando o dado e secreto.

### Recomendacao
Documentar limitacao e priorizar criptografia em repouso com destruicao de chave para "secure delete" efetivo.

### Tradeoffs
Overwrite manual pode dar falsa seguranca e degradar performance.

### Teste Sugerido
Verificar que delete remove do JSON logico; para secure delete, testar destruicao de chave quando criptografia existir.

## QUAL-001 - `isSelfWriting` depende de temporizador fixo

| Campo | Valor |
|-------|-------|
| **Categoria** | Qualidade |
| **Severidade** | P2 Medium |
| **Confianca** | Media |
| **Status** | Suspeita |
| **Arquivo(s)** | `ClipboardStore.swift`, linhas 108-121; `ClipboardMonitor.swift`, linhas 6, 37-47 |
| **Breaking Change** | Nao |
| **Decisao Humana** | Nao |

### Trecho de Codigo Relevante
```swift
// ClipboardStore.swift, linhas 108-121
isSelfWriting = true
pasteboard.clearContents()
...
DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
    self?.isSelfWriting = false
}

// ClipboardMonitor.swift, linhas 6, 45-46
static let pollInterval: TimeInterval = 0.5
guard !store.isSelfWriting else { return }
```

### Problema
O filtro de self-write e temporal. Se o main thread atrasar o poll para depois de 0.6s, o app pode recapturar item escrito por ele mesmo.

### Por que importa neste projeto
Pode gerar duplicacao, reorder inesperado e loops sutis entre restore, screenshot e monitor.

### Recomendacao
Rastrear `changeCount` produzido pela escrita propria ou guardar assinatura/hash do item escrito ate o proximo change observado, em vez de tempo fixo.

### Tradeoffs
Exige cuidado para nao ignorar uma alteracao real feita logo apos restore.

### Teste Sugerido
Teste deterministico com pasteboard fake/changeCount fake cobrindo poll antes/depois do reset.

## QUAL-002 - Deduplicacao de imagem usa `tiffRepresentation` byte-a-byte

| Campo | Valor |
|-------|-------|
| **Categoria** | Qualidade |
| **Severidade** | P2 Medium |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | `ClipboardItem.swift`, linhas 46-55; `ClipboardStore.swift`, linha 58 |
| **Breaking Change** | Nao |
| **Decisao Humana** | Nao |

### Trecho de Codigo Relevante
```swift
// ClipboardItem.swift, linhas 50-54
guard let lhsData = lhs.tiffRepresentation, let rhsData = rhs.tiffRepresentation else {
    return false
}
return lhsData == rhsData
```

### Problema
Cada deduplicacao pode materializar TIFFs grandes e comparar bytes contra itens existentes.

### Por que importa neste projeto
Screenshots podem ser grandes; isso afeta memoria, CPU e responsividade.

### Recomendacao
Calcular digest normalizado uma vez por imagem persistida/capturada e comparar hashes/tamanho, com limite maximo.

### Tradeoffs
Hash pode exigir migracao se for persistido no schema.

### Teste Sugerido
Teste de performance/memoria com imagens grandes e muitos itens.

## QUAL-003 - Watcher GCD cruza para MainActor, mas isolamento do watcher nao e formalizado

| Campo | Valor |
|-------|-------|
| **Categoria** | Qualidade |
| **Severidade** | P2 Medium |
| **Confianca** | Media |
| **Status** | Suspeita |
| **Arquivo(s)** | `ScreenshotWatcher.swift`, linhas 14-19, 43-50, 118-126, 137-146 |
| **Breaking Change** | Nao |
| **Decisao Humana** | Nao |

### Trecho de Codigo Relevante
```swift
// ScreenshotWatcher.swift, linhas 16-19, 49-50, 140-145
private let queue = DispatchQueue(label: "com.startapse.ClipStack.screenshot-watcher")
private var processedFileIdentifiers = Set<String>()
source.setEventHandler { [weak self] in
    self?.scanForRecentScreenshots()
}
Task { @MainActor [store, url] in
    guard let image = NSImage(contentsOf: url) else { return }
    store.copyScreenshotImageToPasteboardAndHistory(image)
}
```

### Problema
O acesso ao `ClipboardStore` ocorre dentro de `Task { @MainActor }`, mas o watcher em si nao e actor-isolated. `source`, `fileDescriptor` e `processedFileIdentifiers` dependem de disciplina manual entre caller e queue.

### Por que importa neste projeto
Misturar GCD e Swift concurrency pode esconder data races e violacoes de isolamento em mudancas futuras.

### Recomendacao
Isolar o watcher em um ator ou garantir todas as mutacoes na fila privada, com API publica `@MainActor`/serializada clara.

### Tradeoffs
Pode exigir reestruturar testes e lifecycle.

### Teste Sugerido
Executar Thread Sanitizer e teste que chama start/stop enquanto eventos sao processados.

## QUAL-004 - Uso de `@unchecked Sendable`

| Campo | Valor |
|-------|-------|
| **Categoria** | Qualidade |
| **Severidade** | P2 Medium |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | `ClipboardItem.swift`, linha 5; `SemanticIndex.swift`, linha 17; `SemanticIndexTests.swift`, linhas 230, 242 |
| **Breaking Change** | Nao |
| **Decisao Humana** | Nao |

### Trecho de Codigo Relevante
```swift
// ClipboardItem.swift, linhas 5-7
enum ClipboardItem: Identifiable, @unchecked Sendable {
    case text(String, id: UUID = UUID(), timestamp: Date = Date())
    case image(NSImage, id: UUID = UUID(), timestamp: Date = Date())
}

// SemanticIndex.swift, linha 17
final class NaturalLanguageSentenceVectorProvider: SemanticVectorProviding, @unchecked Sendable
```

### Problema
`NSImage` nao e garantidamente Sendable, e `NaturalLanguageSentenceVectorProvider` tem estado mutavel (`didLoadEmbeddings`, embeddings) sem lock/actor.

### Por que importa neste projeto
O codigo usa Tasks e actor `SemanticIndex`; `@unchecked` remove protecoes do compilador justamente nos pontos sensiveis.

### Recomendacao
Substituir por tipos value/sendable para dados de imagem, isolar provider em actor ou proteger estado com lock.

### Tradeoffs
Pode exigir conversao de imagem para `Data`/metadata e ajustes de UI.

### Teste Sugerido
Ativar Swift concurrency diagnostics estritos e rodar stress de busca/rebuild concorrente.

## QUAL-005 - `NSImage(contentsOf:)` sincrono executa no MainActor

| Campo | Valor |
|-------|-------|
| **Categoria** | Qualidade |
| **Severidade** | P2 Medium |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | `ScreenshotWatcher.swift`, linhas 137-146 |
| **Breaking Change** | Nao |
| **Decisao Humana** | Nao |

### Trecho de Codigo Relevante
```swift
// ScreenshotWatcher.swift, linhas 140-145
Task { @MainActor [store, url] in
    guard let image = NSImage(contentsOf: url) else {
        return
    }
    store.copyScreenshotImageToPasteboardAndHistory(image)
}
```

### Problema
A hipotese de chamada na watcher queue foi refutada; a chamada acontece no MainActor. Ainda assim, decodificacao de imagem do disco e sincrona e pode bloquear UI.

### Por que importa neste projeto
Screenshots grandes ou disco lento podem travar menu bar/popover.

### Recomendacao
Carregar/validar dados fora do MainActor, depois entregar imagem ja validada ao store no MainActor.

### Tradeoffs
NSImage/AppKit tem restricoes de thread; pode ser melhor usar ImageIO/CGImageSource fora da main.

### Teste Sugerido
Teste com imagem grande e medicao de bloqueio do MainActor.

## QUAL-006 - Sem limite de tamanho de imagem antes de carregar

| Campo | Valor |
|-------|-------|
| **Categoria** | Qualidade |
| **Severidade** | P2 Medium |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | `ScreenshotWatcher.swift`, linhas 90-126, 137-142 |
| **Breaking Change** | Nao |
| **Decisao Humana** | Nao |

### Trecho de Codigo Relevante
```swift
// ScreenshotWatcher.swift, linhas 104-116, 140-142
let candidates = fileURLs.compactMap { url -> ScreenshotCandidate? in
    guard let values = try? url.resourceValues(forKeys: resourceKeys),
          values.isRegularFile == true else { return nil }
    return ScreenshotCandidate(url: url, creationDate: date)
}
guard let image = NSImage(contentsOf: url) else { return }
```

### Problema
Filtro verifica extensao, nome e data, mas nao tamanho em bytes, dimensoes ou tipo real antes de carregar.

### Por que importa neste projeto
Arquivo enorme ou malicioso com nome de screenshot pode causar uso excessivo de memoria/CPU.

### Recomendacao
Checar `fileSizeKey`, usar `CGImageSourceCopyPropertiesAtIndex` para dimensoes e impor limites antes de decodificar.

### Tradeoffs
Pode rejeitar screenshots legitimos muito grandes.

### Teste Sugerido
Testes com PNG muito grande, arquivo falso `.png` e arquivo acima do limite.

## QUAL-007 - Sem estrategia real de migracao de schema

| Campo | Valor |
|-------|-------|
| **Categoria** | Qualidade |
| **Severidade** | P2 Medium |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | `ClipboardHistoryPersistence.swift`, linhas 10-12, 57-62, 69-72 |
| **Breaking Change** | Depende |
| **Decisao Humana** | Sim |

### Trecho de Codigo Relevante
```swift
// ClipboardHistoryPersistence.swift, linhas 10-12, 61-62, 71
private struct StoredHistory: Codable {
    let version: Int
    let items: [StoredItem]
}
let history = try decoder.decode(StoredHistory.self, from: data)
return history.items.compactMap(Self.makeClipboardItem(from:))
let history = StoredHistory(version: 1, items: storedItems)
```

### Problema
Existe campo `version`, mas o loader nao faz switch por versao, migracao, fallback ou preservacao de formato antigo.

### Por que importa neste projeto
Criptografia, redacao, hashes de imagem ou TTL provavelmente mudarao o schema.

### Recomendacao
Introduzir migrador por versao, testes de fixtures antigas e caminho de backup em caso de falha.

### Tradeoffs
Aumenta complexidade antes do produto estabilizar.

### Teste Sugerido
Fixtures `version: 1`, futura `version: 2` e versao desconhecida devem ter comportamento definido.

## REL-001 - SHA-256 hardcoded e verificado antes da extracao

| Campo | Valor |
|-------|-------|
| **Categoria** | Release |
| **Severidade** | P2 Medium |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | `install.sh`, linhas 16-17, 67-84 |
| **Breaking Change** | Nao |
| **Decisao Humana** | Sim |

### Trecho de Codigo Relevante
```bash
# install.sh, linhas 69-84
curl -fsSL --progress-bar "${DOWNLOAD_URL}" -o "${TMP_DIR}/${ZIP_NAME}"
ACTUAL_SHA256=$(shasum -a 256 "${TMP_DIR}/${ZIP_NAME}" | awk '{print $1}')
if [ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]; then abort ...; fi
ditto -x -k "${TMP_DIR}/${ZIP_NAME}" "${TMP_DIR}/extracted/"
```

### Problema
O zip e verificado antes da extracao, refutando a parte "depois da execucao do zip". O risco restante e checksum hardcoded no mesmo instalador nao assinado.

### Por que importa neste projeto
Integridade do zip e boa, mas nao basta para cadeia de confianca publica.

### Recomendacao
Separar assinatura/atestacao do artefato e do instalador.

### Tradeoffs
Mais passos de release.

### Teste Sugerido
CI que verifica ordem download -> checksum -> extract e presenca de assinatura externa.

## REL-002 - Sem build reproduzivel documentado/configurado

| Campo | Valor |
|-------|-------|
| **Categoria** | Release |
| **Severidade** | P3 Low |
| **Confianca** | Media |
| **Status** | Suspeita |
| **Arquivo(s)** | `scripts/build.sh`, linhas 7, 24-38, 71-77; `RELEASING.md`, linhas 11-35 |
| **Breaking Change** | Depende |
| **Decisao Humana** | Sim |

### Trecho de Codigo Relevante
```bash
# scripts/build.sh, linhas 7, 25-38, 74-77
BUILD_DIR="$(pwd)/build"
xcodebuild ... -derivedDataPath "${BUILD_DIR}/derived" ... build
ditto -c -k --keepParent "${APP_PATH}" "${BUILD_DIR}/${ZIP_NAME}"
SHA256=$(shasum -a 256 "${BUILD_DIR}/${ZIP_NAME}" | awk '{print $1}')
```

### Problema
Nao encontrei configuracao/documentacao para builds bit-for-bit reproduziveis, controle de timestamps, paths absolutos ou ambiente fixo.

### Por que importa neste projeto
Reprodutibilidade ajuda usuarios/pesquisadores a validar que o binario corresponde ao codigo-fonte.

### Recomendacao
Documentar toolchain, ambiente e comparar hashes de builds limpos; avaliar flags/normalizacao de zip.

### Tradeoffs
Pode ser caro para MVP macOS/Xcode.

### Teste Sugerido
Job que roda build duas vezes em ambiente limpo e compara hashes normalizados.

## REL-003 - Placeholder `FIXME_ORG/clipstack` permanece

| Campo | Valor |
|-------|-------|
| **Categoria** | Release |
| **Severidade** | P2 Medium |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | `install.sh`, linhas 8, 13-15; `README.md`, linhas 7-9, 53-55; `RELEASING.md`, linhas 39-41 |
| **Breaking Change** | Nao |
| **Decisao Humana** | Nao |

### Trecho de Codigo Relevante
```bash
# install.sh, linhas 13-15
REPO="FIXME_ORG/clipstack"
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ZIP_NAME}"
```

### Problema
Installer e docs apontam para placeholder, nao repositorio real.

### Por que importa neste projeto
Distribuicao publica fica quebrada ou direciona usuarios para um namespace inexistente/errado.

### Recomendacao
Substituir por org/repo real antes de release e validar URLs em CI.

### Tradeoffs
Nenhum relevante.

### Teste Sugerido
Lint que falha em placeholder de org ou URL 404.

## REL-004 - Sem auto-update

| Campo | Valor |
|-------|-------|
| **Categoria** | Release |
| **Severidade** | P2 Medium |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | `README.md`, linhas 5-9; `RELEASING.md`, linhas 18-35; busca por `Sparkle`, `URLSession`, `auto-update` sem resultado relevante |
| **Breaking Change** | Sim |
| **Decisao Humana** | Sim |

### Trecho de Codigo Relevante
```markdown
<!-- README.md, linhas 5-9 -->
## Install
curl -fsSL https://raw.githubusercontent.com/FIXME_ORG/clipstack/main/install.sh | bash
```

### Problema
Nao ha mecanismo de update, feed de release, Sparkle, checagem de versao ou notificacao de patch.

### Por que importa neste projeto
Falhas de seguranca em clipboard manager precisam chegar aos usuarios.

### Recomendacao
Decidir entre Sparkle, Homebrew Cask, aviso manual de nova versao, ou distribuicao notarizada com canal claro.

### Tradeoffs
Auto-update introduz rede e nova superficie de supply chain.

### Teste Sugerido
Teste de manifest/update feed quando o mecanismo existir.

## REL-005 - Sem threat model documentado

| Campo | Valor |
|-------|-------|
| **Categoria** | Release |
| **Severidade** | P3 Low |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | Busca por arquivos `*threat*`, `SECURITY.md` nao retornou resultados |
| **Breaking Change** | Nao |
| **Decisao Humana** | Nao |

### Trecho de Codigo Relevante
```text
Resultado da busca:
find . -maxdepth 5 -type f \( -name '*threat*' -o -name '*Threat*' -o -name 'SECURITY.md' \)
# sem resultados
```

### Problema
Nao ha documento de ameacas, assets, boundaries, decisoes aceitas e riscos residuais.

### Por que importa neste projeto
Clipboard manager local tem risco concentrado em dados sensiveis locais e supply chain.

### Recomendacao
Criar `SECURITY.md` e `THREAT_MODEL.md` com ameacas locais, instalacao, persistencia, screenshots e updates.

### Tradeoffs
Tempo de manutencao.

### Teste Sugerido
Checklist de release exigindo revisao do threat model para mudancas de persistencia/distribuicao.

## TEST-001 - Sem testes de permissao do `history.json`

| Campo | Valor |
|-------|-------|
| **Categoria** | Testes |
| **Severidade** | P2 Medium |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | `ClipboardStoreTests.swift`, linhas 181-229, 253-264 |
| **Breaking Change** | Nao |
| **Decisao Humana** | Nao |

### Trecho de Codigo Relevante
```swift
// ClipboardStoreTests.swift, linhas 181-189
firstStore.add(.text("persist me"))
let reloadedStore = ClipboardStore(persistence: persistence)
XCTAssertEqual(reloadedStore.items[0].textValue, "persist me")
```

### Problema
Testes cobrem persistencia/reload/remocao logica, mas nao atributos de arquivo.

### Por que importa neste projeto
Permissao incorreta do arquivo exporia clipboard para outros processos/usuarios locais.

### Recomendacao
Adicionar teste de `posixPermissions` do arquivo e diretorio.

### Tradeoffs
Permissoes podem variar por plataforma se nao forem definidas explicitamente.

### Teste Sugerido
Salvar historico temporario e assertar `0o600` para arquivo e `0o700` para diretorio.

## TEST-002 - Sem testes de concorrencia/stress Monitor + Store

| Campo | Valor |
|-------|-------|
| **Categoria** | Testes |
| **Severidade** | P2 Medium |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | `ClipboardMonitorTests.swift`, linhas 17-53; `ClipboardStoreTests.swift`, linhas 231-251 |
| **Breaking Change** | Nao |
| **Decisao Humana** | Nao |

### Trecho de Codigo Relevante
```swift
// ClipboardMonitorTests.swift, linhas 17-26
NSPasteboard.general.setString("hello", forType: .string)
monitor.pollOnce()
XCTAssertEqual(store.items[0].textValue, "hello")
```

### Problema
Testes exercitam chamadas unitarias e um sleep de busca, mas nao stress de polling, restore, persistencia e tasks simultaneas.

### Por que importa neste projeto
Os riscos de `isSelfWriting`, semantic index e watcher aparecem em timing real.

### Recomendacao
Usar pasteboard fake para gerar sequencias rapidas e rodar sob Thread Sanitizer.

### Tradeoffs
Testes de timing podem ficar flaky se nao forem deterministas.

### Teste Sugerido
Stress com 1.000 mudancas simuladas, restores intercalados e asserts de contagem/duplicacao.

## TEST-003 - ScreenshotWatcher nao cobre PNG malformado/oversized

| Campo | Valor |
|-------|-------|
| **Categoria** | Testes |
| **Severidade** | P2 Medium |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | `ScreenshotWatcherTests.swift`, linhas 6-54 |
| **Breaking Change** | Nao |
| **Decisao Humana** | Nao |

### Trecho de Codigo Relevante
```swift
// ScreenshotWatcherTests.swift, linhas 26-33, 36-43
let url = URL(fileURLWithPath: "/tmp/Screenshot ... .jpg")
XCTAssertTrue(result.isEmpty)
let url = URL(fileURLWithPath: "/tmp/Photo 2026-04-20.png")
XCTAssertTrue(result.isEmpty)
```

### Problema
Cobertura atual testa filtro por extensao, prefixo e idade. Nao testa arquivo `.png` invalido, `.png` nao-PNG, dimensoes enormes ou tamanho em bytes.

### Por que importa neste projeto
Watcher carrega imagens automaticamente do Desktop.

### Recomendacao
Adicionar testes com fixtures malformadas e limites.

### Tradeoffs
Fixtures grandes podem pesar; usar arquivos sinteticos pequenos com headers manipulados.

### Teste Sugerido
Criar arquivo `Screenshot ... .png` com texto aleatorio e garantir que nao e carregado nem persistido.

## TEST-004 - Sem teste especifico para timing de `isSelfWriting`

| Campo | Valor |
|-------|-------|
| **Categoria** | Testes |
| **Severidade** | P2 Medium |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | `ClipboardMonitorTests.swift`, linhas 29-40 |
| **Breaking Change** | Nao |
| **Decisao Humana** | Nao |

### Trecho de Codigo Relevante
```swift
// ClipboardMonitorTests.swift, linhas 29-38
store.isSelfWriting = true
NSPasteboard.general.setString("self write", forType: .string)
monitor.pollOnce()
store.isSelfWriting = false
```

### Problema
O teste cobre apenas flag manual ativa no momento de `pollOnce`; nao cobre reset automatico de 0.6s, poll interval 0.5s ou atraso do main thread.

### Por que importa neste projeto
O bug potencial e temporal; teste estatico nao detecta regressao.

### Recomendacao
Injetar scheduler/clock ou abstrair self-write tracker para teste deterministico.

### Tradeoffs
Pequena refatoracao para testabilidade.

### Teste Sugerido
Simular self-write, avancar clock para antes/depois do reset e confirmar comportamento esperado.

## TEST-005 - Sem teste/script de ausencia de trafego de rede

| Campo | Valor |
|-------|-------|
| **Categoria** | Testes |
| **Severidade** | P3 Low |
| **Confianca** | Alta |
| **Status** | Confirmado |
| **Arquivo(s)** | `scripts/test.sh`, linhas 15-20; busca por `URLSession`/network sem uso no app |
| **Breaking Change** | Nao |
| **Decisao Humana** | Nao |

### Trecho de Codigo Relevante
```bash
# scripts/test.sh, linhas 15-20
xcodebuild test \
  -project "$ROOT_DIR/ClipStack.xcodeproj" \
  -scheme ClipStack \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64'
```

### Problema
O codigo nao mostra chamadas de rede no app, mas nao existe teste que assegure "network silence".

### Por que importa neste projeto
README promete "No network access. No cloud sync. No account. No telemetry."

### Recomendacao
Adicionar teste estatico/lint para APIs de rede e, opcionalmente, teste dinamico com firewall/local proxy em CI.

### Tradeoffs
Teste dinamico pode ser fragil em CI macOS.

### Teste Sugerido
Script que falha se `URLSession`, `CFNetwork`, sockets ou dependencias de rede aparecerem no target do app.

## Problemas Confirmados

SEC-001, SEC-002, SEC-003, SEC-004, SEC-006, SEC-007, SEC-008, PRIV-001, PRIV-002, PRIV-003, PRIV-004, PRIV-005, PRIV-006, QUAL-002, QUAL-004, QUAL-005, QUAL-006, QUAL-007, REL-001, REL-003, REL-004, REL-005, TEST-001, TEST-002, TEST-003, TEST-004, TEST-005.

## Suspeitas que Precisam de Decisao de Produto

SEC-001 (criptografia/permissao e migracao), SEC-002 (politica de redacao), PRIV-001 (semantica de pausa), PRIV-002 (retencao), PRIV-003 (limpar no quit/lock), PRIV-005 (screenshot opt-in), QUAL-007 (evolucao de schema), REL-004 (auto-update versus promessa local-only).

## Melhorias Opcionais

SEC-005, PRIV-004, PRIV-006, REL-002, REL-005, TEST-005.

## Itens Nao Aplicaveis

SEC-005 foi refutado na forma proposta: nao ha evidencia de log de substrings de clipboard; os logs interpolam apenas objetos de erro.

## Plano de Implementacao Sugerido

Nao implementar nesta auditoria. Ordem sugerida se aprovada:

### Fase 1 - Quick Wins (sem breaking change)

REL-003, TEST-001, TEST-003, TEST-004, TEST-005, SEC-005 hardening de logs, QUAL-002 digest/limites simples se nao persistir schema.

### Fase 2 - Hardening de Seguranca (pode exigir decisao)

SEC-001, SEC-002, PRIV-001, PRIV-002, PRIV-003, PRIV-005, QUAL-006, QUAL-007. Dependencia principal: decidir schema/migracao antes de criptografia, hashes, TTL e redacao persistida.

### Fase 3 - Maturidade e Distribuicao

SEC-003, SEC-004, SEC-006, SEC-007, SEC-008, REL-001, REL-002, REL-004, REL-005. Dependencia principal: escolher canal de distribuicao e assinatura.

## Perguntas de Decisao

1. Criptografia do `history.json` e obrigatoria para v1.0 ou pode ficar para pos-MVP?
2. Para secrets detectados, o produto deve bloquear persistencia, redigir preview, aplicar TTL curto ou pedir confirmacao?
3. Private Mode deve ser persistente, por sessao ou temporizado?
4. Qual TTL default e aceitavel para historico geral e para secrets?
5. Auto-copia de screenshots deve ser opt-in? Deve salvar no historico ou apenas copiar para pasteboard?
6. O projeto vai investir em Apple Developer ID/notarizacao agora ou manter distribuicao manual?
7. App Sandbox e requisito para v1.0 mesmo que exija novo fluxo de permissao para Desktop?
8. Auto-update e compativel com a promessa "local-only/no network" se for apenas check de versao?
9. Qual comportamento esperado para clear-on-quit e purge-on-lock?
10. Qual contrato de compatibilidade para `history.json` apos mudancas de schema?
