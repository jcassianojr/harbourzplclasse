#include "hbclass.ch"
#include "hbzebra.ch"
#include "harupdf.ch"

// ============================================================================
// CONSTANTES DE CONVERSÃO MATEMÁTICA E SISTEMA DE UNIDADES
// ============================================================================
#define ZPL_POINTS_TO_MM_FACTOR 25.4
#define ZPL_DEFAULT_DPI         203
#define ZPL_DEFAULT_WIDTH_DOTS  812  
#define ZPL_DEFAULT_HEIGHT_DOTS 1218 

// ============================================================================
// CLASSE COMPLETA: TZebraToPdf (Arquitetura Unificada Definitiva)
// ============================================================================
CLASS TZebraToPdf
   DATA hPdf
   DATA hPage
   DATA hFont
   DATA nHeight
   
   // --- ESTADO GLOBAL DA ETIQUETA ---
   DATA nX INIT 0
   DATA nY INIT 0
   DATA nLHx INIT 0       
   DATA nLHy INIT 0       
   DATA nBarWidth INIT 2
   DATA nBarHeight INIT 100
   DATA cGlobalOrient INIT "N"
   DATA cCurrentFont INIT "A"
   DATA nFontHeight INIT 9 // Metrica padrão Zebra Fonte A
   DATA nFontWidth INIT 5  // Metrica padrão Zebra Fonte A
   DATA nFontSize INIT 9
   
   // --- ESTADO ESPECÍFICO DO CAMPO ---
   DATA cOrientation INIT "N" 
   DATA cFieldOrient INIT ""
   DATA nFieldHeight INIT 0
   DATA lFieldPrintText INIT .T.
   DATA cBarcodeType INIT ""
   DATA lReverse INIT .F.
   DATA lHexDecodeNextField INIT .F. 
   DATA aFieldBlock       
   DATA cHexPrefix INIT "" 
   
   // --- CONFIGURAÇÕES DO CONVERSOR E FONTES ---
   DATA nDpi INIT ZPL_DEFAULT_DPI
   DATA nScale 
   DATA lPrintBarcodeText INIT .T.
   DATA hExtReverse INIT Nil
   DATA hExtNormal INIT Nil
   DATA hFontStates INIT {=>} 
   DATA hFontMap INIT {=>} 

   METHOD New( nDpi ) CONSTRUCTOR
   METHOD Generate( cZplTextOrFile, cPdfFile, aCAMVALOR ) 
   
   // Métodos de Gerenciamento de Estado e Unidades
   METHOD ResetLabelState()
   METHOD ClearFieldState()
   METHOD GetDefaultFontMetrics( cFont, @nH, @nW )
   
   METHOD PreProcessZPL( cZPL )
   METHOD SplitLabels( cZPL )
   METHOD ExtractDimensions( cLabel, @nWidth, @nHeight )
   METHOD DecodeFH( cText )
   
   METHOD ParseCommand( cCmd )
   METHOD ParseBarcodeParams( aParams, nPosO, nPosH, nPosT )
   METHOD DrawTextZPL( cText, aFieldBlock )
   METHOD DrawBoxZPL( nW, nH, nThickness )
   METHOD DrawBarcodeZPL( cData, cType )
   METHOD DrawGraphicZPL( cData, nBytesPerRow ) 
   METHOD DecompressZPLGraphic( cData, nBytesPerRow )
   METHOD HexToBinStr( cHex )
   METHOD MM_X( nDotX )
   METHOD MM_Y( nDotY )
   METHOD DecodeZPLHex( cText )
   METHOD ConvertCP850ToWinAnsi( cHex )
   METHOD ApplyReverseState()
   METHOD DrawCircleZPL( nDiameter, nThickness )
   METHOD DrawEllipseZPL( nWidth, nHeight, nThickness )
ENDCLASS

METHOD New( nDpi ) CLASS TZebraToPdf
   If nDpi != Nil
      ::nDpi := nDpi
   Endif
   ::nScale := 72 / ::nDpi 
   
   ::hFontMap := {=>}
   ::hFontMap["0"] := "Helvetica-Bold"
   ::hFontMap["A"] := "Helvetica"
   ::hFontMap["B"] := "Helvetica"
Return Self

METHOD GetDefaultFontMetrics( cFont, nH, nW ) CLASS TZebraToPdf
   // Tabela Oficial de Matriz de Pontos ZPL II (Base 203 DPI)
   SWITCH Upper( cFont )
      CASE "A"; nH := 9;  nW := 5;  EXIT
      CASE "B"; nH := 11; nW := 7;  EXIT
      CASE "C"; nH := 18; nW := 10; EXIT
      CASE "D"; nH := 18; nW := 10; EXIT
      CASE "E"; nH := 28; nW := 15; EXIT
      CASE "F"; nH := 26; nW := 13; EXIT
      CASE "G"; nH := 60; nW := 40; EXIT
      CASE "H"; nH := 21; nW := 13; EXIT
      CASE "0"; nH := 15; nW := 15; EXIT
      OTHERWISE; nH := 15; nW := 15
   ENDSWITCH
Return Nil

METHOD ResetLabelState() CLASS TZebraToPdf
   ::nX := 0
   ::nY := 0
   ::nLHx := 0
   ::nLHy := 0
   ::nBarWidth := 2
   ::nBarHeight := 100
   ::cGlobalOrient := "N"
   
   // Padrão de Inicialização de Etiqueta (Fonte A)
   ::cCurrentFont := "A"
   ::nFontHeight := 9
   ::nFontWidth := 5
   ::nFontSize := 9
   
   ::ClearFieldState()
Return Nil

METHOD ClearFieldState() CLASS TZebraToPdf
   ::cOrientation := ::cGlobalOrient
   ::cFieldOrient := ""
   ::nFieldHeight := 0
   ::lFieldPrintText := ::lPrintBarcodeText
   ::cBarcodeType := ""
   ::lReverse := .F.
   ::lHexDecodeNextField := .F.
   ::aFieldBlock := Nil
   ::cHexPrefix := ""
Return Nil

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
   Local cZplText := ""
   Local aLabels, cLabel, cCmdStr, cOpcode
   Local i, nPos, nNextPos, nPageWidth, nPageHeight
   Local aItemData, cKey, uVal, cValStr

   If Hb_FileExists( cZplTextOrFile )
      cZplText := MemoRead( cZplTextOrFile )
   Else
      cZplText := cZplTextOrFile
   Endif

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
               cZplText := StrTran( cZplText, cKey, cValStr )
               cZplText := StrTran( cZplText, Upper( cKey ), cValStr )
            Endif
         Endif
      Next i
   Endif

   cZplText := ::PreProcessZPL( cZplText )
   aLabels := ::SplitLabels( cZplText )

   ::hPdf := HPDF_New()
   If Empty(::hPdf)
      Return .F.
   Endif

   HPDF_SetCompressionMode( ::hPdf, 15 )
   HPDF_SetCurrentEncoder( ::hPdf, "WinAnsiEncoding" )
   ::hFont := HPDF_GetFont( ::hPdf, "Helvetica", "WinAnsiEncoding" )

   For i := 1 To Len( aLabels )
      cLabel := aLabels[ i ]
      ::ExtractDimensions( cLabel, @nPageWidth, @nPageHeight )
      
      ::hPage := HPDF_AddPage( ::hPdf )
      HPDF_Page_SetWidth( ::hPage, nPageWidth * ::nScale ) 
      HPDF_Page_SetHeight( ::hPage, nPageHeight * ::nScale ) 
      ::nHeight := HPDF_Page_GetHeight( ::hPage )
      
      HPDF_Page_SetRGBFill( ::hPage, 1, 1, 1 )
      HPDF_Page_Rectangle( ::hPage, 0, 0, HPDF_Page_GetWidth( ::hPage ), ::nHeight )
      HPDF_Page_Fill( ::hPage )
      HPDF_Page_SetRGBFill( ::hPage, 0, 0, 0 ) 

      ::ResetLabelState()

      nPos := 1
      While ( nPos := hb_At( "^", cLabel, nPos ) ) > 0
         
         cOpcode := Upper( SubStr( cLabel, nPos + 1, 2 ) )
         
         If cOpcode == "FD"
            nNextPos := hb_At( "^FS", Upper(cLabel), nPos + 1 )
            If nNextPos > 0
               cCmdStr := SubStr( cLabel, nPos + 1, nNextPos - nPos - 1 )
               
               cCmdStr := AllTrim( cCmdStr )
               If !Empty( cCmdStr )
                  ::ParseCommand( cCmdStr )
               Endif
               
               nPos := nNextPos + 3 
               LOOP
            Endif
         Endif
         
         nNextPos := hb_At( "^", cLabel, nPos + 1 )
         
         If nNextPos == 0
            cCmdStr := SubStr( cLabel, nPos + 1 )
            nPos := Len( cLabel ) + 1 
         Else
            cCmdStr := SubStr( cLabel, nPos + 1, nNextPos - nPos - 1 )
            nPos := nNextPos 
         Endif
         
         cCmdStr := AllTrim( cCmdStr )
         
         If !Empty( cCmdStr ) .AND. Left(cCmdStr, 2) != "XA" .AND. Left(cCmdStr, 2) != "XZ" .AND. Left(cCmdStr, 2) != "FS"
            ::ParseCommand( cCmdStr )
         Endif
         
      End
   Next i

   HPDF_SaveToFile( ::hPdf, cPdfFile )
   HPDF_Free( ::hPdf )
Return Hb_FileExists(cPdfFile)

METHOD PreProcessZPL( cZPL ) CLASS TZebraToPdf
   Local nPosFN, nPosEnd
   
   cZPL := StrTran( cZPL, "~", "^" )
   cZPL := StrTran( cZPL, "^B0", "^BO" ) 
   cZPL := StrTran( cZPL, Chr(13), "" )
   cZPL := StrTran( cZPL, Chr(10), "" )

   nPosFN := At( "^FN", cZPL )
   While nPosFN > 0
      nPosEnd := nPosFN + 3
      While nPosEnd <= Len(cZPL) .AND. ( SubStr(cZPL, nPosEnd, 1) >= "0" .AND. SubStr(cZPL, nPosEnd, 1) <= "9" )
         nPosEnd++
      End
      cZPL := Left( cZPL, nPosFN - 1 ) + SubStr( cZPL, nPosEnd )
      nPosFN := At( "^FN", cZPL )
   End
Return cZPL

METHOD SplitLabels( cZPL ) CLASS TZebraToPdf
   Local aLabels := {}
   Local nStart := 1
   Local nEnd := 0
   Local cLabel

   While ( nStart := hb_At( "^XA", cZPL, nStart ) ) > 0
      nEnd := hb_At( "^XZ", cZPL, nStart )
      If nEnd > 0
         cLabel := SubStr( cZPL, nStart, nEnd - nStart + 3 )
         AAdd( aLabels, cLabel )
         nStart := nEnd + 3
      Else
         cLabel := SubStr( cZPL, nStart )
         AAdd( aLabels, cLabel )
         EXIT
      Endif
   End
   
   If Len(aLabels) == 0
      AAdd( aLabels, cZPL )
   Endif
Return aLabels

METHOD ExtractDimensions( cLabel, nWidth, nHeight ) CLASS TZebraToPdf
   Local nPosPW, nPosLL, cTemp

   nWidth  := ZPL_DEFAULT_WIDTH_DOTS
   nHeight := ZPL_DEFAULT_HEIGHT_DOTS

   nPosPW := At( "^PW", cLabel )
   If nPosPW > 0
      cTemp := SubStr( cLabel, nPosPW + 3 )
      nWidth := Val( cTemp )
   Endif

   nPosLL := At( "^LL", cLabel )
   If nPosLL > 0
      cTemp := SubStr( cLabel, nPosLL + 3 )
      nHeight := Val( cTemp )
   Endif
Return Nil

METHOD DecodeFH( cText ) CLASS TZebraToPdf
   Local cResult := ""
   Local i := 1
   Local cHex

   While i <= Len( cText )
      If SubStr( cText, i, 1 ) == "_" .AND. i + 2 <= Len( cText )
         cHex := SubStr( cText, i + 1, 2 )
         If IsHex( cHex )
            cResult += Chr( hb_HexToNum( cHex ) )
            i += 3
            LOOP
         Endif
      Endif
      cResult += SubStr( cText, i, 1 )
      i++
   End
Return cResult

METHOD ParseBarcodeParams( aParams, nPosO, nPosH, nPosT ) CLASS TZebraToPdf
   If nPosO > 0 .AND. Len(aParams) >= nPosO .AND. !Empty(aParams[nPosO])
      ::cFieldOrient := aParams[nPosO]
   Endif
   If nPosH > 0 .AND. Len(aParams) >= nPosH .AND. !Empty(aParams[nPosH])
      ::nFieldHeight := Val(aParams[nPosH])
   Endif
   If nPosT > 0 .AND. Len(aParams) >= nPosT .AND. !Empty(aParams[nPosT])
      ::lFieldPrintText := (Upper(aParams[nPosT]) == "Y")
   Endif
Return Nil

METHOD ParseCommand( cCmd ) CLASS TZebraToPdf
   Local cParams, aParams, cRest, cOpcode
   Local cFontID, cOrient
   Local nP1, nP2, nP3, nP4, cFmt, nRowBytes, cGData
   Local cAlias, cFontFile
   Local nDefH, nDefW

   cCmd := AllTrim(cCmd)
   If Empty(cCmd)
      Return Nil
   Endif

   // =========================================================
   // PROCESSAMENTO ESTrito DE MATRIZ DE FONTE (^CF e ^A)
   // =========================================================
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
      
      ::GetDefaultFontMetrics( cFontID, @nDefH, @nDefW )
      
      If !hb_HHasKey( ::hFontStates, cFontID )
         ::hFontStates[ cFontID ] := { nDefH, nDefW } 
      Endif
      
      If Len(aParams) >= 1 .AND. !Empty(aParams[1]) .AND. Val(aParams[1]) > 0
         ::hFontStates[ cFontID ][1] := Val(aParams[1])
         
         // Se a largura for omitida, calcula baseado na proporção REAL da fonte
         If Len(aParams) < 2 .OR. Empty(aParams[2]) .OR. Val(aParams[2]) <= 0
            ::hFontStates[ cFontID ][2] := Round( Val(aParams[1]) * (nDefW / nDefH), 0 ) 
         Endif
      Endif
      If Len(aParams) >= 2 .AND. !Empty(aParams[2]) .AND. Val(aParams[2]) > 0
         ::hFontStates[ cFontID ][2] := Val(aParams[2])
      Endif
      
      ::cCurrentFont := cFontID
      ::nFontHeight  := ::hFontStates[ cFontID ][1]
      ::nFontWidth   := ::hFontStates[ cFontID ][2]
      ::nFontSize    := ::nFontHeight 
      Return Nil
   Endif

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
      
      ::GetDefaultFontMetrics( cFontID, @nDefH, @nDefW )
      
      If !hb_HHasKey( ::hFontStates, cFontID )
         ::hFontStates[ cFontID ] := { nDefH, nDefW }
      Endif
      
      ::cCurrentFont := cFontID
      ::cOrientation := cOrient
      ::nFontHeight := ::hFontStates[ cFontID ][1]
      ::nFontWidth  := ::hFontStates[ cFontID ][2]
      
      If Len(aParams) >= 1 .AND. !Empty(aParams[1]) .AND. Val(aParams[1]) > 0
         ::nFontHeight := Val(aParams[1])
         
         // Se a largura for omitida, calcula baseado na proporção REAL da fonte
         If Len(aParams) < 2 .OR. Empty(aParams[2]) .OR. Val(aParams[2]) <= 0
            ::nFontWidth := Round( Val(aParams[1]) * (nDefW / nDefH), 0 )
         Endif
      Endif
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
      CASE "FX"; EXIT
      CASE "CW"
         If Len(aParams) >= 2 .AND. !Empty(aParams[1])
            cAlias := Upper( Left( aParams[1], 1 ) )
            cFontFile := Upper( aParams[2] )
            
            If "BOLD" $ cFontFile .OR. "B." $ cFontFile
               ::hFontMap[ cAlias ] := "Helvetica-Bold"
            ElseIf "COUR" $ cFontFile
               ::hFontMap[ cAlias ] := "Courier"
            Else
               ::hFontMap[ cAlias ] := "Helvetica"
            Endif
         Endif
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
      CASE "LH"
         If Len(aParams) >= 2
            ::nLHx := Val(aParams[1])
            ::nLHy := Val(aParams[2])
         Endif
         EXIT
      CASE "FW"
         If Len(aParams) >= 1 .AND. !Empty(aParams[1])
            ::cGlobalOrient := aParams[1]
         Endif
         EXIT
      CASE "FR"; ::lReverse := .T.; EXIT
      CASE "FH"; ::lHexDecodeNextField := .T.; EXIT
      CASE "FO"
      CASE "FT" 
         ::cOrientation := ::cGlobalOrient 
         If Len(aParams) >= 2
            ::nX := Val(aParams[1]) + ::nLHx
            ::nY := Val(aParams[2]) + ::nLHy
         Endif
         EXIT
      CASE "FD"
         If Right( cParams, 2 ) == "FS"
            cParams := Left( cParams, Len( cParams ) - 2 )
         Endif
         cParams := StripBBCode( cParams )
         If ::lHexDecodeNextField
            cParams := ::DecodeFH( cParams )
            ::lHexDecodeNextField := .F. 
         Endif
         If !Empty( ::cHexPrefix )
            cParams := ::DecodeZPLHex( cParams )
         Endif
         
         If !Empty( ::cBarcodeType )
            ::DrawBarcodeZPL( cParams, ::cBarcodeType )
         Else
            ::DrawTextZPL( cParams, ::aFieldBlock )
         Endif
         
         ::ClearFieldState()
         EXIT    
      CASE "GB"
         If Len(aParams) >= 3
            ::DrawBoxZPL( Val(aParams[1]), Val(aParams[2]), Val(aParams[3]) )
         ElseIf Len(aParams) == 2
            ::DrawBoxZPL( Val(aParams[1]), Val(aParams[2]), 1 )
         Endif
         ::ClearFieldState() 
         EXIT
      CASE "GC"
         If Len(aParams) >= 2
            ::DrawCircleZPL( Val(aParams[1]), Val(aParams[2]) )
         Endif
         ::ClearFieldState()
         EXIT
      CASE "GE"
         If Len(aParams) >= 3
            ::DrawEllipseZPL( Val(aParams[1]), Val(aParams[2]), Val(aParams[3]) )
         Endif
         ::ClearFieldState()
         EXIT
      CASE "BY"
         If Len(aParams) >= 1
            ::nBarWidth := Val(aParams[1])
         Endif
         If Len(aParams) >= 3
            ::nBarHeight := Val(aParams[3])
         Endif
         EXIT
      CASE "FB"
         If Len(aParams) >= 2
            ::aFieldBlock := { Val(aParams[1]), Val(aParams[2]), If(Len(aParams)>=3, Val(aParams[3]), 0), If(Len(aParams)>=4, aParams[4], "L") }
         Endif
         EXIT
      CASE "GF"
         nP1 := hb_At(",", cParams)
         If nP1 > 0
            nP2 := hb_At(",", cParams, nP1 + 1)
            If nP2 > 0
               nP3 := hb_At(",", cParams, nP2 + 1)
               If nP3 > 0
                  nP4 := hb_At(",", cParams, nP3 + 1)
                  If nP4 > 0
                     cFmt := Upper(Left(cParams, nP1 - 1))
                     nRowBytes := Val(SubStr(cParams, nP3 + 1, nP4 - nP3 - 1))
                     cGData := SubStr(cParams, nP4 + 1)
                     
                     If cFmt == "A" .AND. nRowBytes > 0
                        ::DrawGraphicZPL( cGData, nRowBytes )
                     Endif
                  Endif
               Endif
            Endif
         Endif
         EXIT

      CASE "B1"
      CASE "B2"
      CASE "B4"
      CASE "BO"
      CASE "BP"
         ::cBarcodeType := ""
         EXIT
      CASE "B3"
         ::cBarcodeType := "B3"; ::ParseBarcodeParams( aParams, 1, 3, 4 ); EXIT
      CASE "B8"
         ::cBarcodeType := "B8"; ::ParseBarcodeParams( aParams, 1, 2, 3 ); EXIT
      CASE "B9"
         ::cBarcodeType := "B9"; ::ParseBarcodeParams( aParams, 1, 2, 3 ); EXIT
      CASE "BA"
         ::cBarcodeType := "BA"; ::ParseBarcodeParams( aParams, 1, 2, 3 ); EXIT
      CASE "BC"
         ::cBarcodeType := "BC"; ::ParseBarcodeParams( aParams, 1, 2, 3 ); EXIT
      CASE "BE"
         ::cBarcodeType := "BE"; ::ParseBarcodeParams( aParams, 1, 2, 3 ); EXIT
      CASE "BU"
         ::cBarcodeType := "BU"; ::ParseBarcodeParams( aParams, 1, 2, 3 ); EXIT
      CASE "B7"
         ::cBarcodeType := "B7"; ::ParseBarcodeParams( aParams, 1, 2, 0 ); EXIT
      CASE "BQ"
         ::cBarcodeType := "BQ"; ::ParseBarcodeParams( aParams, 1, 0, 0 ); EXIT
      CASE "BX"
         ::cBarcodeType := "BX"; ::ParseBarcodeParams( aParams, 1, 2, 0 ); EXIT
   ENDSWITCH
Return Nil

METHOD DecompressZPLGraphic( cData, nBytesPerRow ) CLASS TZebraToPdf
   LOCAL cOut := ""
   LOCAL cPrevLine := Replicate("0", nBytesPerRow * 2)
   LOCAL cLine := ""
   LOCAL i, c
   LOCAL nRepeat := 0
   
   If nBytesPerRow <= 0
      Return ""
   Endif
   
   For i := 1 to Len(cData)
      c := SubStr(cData, i, 1)
      
      If c >= 'g' .AND. c <= 'z'
         nRepeat += (Asc(c) - Asc('g') + 1) * 20
         Loop
      Endif
      
      If c >= 'G' .AND. c <= 'Y'
         nRepeat += (Asc(c) - Asc('G') + 1)
         Loop
      Endif
      
      If nRepeat == 0
         nRepeat := 1
      Endif
      
      If c == ','
         cLine += Replicate("0", Max(0, (nBytesPerRow * 2) - Len(cLine)))
      ElseIf c == '!'
         cLine += Replicate("F", Max(0, (nBytesPerRow * 2) - Len(cLine)))
      ElseIf c == ':'
         cLine := cPrevLine
      ElseIf c $ "0123456789ABCDEFabcdef"
         cLine += Replicate(c, nRepeat)
      Endif
      
      nRepeat := 0
      
      If Len(cLine) >= nBytesPerRow * 2
         cOut += Left(cLine, nBytesPerRow * 2)
         cPrevLine := Left(cLine, nBytesPerRow * 2)
         cLine := SubStr(cLine, nBytesPerRow * 2 + 1)
      Endif
   Next
Return cOut

METHOD HexToBinStr( cHex ) CLASS TZebraToPdf
   LOCAL cBin := ""
   LOCAL i, c
   For i := 1 To Len(cHex)
      c := Upper(SubStr(cHex, i, 1))
      SWITCH c
         CASE "0"; cBin += "0000"; EXIT
         CASE "1"; cBin += "0001"; EXIT
         CASE "2"; cBin += "0010"; EXIT
         CASE "3"; cBin += "0011"; EXIT
         CASE "4"; cBin += "0100"; EXIT
         CASE "5"; cBin += "0101"; EXIT
         CASE "6"; cBin += "0110"; EXIT
         CASE "7"; cBin += "0111"; EXIT
         CASE "8"; cBin += "1000"; EXIT
         CASE "9"; cBin += "1001"; EXIT
         CASE "A"; cBin += "1010"; EXIT
         CASE "B"; cBin += "1011"; EXIT
         CASE "C"; cBin += "1100"; EXIT
         CASE "D"; cBin += "1101"; EXIT
         CASE "E"; cBin += "1110"; EXIT
         CASE "F"; cBin += "1111"; EXIT
      ENDSWITCH
   Next
Return cBin

METHOD DrawGraphicZPL( cData, nBytesPerRow ) CLASS TZebraToPdf
   LOCAL cFullHex, nTotalRows, cRowHex, cRowBin
   LOCAL nRow, nCol, nStartX, nSpan
   LOCAL x, y, h, w
   
   cFullHex := ::DecompressZPLGraphic( cData, nBytesPerRow )
   nTotalRows := Len(cFullHex) / (nBytesPerRow * 2)
   
   ::ApplyReverseState()
   HPDF_Page_SetRGBFill( ::hPage, 0, 0, 0 ) 
   
   For nRow := 1 to nTotalRows
      cRowHex := SubStr( cFullHex, ((nRow - 1) * nBytesPerRow * 2) + 1, nBytesPerRow * 2 )
      cRowBin := ::HexToBinStr( cRowHex )
      
      nStartX := -1
      nSpan := 0
      
      For nCol := 1 to Len(cRowBin)
         If SubStr(cRowBin, nCol, 1) == "1"
            If nStartX == -1
               nStartX := nCol - 1
            Endif
            nSpan++
         Else
            If nStartX != -1
               x := ::MM_X( ::nX + nStartX )
               y := ::MM_Y( ::nY + (nRow - 1) )
               w := nSpan * ::nScale
               h := 1 * ::nScale
               HPDF_Page_Rectangle( ::hPage, x, y - h, w, h )
               HPDF_Page_Fill( ::hPage )
               
               nStartX := -1
               nSpan := 0
            Endif
         Endif
      Next
      
      If nStartX != -1
         x := ::MM_X( ::nX + nStartX )
         y := ::MM_Y( ::nY + (nRow - 1) )
         w := nSpan * ::nScale
         h := 1 * ::nScale
         HPDF_Page_Rectangle( ::hPage, x, y - h, w, h )
         HPDF_Page_Fill( ::hPage )
      Endif
   Next
Return Nil

METHOD DrawTextZPL( cText, aFieldBlock ) CLASS TZebraToPdf
   Local nWidth, nMaxLines, nLineSpacing, cAlignment
   Local cLine, aLines, i, nLineShift
   Local cWord, cDrawLine, nLineWidth, nDrawX
   Local nPdfFontSize, nHScale, nBaseRatio, x, y
   Local cFontName
   Local hActiveFont

   If hb_HHasKey( ::hFontMap, ::cCurrentFont )
      cFontName := ::hFontMap[ ::cCurrentFont ]
   Else
      cFontName := If( ::cCurrentFont == "0", "Helvetica-Bold", "Helvetica" )
   Endif

   hActiveFont := HPDF_GetFont( ::hPdf, cFontName, "WinAnsiEncoding" )

   nPdfFontSize := Max( ::nFontSize * ::nScale, 1 )
   HPDF_Page_SetFontAndSize( ::hPage, hActiveFont, nPdfFontSize )

   nHScale := 1.0
   If ::nFontHeight > 0 .AND. ::nFontWidth > 0 
      nBaseRatio := If( "Bold" $ cFontName, 1.0, If( "Courier" $ cFontName, 0.60, 0.55 ) )
      nHScale := ::nFontWidth / (::nFontHeight * nBaseRatio)
      nHScale := Max(0.4, Min(nHScale, 2.5))
   Endif

   ::ApplyReverseState()

   aLines := {}
   cAlignment := "L"
   nLineSpacing := 0
   nWidth := 0

   If Empty( aFieldBlock )
      AAdd( aLines, cText )
   Else
      nWidth       := aFieldBlock[1] * ::nScale
      nMaxLines    := aFieldBlock[2]
      nLineSpacing := aFieldBlock[3] * ::nScale
      cAlignment   := aFieldBlock[4]

      cLine := ""
      For i := 1 To NumToken( cText, " " )
         cWord := Token( cText, " ", i )
         If ( HPDF_Page_TextWidth( ::hPage, cLine + cWord ) * nHScale ) > nWidth .AND. !Empty(cLine)
            AAdd( aLines, cLine )
            cLine := cWord + " "
         Else
            cLine += cWord + " "
         Endif
      Next
      If !Empty(cLine)
         AAdd( aLines, cLine )
      Endif

      If Len(aLines) > nMaxLines .AND. nMaxLines > 0
         ASize( aLines, nMaxLines )
      Endif
   Endif

   HPDF_Page_BeginText( ::hPage )
   
   x := ::MM_X( ::nX )
   y := ::MM_Y( ::nY ) - (nPdfFontSize * 0.8)
   
   For i := 1 To Len( aLines )
      cDrawLine := AllTrim(aLines[i])
      nLineWidth := HPDF_Page_TextWidth( ::hPage, cDrawLine ) * nHScale
      nDrawX := 0
      
      SWITCH Upper(cAlignment)
         CASE "C"; nDrawX := Max(0, (nWidth - nLineWidth) / 2); EXIT
         CASE "R"; nDrawX := Max(0, (nWidth - nLineWidth)); EXIT
      ENDSWITCH
      
      nLineShift := (i - 1) * (nPdfFontSize + nLineSpacing)
      
      SWITCH ::cOrientation
         CASE "R"
            HPDF_Page_SetTextMatrix( ::hPage, 0, -1, nHScale, 0, x - nLineShift, y - nDrawX ); EXIT
         CASE "I"
            HPDF_Page_SetTextMatrix( ::hPage, -nHScale, 0, 0, -1, x - nDrawX, y + nLineShift ); EXIT
         CASE "B"
            HPDF_Page_SetTextMatrix( ::hPage, 0, 1, -nHScale, 0, x + nLineShift, y + nDrawX ); EXIT
         OTHERWISE
            HPDF_Page_SetTextMatrix( ::hPage, nHScale, 0, 0, 1, x + nDrawX, y - nLineShift )
      ENDSWITCH
      
      HPDF_Page_ShowText( ::hPage, cDrawLine )
   Next
   
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

METHOD DrawBarcodeZPL( cData, cType ) CLASS TZebraToPdf
   LOCAL hZebra, nFlags := 0
   LOCAL x := ::MM_X( ::nX )
   LOCAL y := ::MM_Y( ::nY ) 
   LOCAL hFont, nPdfFontSize
   LOCAL nWidthFactor, nTextWidth, nCenterTextX
   LOCAL nHarbourModules := 0, nActualWidth
   
   LOCAL cOrient := If( !Empty(::cFieldOrient), ::cFieldOrient, ::cOrientation )
   LOCAL nRawHeight := If( ::nFieldHeight > 0, ::nFieldHeight, If( ValType(::nBarHeight) == "N" .AND. ::nBarHeight > 0, ::nBarHeight, 100 ) )
   LOCAL lShowText := ::lFieldPrintText
   LOCAL nPdfBarHeight

   nPdfBarHeight := Abs( ::MM_Y( nRawHeight ) - ::MM_Y( 0 ) )

   DO CASE
      CASE cType == "B3"; hZebra := hb_zebra_create_code39( cData, nFlags )
      CASE cType == "B8"; hZebra := hb_zebra_create_ean8( cData, nFlags )
      CASE cType == "B9"; hZebra := hb_zebra_create_upce( cData, nFlags )
      CASE cType == "BA"; hZebra := hb_zebra_create_code93( cData, nFlags )
      CASE cType == "BC"; hZebra := hb_zebra_create_code128( cData, nFlags )
      CASE cType == "BE"; hZebra := hb_zebra_create_ean13( cData, nFlags )
      CASE cType == "BU"; hZebra := hb_zebra_create_upca( cData, nFlags )
      CASE cType == "B7"; hZebra := hb_zebra_create_pdf417( cData, nFlags ); lShowText := .F.
      CASE cType == "BQ"
         If Substr(cData, 2, 1) == ","
            cData := SubStr(cData, 3)
         Endif
         hZebra := hb_zebra_create_qrcode( cData, nFlags )
         lShowText := .F.
      CASE cType == "BX"; hZebra := hb_zebra_create_datamatrix( cData, nFlags ); lShowText := .F.
      OTHERWISE; hZebra := Nil
   ENDCASE

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

      SWITCH cOrient
         CASE "R"; HPDF_Page_Concat( ::hPage, 0, -1, 1, 0, x, y ); EXIT
         CASE "I"; HPDF_Page_Concat( ::hPage, -1, 0, 0, -1, x, y ); EXIT
         CASE "B"; HPDF_Page_Concat( ::hPage, 0, 1, -1, 0, x, y ); EXIT
         OTHERWISE; HPDF_Page_Concat( ::hPage, 1, 0, 0, 1, x, y )
      ENDSWITCH

      hb_zebra_draw( hZebra, {| bx, by, bw, bh | HPDF_Page_Rectangle( ::hPage, bx, by, bw, bh ) }, 0, -nPdfBarHeight, nWidthFactor, nPdfBarHeight )
      HPDF_Page_Fill( ::hPage )

      If lShowText
         nActualWidth := nHarbourModules * nWidthFactor
         hFont := HPDF_GetFont( ::hPdf, "Helvetica-Bold", "WinAnsiEncoding" )
         
         nPdfFontSize := Max( ::nFontSize * ::nScale, 10 )
         HPDF_Page_SetFontAndSize( ::hPage, hFont, nPdfFontSize )
         
         nTextWidth := HPDF_Page_TextWidth( ::hPage, cData )
         nCenterTextX := (nActualWidth / 2) - (nTextWidth / 2)
         
         HPDF_Page_BeginText( ::hPage )
         HPDF_Page_SetTextMatrix( ::hPage, 1, 0, 0, 1, nCenterTextX, -nPdfBarHeight - (nPdfFontSize * 1.1) )
         HPDF_Page_ShowText( ::hPage, cData ) 
         HPDF_Page_EndText( ::hPage )
      Endif
      
      HPDF_Page_GRestore( ::hPage )
      hb_zebra_destroy( hZebra )
   Endif
Return Nil

METHOD ConvertCP850ToWinAnsi( cHex ) CLASS TZebraToPdf
   Local nNum := hb_HexToNum( cHex )
   Local nWinAnsi := nNum
   SWITCH nNum
      CASE 135; nWinAnsi := 231; EXIT 
      CASE 128; nWinAnsi := 199; EXIT 
      CASE 198; nWinAnsi := 227; EXIT 
      CASE 199; nWinAnsi := 195; EXIT 
      CASE 160; nWinAnsi := 225; EXIT 
      CASE 181; nWinAnsi := 193; EXIT 
      CASE 130; nWinAnsi := 233; EXIT 
      CASE 144; nWinAnsi := 201; EXIT 
      CASE 161; nWinAnsi := 237; EXIT 
      CASE 214; nWinAnsi := 205; EXIT 
      CASE 162; nWinAnsi := 243; EXIT 
      CASE 224; nWinAnsi := 211; EXIT 
      CASE 228; nWinAnsi := 245; EXIT 
      CASE 229; nWinAnsi := 213; EXIT 
      CASE 163; nWinAnsi := 250; EXIT 
      CASE 233; nWinAnsi := 218; EXIT 
      CASE 136; nWinAnsi := 234; EXIT 
      CASE 210; nWinAnsi := 202; EXIT 
      CASE 147; nWinAnsi := 244; EXIT 
      CASE 226; nWinAnsi := 212; EXIT 
      CASE 167; nWinAnsi := 186; EXIT  
      CASE 166; nWinAnsi := 170; EXIT  
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
            Endif
         Endif
      Endif
      nPosIni := hb_At( "[", cLinha, nPosIni + 1 )
   ENDDO
RETURN cLinha

METHOD DrawCircleZPL( nDiameter, nThickness ) CLASS TZebraToPdf
   Local nRadius, x, y
   If Empty( nDiameter )
      Return Nil
   Endif
   nThickness := If( Empty(nThickness), 1, nThickness )
   nRadius := (nDiameter / 2) * ::nScale
   nThickness := nThickness * ::nScale
   x := ::MM_X( ::nX )
   y := ::MM_Y( ::nY )
   HPDF_Page_SetLineWidth( ::hPage, Max(nThickness, 0.5) )
   HPDF_Page_Circle( ::hPage, x + nRadius, y - nRadius, nRadius )
   HPDF_Page_Stroke( ::hPage )
Return Nil

METHOD DrawEllipseZPL( nWidth, nHeight, nThickness ) CLASS TZebraToPdf
   Local nRadiusX, nRadiusY, x, y
   If Empty( nWidth ) .OR. Empty( nHeight )
      Return Nil
   Endif
   nThickness := If( Empty(nThickness), 1, nThickness )
   nRadiusX := (nWidth / 2) * ::nScale
   nRadiusY := (nHeight / 2) * ::nScale
   nThickness := nThickness * ::nScale
   x := ::MM_X( ::nX )
   y := ::MM_Y( ::nY )
   HPDF_Page_SetLineWidth( ::hPage, Max(nThickness, 0.5) )
   HPDF_Page_Ellipse( ::hPage, x + nRadiusX, y - nRadiusY, nRadiusX, nRadiusY )
   HPDF_Page_Stroke( ::hPage )
Return Nil