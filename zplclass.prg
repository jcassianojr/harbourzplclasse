#include "hbclass.ch"
#include "hbzebra.ch"
#include "harupdf.ch"

// ============================================================================
// CLASSE COMPLETA: TZebraToPdf (Parser de Fontes CF Robusto + FREADLINE)
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
   DATA lInverted INIT .F. 
   DATA cOrientation INIT "N" 
   DATA cHexPrefix INIT "" 
   DATA lPrintBarcodeText INIT .T.
   DATA hExtReverse INIT Nil
   DATA hExtNormal INIT Nil
   
   
   DATA hFontStates INIT {=>} 
   DATA cCurrentFont INIT "A"
   DATA nFontHeight INIT 15
   DATA nFontWidth INIT 15

   METHOD New( nDpi ) CONSTRUCTOR
   METHOD Generate( cZplTextOrFile, cPdfFile, aCAMVALOR ) 
   METHOD ParseCommand( cCmd )
   METHOD DrawTextZPL( cText )
   METHOD DrawBoxZPL( nW, nH, nThickness )
   METHOD DrawBarcodeZPL( cData, cType )
   METHOD MM_X( nDotX )
   METHOD MM_Y( nDotY )
   METHOD DecodeZPLHex( cText )
   METHOD ConvertCP850ToWinAnsi( cHex )
   METHOD ApplyReverseState()
ENDCLASS

METHOD New( nDpi ) CLASS TZebraToPdf
   If nDpi != Nil
      ::nDpi := nDpi
   Endif
   ::nScale := 72 / ::nDpi 
Return Self

METHOD ApplyReverseState() CLASS TZebraToPdf
   If ::lReverse
      If ::hExtReverse == Nil
         ::hExtReverse := HPDF_CreateExtGState( ::hPdf )
         HPDF_ExtGState_SetBlendMode( ::hExtReverse, 10 ) 
      Endif
      HPDF_Page_SetExtGState( ::hPage, ::hExtReverse )
      HPDF_Page_SetRGBFill( ::hPage, 1, 1, 1 )
      HPDF_Page_SetRGBStroke( ::hPage, 1, 1, 1 )
   Else
      If ::hExtNormal == Nil
         ::hExtNormal := HPDF_CreateExtGState( ::hPdf )
         HPDF_ExtGState_SetBlendMode( ::hExtNormal, 0 ) 
      Endif
      HPDF_Page_SetExtGState( ::hPage, ::hExtNormal )
      HPDF_Page_SetRGBFill( ::hPage, 0, 0, 0 )
      HPDF_Page_SetRGBStroke( ::hPage, 0, 0, 0 )
   Endif
Return Nil

METHOD Generate( cZplTextOrFile, cPdfFile, aCAMVALOR ) CLASS TZebraToPdf
   Local aLines, cLine, aCmds, i, j, cItem
   Local lIgnoreBin := .F.
   Local aItemData, cKey, uVal, cValStr
   Local nFileUso, cDelim, cZplText := ""

   If ValType( aCAMVALOR ) == "A"
      For i := 1 To Len( aCAMVALOR )
         aItemData := aCAMVALOR[ i ]
         
         If ValType( aItemData ) == "A" .AND. Len( aItemData ) >= 2
            cKey := aItemData[ 1 ]
            uVal := aItemData[ 2 ]
            
            If ValType( cKey ) == "C"
               cKey := If( Left( cKey, 1 ) == "@", cKey, "@" + cKey )
               
               SWITCH ValType( uVal )
                  CASE "C"; cValStr := uVal; EXIT
                  CASE "N"; cValStr := AllTrim( Str( uVal ) ); EXIT
                  CASE "D"; cValStr := DToC( uVal ); EXIT
                  CASE "L"; cValStr := If( uVal, "S", "N" ); EXIT
                  OTHERWISE; cValStr := hb_ValToStr( uVal ) 
               ENDSWITCH
               
               cZplTextOrFile := StrTran( cZplTextOrFile, cKey, cValStr )
               cZplTextOrFile := StrTran( cZplTextOrFile, Upper( cKey ), cValStr )
            Endif
         Endif
      Next i
   Endif

   ::hPdf := HPDF_New()
   If Empty(::hPdf)
      Return .F.
   Endif

   HPDF_SetCompressionMode( ::hPdf, 15 )
   HPDF_SetCurrentEncoder( ::hPdf, "WinAnsiEncoding" )

   // Se for um arquivo existente, lê linha a linha usando a FREADLINE
   If Hb_FileExists( cZplTextOrFile )
      cDelim := FDELIM( cZplTextOrFile, 1024 )
      nFileUso := FOpen( cZplTextOrFile )
      If nFileUso != -1
         While .T.
            cLine := FREADLINE( nFileUso, 1024, .T., cDelim )
            If cLine == "__FINAL__"
               EXIT
            Endif

            cLine := AllTrim( cLine )
            cLine := StrTran( cLine, "~", "^" )

            If Left(cLine, 3) == "~DG" .OR. Left(cLine, 4) == "^GFA"
               lIgnoreBin := .T.
               LOOP
            Endif
            
            If lIgnoreBin
               If Left(cLine, 1) == "^" .OR. Left(cLine, 1) == "~"
                  lIgnoreBin := .F.
               Else
                  LOOP
               Endif
            Endif

            If !Empty( cLine )
               aCmds := hb_ATokens( cLine, "^" )
               For j := 1 To Len(aCmds)
                  cItem := AllTrim(aCmds[j])
                  If !Empty(cItem)
                     ::ParseCommand( cItem )
                  Endif
               Next j
            Endif
         Enddo
         FClose( nFileUso )
      Endif
   Else
      // Caso receba o ZPL diretamente como string
      cZplText := StrTran( cZplTextOrFile, "~", "^" )
      aLines := hb_ATokens( cZplText, Chr(10) )
      
      For i := 1 To Len(aLines)
         cLine := AllTrim(aLines[i])
         cLine := StrTran( cLine, Chr(13), "" )
         
         If Left(cLine, 3) == "~DG" .OR. Left(cLine, 4) == "^GFA"
            lIgnoreBin := .T.
            LOOP
         Endif
         
         If lIgnoreBin
            If Left(cLine, 1) == "^" .OR. Left(cLine, 1) == "~"
               lIgnoreBin := .F.
            Else
               LOOP
            Endif
         Endif

         If !Empty( cLine )
            aCmds := hb_ATokens( cLine, "^" )
            For j := 1 To Len(aCmds)
               cItem := AllTrim(aCmds[j])
               If !Empty(cItem)
                  ::ParseCommand( cItem )
               Endif
            Next j
         Endif
      Next i
   Endif

   HPDF_SaveToFile( ::hPdf, cPdfFile )
   HPDF_Free( ::hPdf )
Return Hb_FileExists(cPdfFile)

METHOD ParseCommand( cCmd ) CLASS TZebraToPdf
   Local cParams, aParams, cRest, k, cOpcode
   Local cFontID
   Local cOrient

   cCmd := AllTrim(cCmd)
   If Empty(cCmd)
      Return Nil
   Endif

   // Tratamento para ^CF (Define a fonte padrão e salva seu estado persistente)
   If Upper(Left(cCmd, 2)) == "CF"
      cFontID := "A" 
      cRest := SubStr(cCmd, 3)
      
      If Len(cRest) >= 1 .AND. (SubStr(cRest, 1, 1) $ "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
         cFontID := SubStr(cRest, 1, 1)
         cRest := SubStr(cRest, 2)
      Endif
      
      If Left(cRest, 1) == ","
         cRest := SubStr(cRest, 2)
      Endif
      
      aParams := hb_ATokens( AllTrim(cRest), "," )
      
      If !hb_HHasKey( ::hFontStates, cFontID )
         ::hFontStates[ cFontID ] := { 15, 15 } // { Altura, Largura }
      Endif
      
      // 1. Atualiza Altura e auto-ajusta a Largura caso ela tenha sido omitida no ZPL
      If Len(aParams) >= 1 .AND. !Empty(aParams[1]) .AND. Val(aParams[1]) > 0
         ::hFontStates[ cFontID ][1] := Val(aParams[1])
         
         If Len(aParams) < 2 .OR. Empty(aParams[2]) .OR. Val(aParams[2]) <= 0
            IF cFontID == "0"
               ::hFontStates[ cFontID ][2] := Val(aParams[1]) // Fonte 0 -> proporção 1:1
            ELSE
               ::hFontStates[ cFontID ][2] := Val(aParams[1]) * 0.6 // Fontes A-Z -> proporção 0.6:1
            ENDIF
         Endif
      Endif
      
      // 2. Se a largura for passada explicitamente, sobrescreve o auto-ajuste
      If Len(aParams) >= 2 .AND. !Empty(aParams[2]) .AND. Val(aParams[2]) > 0
         ::hFontStates[ cFontID ][2] := Val(aParams[2])
      Endif
      
      // Define a fonte atual e passa os dados da memória para as variáveis ativas
      ::cCurrentFont := cFontID
      ::nFontHeight  := ::hFontStates[ cFontID ][1]
      ::nFontWidth   := ::hFontStates[ cFontID ][2]
      ::nFontSize    := ::nFontHeight 
      
      Return Nil
   Endif

   // Tratamento para ^A (Invoca temporariamente uma fonte para o campo atual)
   If Upper(Left(cCmd, 1)) == "A" .AND. Len(cCmd) >= 2 .AND. (SubStr(cCmd, 2, 1) $ "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@")
      cFontID := SubStr(cCmd, 2, 1)
      cRest := SubStr(cCmd, 3)
      
      cOrient := "N"
      If Len(cRest) >= 1 .AND. (SubStr(cRest, 1, 1) $ "NRIB")
         cOrient := SubStr(cRest, 1, 1)
         cRest := SubStr(cRest, 2)
      Endif
      
      If Left(cRest, 1) == ","
         cRest := SubStr(cRest, 2)
      Endif
      
      aParams := hb_ATokens( AllTrim(cRest), "," )
      
      If !hb_HHasKey( ::hFontStates, cFontID )
         ::hFontStates[ cFontID ] := { 15, 15 }
      Endif
      
      ::cCurrentFont := cFontID
      ::cOrientation := cOrient
      
      // 1. Carrega as dimensões herdadas salvas para esta fonte específica
      ::nFontHeight := ::hFontStates[ cFontID ][1]
      ::nFontWidth  := ::hFontStates[ cFontID ][2]
      
      // 2. Atualiza Altura temporária e auto-ajusta Largura temporária se omitida
      If Len(aParams) >= 1 .AND. !Empty(aParams[1]) .AND. Val(aParams[1]) > 0
         ::nFontHeight := Val(aParams[1])
         
         If Len(aParams) < 2 .OR. Empty(aParams[2]) .OR. Val(aParams[2]) <= 0
            IF cFontID == "0"
               ::nFontWidth := Val(aParams[1])
            ELSE
               ::nFontWidth := Val(aParams[1]) * 0.6
            ENDIF
         Endif
      Endif
      
      // 3. Se informou a largura, sobrescreve
      If Len(aParams) >= 2 .AND. !Empty(aParams[2]) .AND. Val(aParams[2]) > 0
         ::nFontWidth := Val(aParams[2])
      Endif
      
      ::nFontSize := ::nFontHeight
      Return Nil
   Endif

   cOpcode := Upper(Left(cCmd, 2))
   cParams := SubStr(cCmd, 3)
   aParams := hb_ATokens( cParams, "," )

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
         
         HPDF_Page_SetRGBFill( ::hPage, 1, 1, 1 )
         HPDF_Page_Rectangle( ::hPage, 0, 0, HPDF_Page_GetWidth( ::hPage ), ::nHeight )
         HPDF_Page_Fill( ::hPage )
         HPDF_Page_SetRGBFill( ::hPage, 0, 0, 0 ) 
         EXIT
         
      CASE "FR"
         ::lReverse := .T.
         EXIT
         
      CASE "FO"
      CASE "FT" 
         ::cOrientation := "N" 
         If Len(aParams) >= 2
            ::nX := Val(aParams[1])
            ::nY := Val(aParams[2])
         Endif
         EXIT
         
      CASE "FD"
         If Right( cParams, 2 ) == "FS"
            cParams := Left( cParams, Len( cParams ) - 2 )
         Endif
         
         cParams := StripBBCode( cParams )
         
         If !Empty( ::cHexPrefix )
            cParams := ::DecodeZPLHex( cParams )
         Endif
         
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

      CASE "BX" 
         ::cBarcodeType := "BX"
         EXIT
         
      CASE "PW" 
         If Len(aParams) >= 1
            HPDF_Page_SetWidth( ::hPage, Val(aParams[1]) * ::nScale )
         Endif
         EXIT
         
      CASE "LL" 
         If Len(aParams) >= 1
            HPDF_Page_SetHeight( ::hPage, Val(aParams[1]) * ::nScale )
            ::nHeight := HPDF_Page_GetHeight( ::hPage ) 
         Endif
         EXIT
         
   ENDSWITCH
Return Nil

METHOD DrawTextZPL( cText ) CLASS TZebraToPdf
   Local cFontName := "Helvetica-Bold"
   Local hFont, x, y, nPdfFontSize, nHScale

   // Fonte 0 = Negrito (Escalável)
   // Fontes A-Z = Regular (Matricial)
   IF ::cCurrentFont == "0"
      cFontName := "Helvetica-Bold" 
   ELSE
      cFontName := "Helvetica" // Revertido para remover o negrito indesejado
   ENDIF

   hFont := HPDF_GetFont( ::hPdf, cFontName, "WinAnsiEncoding" )
   
   x := ::MM_X( ::nX )
   nPdfFontSize := ::nFontSize * ::nScale 
   
   y := ::MM_Y( ::nY ) - (nPdfFontSize * 0.8)

   nHScale := 1.0
   IF ::nFontHeight > 0 .AND. ::nFontWidth > 0 
      nHScale := ::nFontWidth / (::nFontHeight * If(::cCurrentFont == "0", 1.0, 0.6))
   ENDIF

   ::ApplyReverseState()

   HPDF_Page_SetFontAndSize( ::hPage, hFont, nPdfFontSize )
   HPDF_Page_BeginText( ::hPage )
   
   SWITCH ::cOrientation
      CASE "R" 
         HPDF_Page_SetTextMatrix( ::hPage, 0, -1, nHScale, 0, x, y )
         EXIT
      CASE "I" 
         HPDF_Page_SetTextMatrix( ::hPage, -nHScale, 0, 0, -1, x, y )
         EXIT
      CASE "B" 
         HPDF_Page_SetTextMatrix( ::hPage, 0, 1, -nHScale, 0, x, y )
         EXIT
      OTHERWISE 
         HPDF_Page_SetTextMatrix( ::hPage, nHScale, 0, 0, 1, x, y )
   ENDSWITCH
   
   HPDF_Page_ShowText( ::hPage, cText )
   HPDF_Page_EndText( ::hPage )
Return Nil

METHOD DrawBoxZPL( nW, nH, nThickness ) CLASS TZebraToPdf
   Local x := ::MM_X( ::nX )
   Local y := ::MM_Y( ::nY )
   Local w := nW * ::nScale
   Local h := nH * ::nScale
   Local t := nThickness * ::nScale
   
   ::ApplyReverseState()

   If nThickness >= (nW / 2) .OR. nThickness >= (nH / 2)
      HPDF_Page_Rectangle( ::hPage, x, y - h, w, h )
      HPDF_Page_Fill( ::hPage )
   Else
      HPDF_Page_SetLineWidth( ::hPage, Max(t, 0.5) )
      HPDF_Page_Rectangle( ::hPage, x + (t/2), y - h + (t/2), w - t, h - t )
      HPDF_Page_Stroke( ::hPage )
   Endif
Return Nil

METHOD DrawBarcodeZPL( cData, cType ) CLASS TZebraToPdf
   LOCAL hZebra, nFlags := 0
   LOCAL x := ::MM_X( ::nX )
   LOCAL y := ::MM_Y( ::nY ) 
   LOCAL hFont, nPdfFontSize
   LOCAL nRawHeight, nPdfBarHeight
   LOCAL nWidthFactor, nTextWidth, nCenterTextX
   LOCAL nHarbourModules := 0, nActualWidth
   LOCAL lShowText := .T.

   nRawHeight := If( ValType(::nBarHeight) == "N" .AND. ::nBarHeight > 0, ::nBarHeight, 100 )
   nPdfBarHeight := Abs( ::MM_Y( nRawHeight ) - ::MM_Y( 0 ) )

   SWITCH cType
      CASE "BC"; hZebra := hb_zebra_create_code128( cData, nFlags )   ; EXIT
      CASE "B3"; hZebra := hb_zebra_create_code39( cData, nFlags )    ; EXIT
      CASE "BX"; hZebra := hb_zebra_create_datamatrix( cData, nFlags ); lShowText := .F.; EXIT
      CASE "B7"; hZebra := hb_zebra_create_pdf417( cData, nFlags )    ; lShowText := .F.; EXIT
      CASE "BQ"; hZebra := hb_zebra_create_qrcode( cData, nFlags )    ; lShowText := .F.; EXIT
      OTHERWISE; hZebra := hb_zebra_create_code128( cData, nFlags )
   ENDSWITCH

   If hZebra != Nil .AND. hb_zebra_geterror( hZebra ) == 0
      
      ::ApplyReverseState()
      
      hb_zebra_draw( hZebra, {| cx, cy, cw, ch | nHarbourModules := Max(cx + cw, nHarbourModules) }, 0, 0, 1, 1 )
      If nHarbourModules <= 0
         nHarbourModules := 100
      Endif
      
      If ::nBarWidth <= 0
         ::nBarWidth := 2
      Endif
      nWidthFactor := ::nBarWidth * ::nScale 
      
      If !lShowText
         nPdfBarHeight := nWidthFactor
      Endif

      HPDF_Page_GSave( ::hPage )

      SWITCH ::cOrientation
         CASE "R"
            HPDF_Page_Concat( ::hPage, 0, -1, 1, 0, x, y )
            EXIT
         CASE "I"
            HPDF_Page_Concat( ::hPage, -1, 0, 0, -1, x, y )
            EXIT
         CASE "B"
            HPDF_Page_Concat( ::hPage, 0, 1, -1, 0, x, y )
            EXIT
         OTHERWISE
            HPDF_Page_Concat( ::hPage, 1, 0, 0, 1, x, y )
      ENDSWITCH

      hb_zebra_draw( hZebra, {| bx, by, bw, bh | HPDF_Page_Rectangle( ::hPage, bx, by, bw, bh ) }, 0, -nPdfBarHeight, nWidthFactor, nPdfBarHeight )
      HPDF_Page_Fill( ::hPage )

      If lShowText .AND. ::lPrintBarcodeText
         nActualWidth := nHarbourModules * nWidthFactor
         hFont := HPDF_GetFont( ::hPdf, "Helvetica-Bold", "WinAnsiEncoding" )
         
         nPdfFontSize := 20 * ::nScale 
         HPDF_Page_SetFontAndSize( ::hPage, hFont, nPdfFontSize )
         
         nTextWidth := HPDF_Page_TextWidth( ::hPage, cData )
         nCenterTextX := (nActualWidth / 2) - (nTextWidth / 2)
         
         HPDF_Page_BeginText( ::hPage )
         HPDF_Page_SetTextMatrix( ::hPage, 1, 0, 0, 1, nCenterTextX, -nPdfBarHeight - (nPdfFontSize * 1.0) )
         HPDF_Page_ShowText( ::hPage, cData ) 
         HPDF_Page_EndText( ::hPage )
      Endif
      
      HPDF_Page_GRestore( ::hPage )
      hb_zebra_destroy( hZebra )
   Endif
Return Nil

METHOD MM_X( nDotX ) CLASS TZebraToPdf
Return (nDotX * ::nScale)

METHOD MM_Y( nDotY ) CLASS TZebraToPdf
Return ::nHeight - (nDotY * ::nScale)

METHOD DecodeZPLHex( cText ) CLASS TZebraToPdf
   Local nPos, cHex, cChar
   
   If Empty( ::cHexPrefix )
      Return cText
   Endif
   
   nPos := At( ::cHexPrefix, cText )
   While nPos > 0 .AND. nPos <= Len( cText ) - 2
      cHex := SubStr( cText, nPos + 1, 2 )
      
      If IsHex( cHex )
         cChar := ::ConvertCP850ToWinAnsi( cHex )
         cText := Left( cText, nPos - 1 ) + cChar + SubStr( cText, nPos + 3 )
      Else
         cText := Left( cText, nPos - 1 ) + Chr(255) + SubStr( cText, nPos + 1 )
      Endif
      
      nPos := At( ::cHexPrefix, cText )
   End
   
   cText := StrTran( cText, Chr(255), ::cHexPrefix )
   ::cHexPrefix := "" 
   
Return cText

METHOD ConvertCP850ToWinAnsi( cHex ) CLASS TZebraToPdf
   Local nNum := hb_HexToNum( cHex )
   Local nWinAnsi := nNum
   
   SWITCH nNum
      CASE 135; nWinAnsi := 231; EXIT // ç
      CASE 128; nWinAnsi := 199; EXIT // Ç
      CASE 198; nWinAnsi := 227; EXIT // ã
      CASE 199; nWinAnsi := 195; EXIT // Ã
      CASE 160; nWinAnsi := 225; EXIT // á
      CASE 181; nWinAnsi := 193; EXIT // Á
      CASE 130; nWinAnsi := 233; EXIT // é
      CASE 144; nWinAnsi := 201; EXIT // É
      CASE 161; nWinAnsi := 237; EXIT // í
      CASE 214; nWinAnsi := 205; EXIT // Í
      CASE 162; nWinAnsi := 243; EXIT // ó
      CASE 224; nWinAnsi := 211; EXIT // Ó
      CASE 228; nWinAnsi := 245; EXIT // õ
      CASE 229; nWinAnsi := 213; EXIT // Õ
      CASE 163; nWinAnsi := 250; EXIT // ú
      CASE 233; nWinAnsi := 218; EXIT // Ú
      CASE 136; nWinAnsi := 234; EXIT // ê
      CASE 210; nWinAnsi := 202; EXIT // Ê
      CASE 147; nWinAnsi := 244; EXIT // ô
      CASE 226; nWinAnsi := 212; EXIT // Ô
      CASE 167; nWinAnsi := 186; EXIT // º 
      CASE 166; nWinAnsi := 170; EXIT // ª 
   ENDSWITCH
   
Return Chr( nWinAnsi )

STATIC FUNCTION IsHex( cStr )
   Local i, c
   If Len(cStr) != 2
      Return .F.
   Endif
   For i := 1 To 2
      c := Upper( SubStr(cStr, i, 1) )
      If !(c >= "0" .AND. c <= "9") .AND. !(c >= "A" .AND. c <= "F")
         Return .F.
      Endif
   Next
Return .T.

FUNCTION StripBBCode( cLinha )
   LOCAL nPosIni, nPosFim, cTag, cComando, nPosIgual
   
   cLinha := StrTran( cLinha, "[B]", "" )
   cLinha := StrTran( cLinha, "[/B]", "" )
   cLinha := StrTran( cLinha, "[I]", "" )
   cLinha := StrTran( cLinha, "[/I]", "" )
   cLinha := StrTran( cLinha, "[U]", "" )
   cLinha := StrTran( cLinha, "[/U]", "" )
   cLinha := StrTran( cLinha, "[S]", "" )
   cLinha := StrTran( cLinha, "[/S]", "" )
   cLinha := StrTran( cLinha, "[CENTER]", "" )
   cLinha := StrTran( cLinha, "[/CENTER]", "" )
   cLinha := StrTran( cLinha, "[HR]", "" )
   cLinha := StrTran( cLinha, "[PAGE]", "" )
   cLinha := StrTran( cLinha, "##page##", "" )
   cLinha := StrTran( cLinha, "[/COLOR]", "" )
   cLinha := StrTran( cLinha, "[/SIZE]", "" )
   cLinha := StrTran( cLinha, "[/FONT]", "" )

   nPosIni := At( "[", cLinha )
   WHILE nPosIni > 0
      nPosFim := hb_At( "]", cLinha, nPosIni )
      IF nPosFim > 0
         cTag := SubStr( cLinha, nPosIni + 1, nPosFim - nPosIni - 1 )
         nPosIgual := At( "=", cTag )
         IF nPosIgual > 0
            cComando := Upper( SubStr( cTag, 1, nPosIgual - 1 ) )
            IF cComando == "COLOR" .OR. cComando == "SIZE" .OR. cComando == "FONT"
               cLinha := Left( cLinha, nPosIni - 1 ) + SubStr( cLinha, nPosFim + 1 )
               nPosIni := hb_At( "[", cLinha, nPosIni ) 
               LOOP
            ENDIF
         ENDIF
      ENDIF
      nPosIni := hb_At( "[", cLinha, nPosIni + 1 )
   ENDDO

RETURN cLinha


// ============================================================================
// FUNÇÕES SUPORTE (FREADLINE, FDELIM, SplitCommaAspas)
// ============================================================================

STATIC FUNCTION FREADLINE( handle, line_len, lremchrexp, cDELI )

   LOCAL buffer, line_end, num_bytes, cRETU

   IF ValType( line_len ) <> 'N'
      line_len := 1024
   ENDIF
   IF ValType( lremchrexp ) <> "L"
      lREMCHREXP := .T.
   ENDIF
   IF ValType( cDELI ) <> "C"
      cDELI := Chr( 13 ) + Chr( 10 )
   ENDIF
   cRETU := ""
   buffer := Space( line_len )
   num_bytes := FRead( handle, @buffer, line_len )
   line_end := At( cDELI, buffer )
   
   IF line_end = 0
      FSeek( handle, 0 )
      RETURN ( '__FINAL__' )
   ELSE
      IF cDELI = Chr( 10 )
         FSeek( handle, ( num_bytes * -1 ) + line_end, 1 )  
      ELSE
         FSeek( handle, ( num_bytes * -1 ) + line_end + 1, 1 )  
      ENDIF
      
      IF lREMCHREXP
         cRETU := SubStr( buffer, 1, line_end - 1 )
         cRETU := RANGEREPL( Chr( 0 ), Chr( 9 ), cRETU, " " )   
         cRETU := RANGEREPL( Chr( 11 ), Chr( 12 ), cRETU, " " )   
         cRETU := RANGEREPL( Chr( 14 ), Chr( 31 ), cRETU, " " )   
         cRETU := RANGEREPL( Chr( 127 ), Chr( 255 ), cRETU, " " )
         RETURN cRETU
      ELSE
         RETURN ( SubStr( buffer, 1, line_end - 1 ) )
      ENDIF
   ENDIF
RETURN cRETU

STATIC FUNCTION FDELIM( cARQ, line_len, cPADRAO )

   LOCAL buffer, line_end, num_bytes, nhandle, cRETU

   IF ValType( line_len ) <> 'N'
      line_len := 1024
   ENDIF
   cRETU := ""
   buffer := Space( line_len )
   nHANDLE := FOpen( cARQ )
   num_bytes := FRead( nhandle, @buffer, line_len )
   IF Empty( AllTrim( BUFFER ) )
      buffer := FReadStr( nhandle, line_len )
   ENDIF
   FClose( NHANDLE )

   line_end := At( Chr( 13 ) + Chr( 10 ), buffer )  
   IF line_end > 0
      cRETU := Chr( 13 ) + Chr( 10 )
      RETURN cRETU
   ENDIF

   line_end := At( Chr( 10 ), buffer )  
   IF line_end > 0
      cRETU := Chr( 10 )
      RETURN cRETU
   ENDIF

   line_end := At( Chr( 13 ), buffer )  
   IF line_end > 0
      cRETU := Chr( 13 )
      RETURN cRETU
   ENDIF

   line_end := At( Chr( 255 ) + Chr( 254 ), buffer )
   IF line_end > 0
      cRETU := Chr( 255 ) + Chr( 254 )
      RETURN cRETU
   ENDIF

   line_end := At( Chr( 239 ) + Chr( 187 ) + Chr( 191 ), buffer )
   IF line_end > 0
      cRETU := Chr( 239 ) + Chr( 187 ) + Chr( 191 )
      RETURN cRETU
   ENDIF

   IF Empty( cRETU ) .AND. ValType( cPADRAO ) = "C"
      cRETU := cPADRAO
   ENDIF

   RETURN cRETU

