```markdown


## Arquitetura

O repositório é um projeto pequeno e concentrado: o núcleo inteiro está em `zplclass.prg`, acompanhado por um programa de exemplo em `teste\teste.prg`, uma entrada ZPL (`teste\teste.zpl`), um PDF gerado e um script de compilação específico para Windows.

O fluxo principal é:

```text
ZPL em string ou arquivo
        |
        v
TZebraToPdf:Generate()
        |
        +-- Substituição de variáveis
        +-- Pré-processamento do ZPL
        +-- Separação de múltiplas etiquetas
        +-- Extração de dimensões
        +-- Interpretação dos comandos
        +-- Renderização em PDF
        v
Arquivo PDF via HaruPDF
```

### Módulo principal: `zplclass.prg`

A classe `TZebraToPdf` combina parser, estado da etiqueta e renderização:

- **Entrada e preparação**
  - `Generate()` aceita ZPL direto ou caminho de arquivo.
  - Substitui variáveis como `@CLIENTE`.
  - Processa múltiplas seções `^XA...^XZ`.
  - Extrai `^PW` e `^LL`.
- **Estado de impressão**
  - Posição atual (`^FO`, `^FT`).
  - Fonte e orientação (`^A`, `^CF`, `^FW`).
  - Configuração de código de barras (`^BY`, `^BC`, `^B3`, `^BQ`, `^BX`, etc.).
  - Reversão de campo (`^FR`) e decodificação hexadecimal (`^FH`).
- **Parser**
  - `ParseCommand()` identifica os comandos ZPL e atualiza o estado.
  - O parser atualmente é baseado em busca textual de `^` e tratamento especial para `^FD...^FS`, não sendo um analisador formal/tokenizado.
- **Renderização**
  - Texto: `DrawTextZPL()`.
  - Códigos de barras: `DrawBarcodeZPL()`.
  - Caixas, círculos e elipses: `DrawBoxZPL()`, `DrawCircleZPL()` e `DrawEllipseZPL()`.
  - Gráficos `^GF`: descompressão e rasterização em `DrawGraphicZPL()`.
  - Conversão de coordenadas: `MM_X()` e `MM_Y()` transformam dots ZPL em pontos PDF.

### Programa de teste

`teste\teste.prg` contém dois exemplos:

- `Main()`: cria ou lê `teste.zpl` e gera `teste.pdf`.
- `Main02()`: gera uma etiqueta complexa diretamente em Harbour.

`teste\compteste.bat` compila com `hbmk2`, vinculando `hbhpdf`, `hbzebra`, `xhb` e um arquivo externo de modo de erro. O script possui caminhos absolutos para uma instalação local do Harbour.

## Stack tecnológico

- **Linguagem:** Harbour/xBase, compatível conceitualmente com Clipper.
- **Geração de PDF:** HaruPDF através de `hbhpdf`/`libhpdf`.
- **Códigos de barras:** `hbzebra`.
- **Build:** `hbmk2`.
- **Plataforma atualmente documentada:** Windows/MinGW, com dependências instaladas externamente.
- **Formato processado:** subconjunto de ZPL II.
- **Saída:** PDF com uma página por etiqueta.
- **Testes:** exemplos manuais e artefato PDF; não há suíte automatizada, manifesto de dependências, CI ou configuração de build portátil.

## Principais pontos

faixa útil do ZPL:

- Textos com fontes, escala, alinhamento e orientação.
- Code 39, Code 93, Code 128, EAN, UPC, PDF417, QR Code e DataMatrix via `hbzebra`.
- Formas geométricas básicas.
- Etiquetas múltiplas no mesmo fluxo.
- Substituição de valores em tempo de execução.
- Dados hexadecimais e gráficos comprimidos em formato ZPL.
- Conversão de resolução (`^JM`) e dimensões da etiqueta.



# TZebraToPdf

Um conversor nativo de código ZPL (Zebra Programming Language) para PDF desenvolvido em **Harbour**. Esta classe permite renderizar etiquetas térmicas, códigos de barras e formas geométricas diretamente em arquivos PDF, eliminando a necessidade de impressoras físicas para testes ou emissão de documentos digitais.

![Harbour](https://img.shields.io/badge/Language-Harbour-blue.svg)
![PDF](https://img.shields.io/badge/Output-PDF-red.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## 📌 Funcionalidades

* **Emulação de Fontes:** Gerenciamento de estado independente para fontes escaláveis (`0`) e matriciais (`A-Z` e `1-9`), incluindo cálculo de proporção automática e simulação de alongamento horizontal (stretching).
* **Códigos de Barras Nativo:** Renderização de Code 128 (`^BC`), Code 39 (`^B3`), DataMatrix (`^BX`), PDF417 (`^B7`) e QR Code (`^BQ`) usando a biblioteca `hbzebra`.
* **Substituição Dinâmica de Dados:** Suporte à injeção de variáveis em tempo de execução via array (ex: substituir `@NOME` pelo valor correspondente no ZPL).
* **Orientação e Cores:** Suporte a textos rotacionados (Normal, Rotated, Inverted, Bottom-up) e comando de inversão de cor (Reverse Print - `^FR`).
* **Leitura Híbrida:** Capacidade de processar tanto strings ZPL diretas na memória quanto arquivos físicos `.zpl` / `.txt` (com leitura otimizada via `FREADLINE`).

## ⚙️ Dependências

Para compilar e utilizar esta classe, seu ambiente Harbour deve possuir as seguintes bibliotecas auxiliares vinculadas (flags do `hbmk2`):

* `hbhpdf` e `libhpdf` (HaruPDF para geração gráfica)
* `hbzebra` (Para renderização de códigos de barras)

Exemplo de flags adicionais no seu `.hbp` ou linha de comando:
```text
-lhbhpdf
-lhbzebra
-llibhpdf

```

## 🚀 Como Usar

Abaixo está um exemplo básico de como instanciar a classe e gerar o PDF a partir de uma string ZPL:

```harbour
#include "hbclass.ch"

PROCEDURE Main()
   LOCAL oZplToPdf
   LOCAL cZplCode
   LOCAL cArquivoPdf := "etiqueta_saida.pdf"
   LOCAL aVariaveis
   
   // String ZPL de exemplo
   cZplCode := "^XA" + ;
               "^FO50,50^A0N,40,40^FDDestinatario: @CLIENTE^FS" + ;
               "^FO50,100^BCN,100,Y,N,N^FD@CODIGO^FS" + ;
               "^XZ"
               
   // Array de substituição opcional (Tag -> Valor)
   aVariaveis := { ;
      { "@CLIENTE", "Joao da Silva" }, ;
      { "@CODIGO", "123456789" } ;
   }

   // Instancia a classe informando o DPI (Padrão: 203 DPI)
   oZplToPdf := TZebraToPdf():New( 203 )
   
   // Gera o PDF (pode passar o ZPL em texto ou o caminho de um arquivo .zpl)
   IF oZplToPdf:Generate( cZplCode, cArquivoPdf, aVariaveis )
      ? "Sucesso! PDF gerado em: " + cArquivoPdf
   ELSE
      ? "Erro ao gerar o PDF."
   ENDIF

RETURN

```

## 📖 Principais Comandos ZPL Suportados

A classe processa um subconjunto amplo e funcional do padrão ZPL II:

| Comando | Descrição | Implementação na Classe |
| --- | --- | --- |
| `^XA` / `^XZ` | Início / Fim do formato | Cria e finaliza a página PDF (`HPDF_AddPage`). |
| `^JM` | Resolução (Dots/Millimeter) | Ajusta a escala global (`A`=600dpi, `B`=300dpi, `C`=152dpi, Padrão=203dpi). |
| `^PW` / `^LL` | Page Width / Label Length | Redimensiona o quadro do PDF dinamicamente. |
| `^CF` / `^A` | Configuração de Fontes | Guarda o estado de dimensões por fonte (`hFontStates`). |
| `^FO` / `^FT` | Field Origin / Typeset | Move o ponteiro X, Y com cálculos de conversão de DPI para Pontos PDF. |
| `^FD` / `^FS` | Field Data / Separator | Escreve o texto/código e decodifica Hex (se prefixo definido). |
| `^GB` | Graphic Box | Desenha retângulos com suporte a espessura de linha preenchida ou vazada. |
| `^FR` | Field Reverse | Aplica GState de BlendMode no PDF para inversão de cor (Preto para Branco). |
| `^BY` | Barcode Field Default | Configura largura e altura padrão dos módulos de código de barras. |

## 🛠️ Detalhes de Implementação de Fontes

A classe faz distinção entre a fonte escalável `0` (renderizada usando **Helvetica-Bold** no HaruPDF) e as fontes matriciais de base da impressora térmica `A-Z` e `1-9` (renderizadas usando **Helvetica** regular para simular o espaçamento/peso visual de antigas impressoras). O fator de estiramento horizontal (`nHScale`) é calculado automaticamente caso a largura do caractere seja omitida no ZPL.

```

```