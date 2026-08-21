```markdown
# 🏷️ ZPL Document Class for Harbour

Uma classe leve, robusta e **100% em Harbour puro** desenvolvida para criar, manipular e exportar etiquetas térmicas baseadas na linguagem **ZPL II (Zebra Programming Language)**.

Esta classe foi estruturada para suportar tanto a montagem programática de etiquetas (textos, códigos de barras, QR Codes, linhas e caixas) quanto a injeção de códigos ZPL brutos (`AddRaw`), permitindo total compatibilidade com modelos parametrizados e a integração direta com pré-visualizações em PDF via API.

---

## ✨ Principais Características

* **Zero Dependências Externas:** Não exige bibliotecas complexas de terceiros para estruturar os comandos da impressora térmica.
* **100% Harbour:** Escrita nativamente em Harbour, garantindo portabilidade entre sistemas operacionais.
* **Métodos de Alto e Baixo Nível:** Oferece funções dedicadas para elementos comuns (textos, códigos de barras Code 128, QR Codes, caixas e linhas) além do método coringa `AddRaw()` para injeção de códigos ZPL brutos ou templates prontos.
* **Preview em PDF Integrado:** Possui suporte nativo à conversão e geração de pré-visualizações em PDF utilizando o motor de requisições seguras com controle de timeout.
* **Impressão Direta RAW:** Envio simplificado de arquivos e buffers ZPL diretamente para a porta ou spooler da impressora térmica Zebra.

---

## 🚀 Como Utilizar

### Exemplo 1: Montando uma Etiqueta Programaticamente

```harbour
#include "simpleio.ch"

PROCEDURE Main()
   LOCAL oZPL

   // 1. Cria uma etiqueta de 100mm x 50mm com resolução de 203 DPI (8 dpmm)
   oZPL := ZPLDocument():New( 100, 50, 8 )

   // 2. Adiciona elementos visuais e textos
   oZPL:AddBox( 10, 10, 780, 380, 3 )
   oZPL:AddText( 30, 30, "EMPRESA DE TESTE LTDA", 35 )
   oZPL:AddLine( 30, 70, 740, 0, 2 )
   
   oZPL:AddText( 30, 90, "PRODUTO: TECLADO MECÂNICO RGB", 28 )
   oZPL:AddText( 30, 130, "PREÇO: R$ 250,00", 35 )

   // 3. Adiciona Código de Barras e QR Code
   oZPL:AddBarcode128( 30, 180, "7891234567890", 100, .T. )
   oZPL:AddQRCode( 600, 180, "[https://meusistema.com.br](https://meusistema.com.br)", 5 )

   // 4. Salva o arquivo de Preview em PDF ou envia para a impressora
   oZPL:SaveToPDF( "etiqueta_preview.pdf" )
   oZPL:PrintRAW( "Zebra_TLP_2844" )

   OutStd( "Etiqueta ZPL gerada com sucesso!" )
RETURN

```

### Exemplo 2: Utilizando Templates ZPL Prontos (Comandos Raw / Macros)

```harbour
PROCEDURE ImprimirTemplateZPL()
   LOCAL oZPL, cTextoZPL

   // Simula a leitura de um arquivo .zpl ou template parametrizado
   cTextoZPL := hb_MemoRead( "modelo_etiqueta.zpl" )

   oZPL := ZPLDocument():New()
   oZPL:AddRaw( cTextoZPL )

   // Gera o PDF para homologação em tela
   oZPL:SaveToPDF( "etiqueta_modelo.pdf" )
RETURN

```

---

## 📖 Referência de Métodos

### `ZPLDocument` (Classe Principal)

* **`New( nWidthMM, nHeightMM, nDpmm )`**
Inicializa o documento ZPL. Os parâmetros padrão criam uma etiqueta de 100x150mm a 8 dpmm (203 DPI) caso não sejam informados.
* **`StartLabel()`**
Insere os comandos de inicialização da etiqueta (`^XA`, `^PW`, `^LL`, `^LS0`).
* **`EndLabel()`**
Garante o fechamento correto do bloco ZPL com o comando `^XZ`.
* **`AddText( nX, nY, cText, nSize, cFont, cOrient )`**
Adiciona uma linha de texto nas coordenadas especificadas.
* **`AddBarcode128( nX, nY, cCode, nHeight, lShowText )`**
Insere um código de barras no padrão Code 128.
* **`AddQRCode( nX, nY, cCode, nSize )`**
Insere um código QR estruturado.
* **`AddBox( nX, nY, nWidth, nHeight, nThickness )`**
Desenha uma caixa/retângulo preenchido ou com bordas nas dimensões informadas.
* **`AddLine( nX, nY, nWidth, nHeight, nThickness )`**
Atalho para criação de linhas horizontais ou verticais.
* **`AddRaw( cZplCmd )`**
Permite injetar blocos de código ZPL puro diretamente no buffer da classe.
* **`SaveToPDF( cFilePDF )`**
Converte o buffer ZPL em um arquivo PDF utilizando a engine web com controle otimizado de timeout.
* **`PrintRAW( cPrinterName )`**
Envia o conteúdo ZPL diretamente para a fila da impressora térmica no modo RAW.

---

## 📄 Licença

Este código é de uso livre e integrado a sistemas comerciais, utilitários de relatórios e automações de impressão em Harbour.

```

```