[English](README.md) · **Português (Brasil)**

# God of War II HD — port nativo por recompilação estática

Port nativo de **God of War II HD** (PS3, `NPUA80491`) para **macOS/Apple Silicon**, com versões
experimentais para iPhone e Android, por **recompilação estática**: o código PowerPC (PPU) e SPU do
jogo é traduzido para C/C++ antes da execução, compilado para arm64 e roda sobre uma reimplementação do
sistema do PS3, com Metal (gráficos), VideoToolbox (vídeos) e CoreAudio (som) no Mac. Sem emulador e
sem JIT.

> Este repositório **não contém código nem arquivos do jogo**. Como no Dusk, você fornece a sua própria
> cópia, obtida legalmente, e o kit de instalação descriptografa, traduz e compila tudo **na sua máquina**.

## Estado

O jogo vai do boot ao gameplay no Mac (Metal) e no tablet Android (Vulkan); no iPhone, em ramos
anteriores. Os números medidos (aparelho, data e número de corridas) estão em
[Estado por plataforma e desempenho](README.md#estado-por-plataforma-e-desempenho-2026-10-02) e as
pendências em [Em aberto](README.md#em-aberto).

## Requisitos (Mac)

- Mac com Apple Silicon (M1 ou mais novo), Xcode Command Line Tools (`xcode-select --install`) e,
  pelo [Homebrew](https://brew.sh), `cmake ninja pkgconf sdl2`. Detalhes em [kit/README.md](kit/README.md).
- O motor [ps3recomp](https://github.com/andrebrumdev/ps3recomp) ao lado deste repositório
  (`../ps3recomp`) ou indicado por `PS3_ENGINE_ROOT`.
- O seu jogo, **God of War II HD, NPUA80491 v01.00**: a pasta `PS3_GAME` (com `USRDIR/EBOOT.BIN` e
  `USRDIR/gow2.psarc`, do RPCS3 ou do seu PS3) e a sua licença
  `UP9000-NPUA80491_00-GODOFWARIIHDUS00.rap`.

## Começo rápido (Mac)

```bash
./kit/setup.sh /caminho/para/PS3_GAME   # acha o .rap sozinho (exdata do RPCS3, ao lado do jogo ou ~/Downloads)
./jogar_g2.sh
```

O `setup.sh` descriptografa o `EBOOT.BIN`, recompila o código PPU e os sete programas SPU, extrai os
filmes do seu `gow2.psarc` e gera o `./g2play`, conferindo cada arquivo gerado com os hashes do `kit/`.
O launcher nativo (`GoW2 Recomp.app`) sai de `launcher/macos/build_app.sh`.

- Android: [Android: compilar e instalar](README.md#android-compilar-e-instalar).
- iOS e Mac (build de desenvolvimento): [iOS e Mac](README.md#ios-e-mac).
- Como medir desempenho: [Como medir](README.md#como-medir).
- Central do jogo (PS/Home, Select+Start ou F1): [seção do overlay](README.md#central-do-jogo-pshome-selectstart-ou-f1-e-o-launcher).

## Aviso legal

God of War II é © Sony Interactive Entertainment. Este projeto não é afiliado nem endossado pela Sony.
Nenhum código ou arquivo do jogo é distribuído; você precisa ter o jogo.

O APK para Android é compilado localmente a partir do seu próprio dump e instalado somente no seu próprio aparelho; ele nunca é distribuído. As bibliotecas do FFmpeg dentro do app continuam sob a LGPL-2.1 e podem ser copiadas, modificadas e substituídas.

A licença MIT ([LICENSE](LICENSE)) cobre só o código e a documentação originais deste projeto; ela não
dá nenhum direito sobre os dados, o código ou as imagens do jogo, nem sobre as partes deles que ficam
no lift gerado por você a partir do seu próprio binário. Componentes de terceiros mantêm as próprias
licenças. Detalhes em [NOTICE.md](NOTICE.md).

## Mais

- O README completo (em inglês, com as seções técnicas em português): [README.md](README.md).
- Os dois repositórios: [Os dois repositórios](README.md#os-dois-repositórios).
- Organização das pastas e mapa dos scripts (caminho antigo na raiz → caminho novo): [scripts/README.md](scripts/README.md).
