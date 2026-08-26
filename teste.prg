#include "hbclass.ch"
#include "hbzebra.ch"
#include "harupdf.ch"

// ============================================================================
// PROGRAMA DE TESTE - EXEMPLO 01 (Simples)
// ============================================================================
PROCEDURE Main()
   Local oConverter
   Local cZplString, cZplFile := "teste.zpl"
   Local cPdfFile := "teste.pdf"
   Local lSuccess

   if .not. file( cZplFile )
     cZplString := "^XA" + hb_Eol() + ;
                   "^FO50,50^GB400,200,2^FS" + hb_Eol() + ;
                   "^FO70,70^FDTeste de Impressao em PDF^FS" + hb_Eol() + ;
                   "^BY2,2,80" + hb_Eol() + ;
                   "^FO70,120^BC^FD1234567890^FS" + hb_Eol() + ;
                   "^XZ"
     hb_MemoWrit( cZplFile, cZplString )
   endif
   
   ? "Iniciando conversao de ZPL para PDF (Main)..."
   
   oConverter := TZebraToPdf():New( 300 )
   lSuccess := oConverter:Generate( hb_MemoRead( cZplFile ), cPdfFile )
   
   If lSuccess
      ? "Sucesso! O arquivo " + cPdfFile + " foi gerado."
   Else
      ? "Falha ao gerar o PDF."
   Endif
   ? "versao 07"
   
RETURN

// ============================================================================
// PROGRAMA DE TESTE - EXEMPLO 02 (Etiqueta Complexa)
// ============================================================================
PROCEDURE Main02()
   Local oConverter
   Local cZplString, cZplFile := "teste_complexo.zpl"
   Local cPdfFile := "teste_complexo.pdf"
   Local lSuccess

   cZplString := "^XA" + hb_Eol() + ;
                 "^FX Top section com logo e texto reverso" + hb_Eol() + ;
                 "^CF0,60" + hb_Eol() + ;
                 "^FO50,50^GB100,100,100^FS" + hb_Eol() + ;
                 "^FO75,75^FR^GB100,100,100^FS" + hb_Eol() + ;
                 "^FO93,93^GB40,40,40^FS" + hb_Eol() + ;
                 "^FO220,50^FDIntershipping, Inc.^FS" + hb_Eol() + ;
                 "^CF0,30" + hb_Eol() + ;
                 "^FO220,115^FD1000 Shipping Lane^FS" + hb_Eol() + ;
                 "^FO50,250^GB700,3,3^FS" + hb_Eol() + ;
                 "^FX Secao de codigo de barras" + hb_Eol() + ;
                 "^BY5,2,270" + hb_Eol() + ;
                 "^FO100,550^BC^FD12345678^FS" + hb_Eol() + ;
                 "^FX Letra Gigante CA" + hb_Eol() + ;
                 "^CF0,190" + hb_Eol() + ;
                 "^FO470,955^FDCA^FS" + hb_Eol() + ;
                 "^XZ"
                 
   hb_MemoWrit( cZplFile, cZplString )
   
   ? "Iniciando conversao de ZPL para PDF (Main02)..."
   
   oConverter := TZebraToPdf():New( 203 )
   lSuccess := oConverter:Generate( hb_MemoRead( cZplFile ), cPdfFile )
   
   If lSuccess
      ? "Sucesso! O arquivo " + cPdfFile + " foi gerado."
   Else
      ? "Falha ao gerar o PDF."
   Endif
   
RETURN

