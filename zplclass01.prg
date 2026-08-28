#include "hbclass.ch"
#include "hbzebra.ch"
#include "harupdf.ch"

// ============================================================================
// CLASSE COMPLETA: TZebraToPdf (Com correções integradas)
// ============================================================================
CLASS TZebraToPdf
   DATA hPdf
   DATA hPage
   DATA nHeight
   DATA nX INIT 0
   DATA nY INIT 0
   DATA nBarWidth INIT 2
   DATA nBarHeight INIT 100
   
   DATA nDpi INIT 203
   DATA nScale 
   
   DATA cBarcodeType INIT ""
   DATA nFontSize INIT 15
   DATA lReverse INIT .F.

   METHOD New( nDpi ) CONSTRUCTOR
   METHOD Generate( cZplText, cPdfFile )
   METHOD ParseCommand( cCmd )
   METHOD DrawTextZPL( cText )
   METHOD DrawBoxZPL( nW, nH, nThickness )
   METHOD DrawBarcodeZPL( cData, cType )
   METHOD MM_X( nDotX )
   METHOD MM_Y( nDotY )
ENDCLASS

METHOD New( nDpi ) CLASS TZebraToPdf
   If nDpi != Nil
      ::nDpi := nDpi
   Endif
   ::nScale := 72 / ::nDpi 
Return Self


METHOD Generate( cZplText, cPdfFile ) CLASS TZebraToPdf
   Local aLines, cLine, aCmds, i, j
   Local lIgnoreBin := .F.

   ::hPdf := HPDF_New()
   If Empty(::hPdf)
      Return .F.
   Endif

   HPDF_SetCompressionMode( ::hPdf, 15 )
   HPDF_SetCurrentEncoder( ::hPdf, "WinAnsiEncoding" )

   aLines := hb_ATokens( StrTran(cZplText, hb_Eol(), Chr(10)), Chr(10) )
   
   For i := 1 To Len(aLines)
      cLine := AllTrim(aLines[i])
      
      // Bloqueia a leitura ao encontrar impressão de binários
      If Left(cLine, 3) == "~DG" .OR. Left(cLine, 4) == "^GFA"
         lIgnoreBin := .T.
         LOOP
      Endif
      
      If lIgnoreBin
         // Retoma a leitura apenas se a linha iniciar com um novo comando
         If Left(cLine, 1) == "^" .OR. Left(cLine, 1) == "~"
            lIgnoreBin := .F.
         Else
            LOOP
         Endif
      Endif

      // Normaliza '~/^' para tratar múltiplos comandos na mesma linha
      cLine := StrTran(cLine, "~", "^")
      aCmds := hb_ATokens( cLine, "^" )
      
      For j := 1 To Len(aCmds)
         If !Empty(aCmds[j])
            ::ParseCommand( aCmds[j] )
         Endif
      Next j
   Next i

   HPDF_SaveToFile( ::hPdf, cPdfFile )
   HPDF_Free( ::hPdf )
Return Hb_FileExists(cPdfFile)


METHOD ParseCommand( cCmd ) CLASS TZebraToPdf
   Local cOpcode := Left(cCmd, 2)
   Local cParams := SubStr(cCmd, 3)
   Local aParams := hb_ATokens( cParams, "," )

   SWITCH cOpcode
      CASE "FX"
         EXIT
         
      CASE "JM"
         If Len(aParams) >= 1
            SWITCH Upper(aParams[1])
               CASE "A"; ::nDpi := 600; EXIT
               CASE "B"; ::nDpi := 300; EXIT
               CASE "C"; ::nDpi := 152; EXIT
            ENDSWITCH
            ::nScale := 72 / ::nDpi 
         Endif
         EXIT
         
      CASE "XA"
         ::hPage := HPDF_AddPage( ::hPdf )
         HPDF_Page_SetWidth( ::hPage, 812 * ::nScale ) 
         HPDF_Page_SetHeight( ::hPage, 1218 * ::nScale ) 
         ::nHeight := HPDF_Page_GetHeight( ::hPage )
         EXIT
         
      CASE "CF"
         If Len(aParams) >= 2
            ::nFontSize := Val(aParams[2])
         ElseIf Len(aParams) == 1
            ::nFontSize := 15 
         Endif
         EXIT
         
      CASE "A0" // Fontes Escalonáveis (Ex: ^A0R,45,45)
         If Len(aParams) >= 2
            ::nFontSize := Val(aParams[2])
         Endif
         EXIT
         
      CASE "FR"
         ::lReverse := .T.
         EXIT
         
      CASE "FO"
      CASE "FT" // Tratado da mesma forma que FO no parse para gerar preview
         If Len(aParams) >= 2
            ::nX := Val(aParams[1])
            ::nY := Val(aParams[2])
         Endif
         EXIT
         
      CASE "FH" // Ignora o indicador de Hexadecimal para o preview
         EXIT
         
      CASE "FD"
         cParams := StrTran(cParams, "FS", "")
         If !Empty( ::cBarcodeType )
            ::DrawBarcodeZPL( cParams, ::cBarcodeType )
            ::cBarcodeType := ""
         Else
            ::DrawTextZPL( cParams )
         Endif
         ::lReverse := .F.
         EXIT
         
      CASE "GB"
         If Len(aParams) >= 3
            ::DrawBoxZPL( Val(aParams[1]), Val(aParams[2]), Val(aParams[3]) )
         ElseIf Len(aParams) == 2
            ::DrawBoxZPL( Val(aParams[1]), Val(aParams[2]), 1 )
         Endif
         ::lReverse := .F.
         EXIT
         
      CASE "BY"
         If Len(aParams) >= 1
            ::nBarWidth := Val(aParams[1])
         Endif
         If Len(aParams) >= 3
            ::nBarHeight := Val(aParams[3])
         Endif
         EXIT
         
      CASE "B3"
         ::cBarcodeType := "B3"
         EXIT
         
      CASE "BC"
         ::cBarcodeType := "BC"
         EXIT

      CASE "BX" // Data Matrix
         ::cBarcodeType := "BX"
         EXIT
         
      CASE "B7" // PDF417
         ::cBarcodeType := "B7"
         EXIT
   ENDSWITCH
Return Nil


METHOD DrawBarcodeZPL( cData, cType ) CLASS TZebraToPdf
   Local hZebra, nFlags := 0
   Local x := ::MM_X( ::nX )
   Local y := ::MM_Y( ::nY ) 
   Local hFont, nTextSize := 12
   Local nRawHeight, nPdfBarHeight, nBottomY
   Local nWidthFactor, nTextWidth, nCenterTextX
   Local nHarbourModules := 0, nActualWidth

   nRawHeight := If( ValType(::nBarHeight) == "N" .AND. ::nBarHeight > 0, ::nBarHeight, 100 )
   nPdfBarHeight := Abs( ::MM_Y( nRawHeight ) - ::MM_Y( 0 ) )
   nBottomY := y - nPdfBarHeight

   // Inclusão de BX e B7
   SWITCH cType
      CASE "BC"; hZebra := hb_zebra_create_code128( cData, nFlags ); EXIT
      CASE "B3"; hZebra := hb_zebra_create_code39( cData, nFlags ); EXIT
      CASE "BX"; hZebra := hb_zebra_create_datamatrix( cData, nFlags ); EXIT
      CASE "B7"; hZebra := hb_zebra_create_pdf417( cData, nFlags ); EXIT
      OTHERWISE; hZebra := hb_zebra_create_code128( cData, nFlags )
   ENDSWITCH

   If hZebra != Nil .AND. hb_zebra_geterror( hZebra ) == 0
      HPDF_Page_SetRGBFill( ::hPage, 0, 0, 0 )
      
      hb_zebra_draw( hZebra, {| cx, cy, cw, ch | nHarbourModules := Max(cx + cw, nHarbourModules) }, 0, 0, 1, 1 )
      If nHarbourModules <= 0
         nHarbourModules := 100
      Endif

      nWidthFactor := ::nScale * 0.9

      hb_zebra_draw( hZebra, {| bx, by, bw, bh | HPDF_Page_Rectangle( ::hPage, bx, by, bw, bh ) }, x, nBottomY, nWidthFactor, nPdfBarHeight )
      HPDF_Page_Fill( ::hPage )

      nActualWidth := nHarbourModules * nWidthFactor
      hFont := HPDF_GetFont( ::hPdf, "Helvetica-Bold", "WinAnsiEncoding" )
      HPDF_Page_SetFontAndSize( ::hPage, hFont, nTextSize )
      
      nTextWidth := HPDF_Page_TextWidth( ::hPage, cData )
      nCenterTextX := x + (nActualWidth / 2) - (nTextWidth / 2)
      
      HPDF_Page_BeginText( ::hPage )
      HPDF_Page_TextOut( ::hPage, nCenterTextX, nBottomY - 15, cData ) 
      HPDF_Page_EndText( ::hPage )
      
      hb_zebra_destroy( hZebra )
   Endif
Return Nil


METHOD DrawTextZPL( cText ) CLASS TZebraToPdf
   Local hFont := HPDF_GetFont( ::hPdf, "Helvetica-Bold", "WinAnsiEncoding" )
   Local x := ::MM_X( ::nX )
   Local nPdfFontSize := ::nFontSize * ::nScale 
   Local y := ::MM_Y( ::nY ) - (nPdfFontSize * 0.8)

   If ::lReverse
      HPDF_Page_SetRGBFill( ::hPage, 1, 1, 1 )
   Else
      HPDF_Page_SetRGBFill( ::hPage, 0, 0, 0 )
   Endif

   HPDF_Page_SetFontAndSize( ::hPage, hFont, nPdfFontSize )
   HPDF_Page_BeginText( ::hPage )
   HPDF_Page_TextOut( ::hPage, x, y, cText )
   HPDF_Page_EndText( ::hPage )
Return Nil

METHOD DrawBoxZPL( nW, nH, nThickness ) CLASS TZebraToPdf
   Local x := ::MM_X( ::nX )
   Local y := ::MM_Y( ::nY )
   Local w := nW * ::nScale
   Local h := nH * ::nScale
   Local t := nThickness * ::nScale
   
   If ::lReverse
      HPDF_Page_SetRGBFill( ::hPage, 1, 1, 1 )
      HPDF_Page_SetRGBStroke( ::hPage, 1, 1, 1 )
   Else
      HPDF_Page_SetRGBFill( ::hPage, 0, 0, 0 )
      HPDF_Page_SetRGBStroke( ::hPage, 0, 0, 0 )
   Endif

   If nThickness >= (nW / 2) .OR. nThickness >= (nH / 2)
      HPDF_Page_Rectangle( ::hPage, x, y - h, w, h )
      HPDF_Page_Fill( ::hPage )
   Else
      HPDF_Page_SetLineWidth( ::hPage, Max(t, 0.5) )
      HPDF_Page_Rectangle( ::hPage, x + (t/2), y - h + (t/2), w - t, h - t )
      HPDF_Page_Stroke( ::hPage )
   Endif
Return Nil


METHOD MM_X( nDotX ) CLASS TZebraToPdf
Return (nDotX * ::nScale)

METHOD MM_Y( nDotY ) CLASS TZebraToPdf
Return ::nHeight - (nDotY * ::nScale)