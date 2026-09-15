#include "hbclass.ch"
#include "hbzebra.ch"
#include "harupdf.ch"

// ============================================================================
// CONSTANTES DE CONVERSÃO MATEMÁTICA (Inspirado no ApplicationConstants.cs)
// ============================================================================
#define ZPL_POINTS_TO_MM_FACTOR 25.4
#define ZPL_DEFAULT_DPI         203
#define ZPL_DEFAULT_WIDTH_DOTS  812  // Aprox 4 polegadas (100mm)
#define ZPL_DEFAULT_HEIGHT_DOTS 1218 // Aprox 6 polegadas (150mm)

// ============================================================================
// CLASSE COMPLETA: TZebraToPdf (Arquitetura Otimizada)
// ============================================================================
CLASS TZebraToPdf
   DATA hPdf
   DATA hPage
   DATA nHeight
   DATA nX INIT 0
   DATA nY INIT 0
   DATA nBarWidth INIT 2
   DATA nBarHeight INIT 100
   DATA hFont // <- ADICIONE ESTA LINHA AQUI
   
   DATA nDpi INIT ZPL_DEFAULT_DPI
   DATA nScale 
   
   DATA cBarcodeType INIT ""
   DATA nFontSize INIT 15
   DATA lReverse INIT .F.
   DATA cOrientation INIT "N" 
   DATA cHexPrefix INIT "" 
   DATA lPrintBarcodeText INIT .T.
   DATA hExtReverse INIT Nil
   DATA hExtNormal INIT Nil
   
   DATA hFontStates INIT {=>} 
   DATA cCurrentFont INIT "A"
   DATA nFontHeight INIT 15
   DATA nFontWidth INIT 15
   
   DATA lHexDecodeNextField INIT .F. // Controle para o comando ^FH
   
   
   DATA nLHx INIT 0       // Label Home X
   DATA nLHy INIT 0       // Label Home Y
   DATA aFieldBlock       // Configurações temporárias do ^FB (Field Block)

   METHOD New( nDpi ) CONSTRUCTOR
   METHOD Generate( cZplTextOrFile, cPdfFile, aCAMVALOR ) 
   
   // Novos Métodos de Pré-Processamento e Extração
   METHOD PreProcessZPL( cZPL )
   METHOD SplitLabels( cZPL )
   METHOD ExtractDimensions( cLabel, @nWidth, @nHeight )
   METHOD DecodeFH( cText )
   
   // Métodos de Renderização
   METHOD ParseCommand( cCmd )
   METHOD DrawTextZPL( cText, aFieldBlock )
   METHOD DrawBoxZPL( nW, nH, nThickness )
   METHOD DrawBarcodeZPL( cData, cType )
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

// ============================================================================
// NOVO FLUXO PRINCIPAL DE GERAÇÃO
// ============================================================================
METHOD Generate( cZplTextOrFile, cPdfFile, aCAMVALOR ) CLASS TZebraToPdf
   Local cZplText := ""
   Local aLabels, cLabel, aCmds, cItem
   Local i, j, nPageWidth, nPageHeight
   Local aItemData, cKey, uVal, cValStr

   // 1. LER ARQUIVO OU STRING PARA A MEMÓRIA
   If Hb_FileExists( cZplTextOrFile )
      cZplText := MemoRead( cZplTextOrFile )
   Else
      cZplText := cZplTextOrFile
   Endif

   // 2. SUBSTITUIR VARIÁVEIS
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

   // 3. PRÉ-PROCESSAMENTO (Limpa lixo e resolve ^FN)
   cZplText := ::PreProcessZPL( cZplText )

   // 4. SEPARA MÚLTIPLAS ETIQUETAS (^XA ... ^XZ)
   aLabels := ::SplitLabels( cZplText )

   ::hPdf := HPDF_New()
   If Empty(::hPdf)
      Return .F.
   Endif

   HPDF_SetCompressionMode( ::hPdf, 15 )
   HPDF_SetCurrentEncoder( ::hPdf, "WinAnsiEncoding" )
   
   // -> ADICIONE ESTA LINHA: Carrega a fonte no documento
   ::hFont := HPDF_GetFont( ::hPdf, "Helvetica", "WinAnsiEncoding" )

   // 5. RENDERIZA CADA ETIQUETA EM UMA NOVA PÁGINA PDF
   For i := 1 To Len( aLabels )
      cLabel := aLabels[ i ]
      
      // Extrai dimensões ANTES de criar a página
      ::ExtractDimensions( cLabel, @nPageWidth, @nPageHeight )
      
      ::hPage := HPDF_AddPage( ::hPdf )
      HPDF_Page_SetWidth( ::hPage, nPageWidth * ::nScale ) 
      HPDF_Page_SetHeight( ::hPage, nPageHeight * ::nScale ) 
      ::nHeight := HPDF_Page_GetHeight( ::hPage )
      
      // Fundo Branco
      HPDF_Page_SetRGBFill( ::hPage, 1, 1, 1 )
      HPDF_Page_Rectangle( ::hPage, 0, 0, HPDF_Page_GetWidth( ::hPage ), ::nHeight )
      HPDF_Page_Fill( ::hPage )
      HPDF_Page_SetRGBFill( ::hPage, 0, 0, 0 ) 

      // Reinicia estados para a nova página
      ::lReverse := .F.
      ::lHexDecodeNextField := .F.
      ::cCurrentFont := "A"

      // Parseia os comandos da etiqueta
      aCmds := hb_ATokens( cLabel, "^" )
      For j := 1 To Len(aCmds)
         cItem := AllTrim(aCmds[j])
         If !Empty(cItem)
            // Ignora os inicializadores pois a página já foi criada
            If Left(cItem, 2) != "XA" .AND. Left(cItem, 2) != "XZ"
               ::ParseCommand( cItem )
            Endif
         Endif
      Next j
   Next i

   HPDF_SaveToFile( ::hPdf, cPdfFile )
   HPDF_Free( ::hPdf )
Return Hb_FileExists(cPdfFile)

// ============================================================================
// NOVOS MÉTODOS DE ARQUITETURA
// ============================================================================
METHOD PreProcessZPL( cZPL ) CLASS TZebraToPdf
   Local nPosFN, nPosEnd
   
   cZPL := StrTran( cZPL, "~", "^" )
   cZPL := StrTran( cZPL, "^B0", "^BO" ) // Workaround comum para erro de digitação
   cZPL := StrTran( cZPL, Chr(13), "" )
   cZPL := StrTran( cZPL, Chr(10), "" )

   // Remove a tag ^FN (Templates) para evitar que sejam impressos como texto puro
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

   //hb_At( <cSearch>, <cString>, [<nStart>], [<nEnd>] ) --> nPos
   While ( nStart := hb_At( "^XA", cZPL, nStart ) ) > 0
      nEnd := hb_At( "^XZ", cZPL, nStart )
      If nEnd > 0
         cLabel := SubStr( cZPL, nStart, nEnd - nStart + 3 )
         AAdd( aLabels, cLabel )
         nStart := nEnd + 3
      Else
         // Se não fechar, pega até o final do arquivo
         cLabel := SubStr( cZPL, nStart )
         AAdd( aLabels, cLabel )
         EXIT
      Endif
   End
   
   // Fallback se o ZPL for mal formatado e não tiver ^XA
   If Len(aLabels) == 0
      AAdd( aLabels, cZPL )
   Endif
Return aLabels

METHOD ExtractDimensions( cLabel, nWidth, nHeight ) CLASS TZebraToPdf
   Local nPosPW, nPosLL, cTemp, i

   // Valores Padrão fallback
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

   // Substitui sequências Hexadecimais ZPL (ex: _C3_A3 -> ã)
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

METHOD ParseCommand( cCmd ) CLASS TZebraToPdf
   Local cParams, aParams, cRest, k, cOpcode
   Local cFontID, cOrient

   cCmd := AllTrim(cCmd)
   If Empty(cCmd)
      Return Nil
   Endif

   // ---------------------------------------------------------
   // ^CF (Define a fonte padrão global)
   // ---------------------------------------------------------
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
         ::hFontStates[ cFontID ] := { 15, 15 } 
      Endif
      
      If Len(aParams) >= 1 .AND. !Empty(aParams[1]) .AND. Val(aParams[1]) > 0
         ::hFontStates[ cFontID ][1] := Val(aParams[1])
         
         If Len(aParams) < 2 .OR. Empty(aParams[2]) .OR. Val(aParams[2]) <= 0
            IF cFontID == "0"
               ::hFontStates[ cFontID ][2] := Val(aParams[1]) 
            ELSE
               ::hFontStates[ cFontID ][2] := Val(aParams[1]) * 0.6 
            ENDIF
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

   // ---------------------------------------------------------
   // ^A@ (Usa o nome da fonte para chamar a fonte)
   // ---------------------------------------------------------
   If Upper(Left(cCmd, 2)) == "A@"
      // O parser completo aqui exigiria mapear fontes do sistema
      // Mas definimos a orientação e tamanho básicos para fallback[cite: 39]
      cRest := SubStr(cCmd, 3)
      aParams := hb_ATokens( AllTrim(cRest), "," )
      If Len(aParams) >= 1
         ::cOrientation := Left(aParams[1], 1)
      Endif
      If Len(aParams) >= 2 .AND. Val(aParams[2]) > 0
         ::nFontHeight := Val(aParams[2])
         ::nFontSize := ::nFontHeight
      Endif
      Return Nil
   Endif

   // ---------------------------------------------------------
   // ^A (Define fonte temporária do campo)
   // ---------------------------------------------------------
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
      
      ::nFontHeight := ::hFontStates[ cFontID ][1]
      ::nFontWidth  := ::hFontStates[ cFontID ][2]
      
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
      CASE "FX" // Comentários
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
         
      CASE "LH" // Label Home (Altera a origem global)
         If Len(aParams) >= 2
            ::nLHx := Val(aParams[1])
            ::nLHy := Val(aParams[2])
         Endif
         EXIT

      CASE "FW" // Field Orientation global[cite: 38]
         If Len(aParams) >= 1
            ::cOrientation := aParams[1]
         Endif
         EXIT

      CASE "FB" // Field Block (Bloco de texto com quebra)[cite: 38]
         If Len(aParams) >= 2
            ::aFieldBlock := { Val(aParams[1]), Val(aParams[2]), If(Len(aParams)>=3, Val(aParams[3]), 0), If(Len(aParams)>=4, aParams[4], "L") }
         Endif
         EXIT
         
      CASE "FR"
         ::lReverse := .T.
         EXIT

      CASE "FH"
         ::lHexDecodeNextField := .T.
         EXIT
         
      CASE "FO"
      CASE "FT" 
         ::cOrientation := "N" 
         If Len(aParams) >= 2
            // Aplica o offset do Label Home (^LH)[cite: 38]
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
            ::cBarcodeType := ""
         Else
            // Passar o aFieldBlock caso ^FB tenha sido declarado antes do ^FD[cite: 38]
            ::DrawTextZPL( cParams, ::aFieldBlock )
         Endif
         ::lReverse := .F. 
         ::aFieldBlock := Nil // Limpa o estado do bloco após o uso
         EXIT    
         
      CASE "GB" // Graphic Box[cite: 38]
         If Len(aParams) >= 3
            ::DrawBoxZPL( Val(aParams[1]), Val(aParams[2]), Val(aParams[3]) )
         ElseIf Len(aParams) == 2
            ::DrawBoxZPL( Val(aParams[1]), Val(aParams[2]), 1 )
         Endif
         ::lReverse := .F. 
         EXIT

      CASE "GC" // Graphic Circle[cite: 38]
         If Len(aParams) >= 2
             ::DrawCircleZPL( Val(aParams[1]), Val(aParams[2]) )
         Endif
         EXIT

      CASE "GE" // Graphic Ellipse[cite: 38]
         If Len(aParams) >= 3
            ::DrawEllipseZPL( Val(aParams[1]), Val(aParams[2]), Val(aParams[3]) )
         Endif
         EXIT
         
      CASE "BY" // Configurações de Códigos de Barras[cite: 38]
         If Len(aParams) >= 1
            ::nBarWidth := Val(aParams[1])
         Endif
         If Len(aParams) >= 3
            ::nBarHeight := Val(aParams[3])
         Endif
         EXIT
         
      // --- MAPEAMENTO DE CÓDIGOS DE BARRAS (1D e 2D)[cite: 38, 39] ---
      CASE "B1"; ::cBarcodeType := "B1"; EXIT // Code 11[cite: 38]
      CASE "B2"; ::cBarcodeType := "B2"; EXIT // Interleaved 2 of 5[cite: 38]
      CASE "B3"; ::cBarcodeType := "B3"; EXIT // Code 39[cite: 38]
      CASE "B4"; ::cBarcodeType := "B4"; EXIT // Code 49[cite: 38]
      CASE "B8"; ::cBarcodeType := "B8"; EXIT // EAN-8[cite: 38]
      CASE "B9"; ::cBarcodeType := "B9"; EXIT // UPC-E[cite: 38]
      CASE "BA"; ::cBarcodeType := "BA"; EXIT // Code 93[cite: 38]
      CASE "BC"; ::cBarcodeType := "BC"; EXIT // Code 128[cite: 38]
      CASE "BE"; ::cBarcodeType := "BE"; EXIT // EAN-13[cite: 38]
      CASE "BU"; ::cBarcodeType := "BU"; EXIT // UPC-A[cite: 38]
      
      // 2D Barcodes
      CASE "B7"; ::cBarcodeType := "B7"; EXIT // PDF417[cite: 38]
      CASE "B0"
      CASE "BO"; ::cBarcodeType := "BO"; EXIT // Aztec[cite: 38]
      CASE "BP"; ::cBarcodeType := "BP"; EXIT // Plessey[cite: 38]
      CASE "BQ"; ::cBarcodeType := "BQ"; EXIT // QR Code[cite: 38]
      CASE "BX"; ::cBarcodeType := "BX"; EXIT // Data Matrix[cite: 38]
         
   ENDSWITCH
Return Nil


METHOD DrawTextZPL( cText, aFieldBlock ) CLASS TZebraToPdf
   Local nWidth, nMaxLines, nLineSpacing, cAlignment
   Local cLine, aLines, i, nYOffset
   Local cWord, cDrawLine, nLineWidth, nDrawX
   Local nPdfX, nPdfY, nPdfFontSize

   // 1. Calcula o tamanho real da fonte em escala PDF
   nPdfFontSize := Max( ::nFontSize * ::nScale, 1 )
   
   // 2. OBRIGATÓRIO: Aplica a fonte na página ANTES de medir ou desenhar
   HPDF_Page_SetFontAndSize( ::hPage, ::hFont, nPdfFontSize )

   // ---------------------------------------------------------
   // TEXTO SIMPLES (Sem Bloco)
   // ---------------------------------------------------------
   If Empty( aFieldBlock )
      nPdfX := ::MM_X( ::nX )
      // O PDF desenha a partir da base da letra (bottom-left), então subtraímos o tamanho da fonte
      nPdfY := ::MM_Y( ::nY ) - nPdfFontSize 

      HPDF_Page_BeginText( ::hPage )
      HPDF_Page_TextOut( ::hPage, nPdfX, nPdfY, cText )
      HPDF_Page_EndText( ::hPage )
      Return Nil
   Endif

   // ---------------------------------------------------------
   // TEXTO EM BLOCO (^FB)
   // ---------------------------------------------------------
   // Converte as dimensões do bloco ZPL para a escala PDF
   nWidth       := aFieldBlock[1] * ::nScale
   nMaxLines    := aFieldBlock[2]
   nLineSpacing := aFieldBlock[3] * ::nScale
   cAlignment   := aFieldBlock[4] // L = Left, C = Center, R = Right, J = Justified

   // Lógica simples de Word Wrap
   aLines := {}
   cLine := ""
   For i := 1 To NumToken( cText, " " )
      cWord := Token( cText, " ", i )
      
      If HPDF_Page_TextWidth( ::hPage, cLine + cWord ) > nWidth
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

   // Base Y convertida para PDF
   nYOffset := ::MM_Y( ::nY ) - nPdfFontSize
   HPDF_Page_BeginText( ::hPage )
   
   For i := 1 To Len( aLines )
      cDrawLine := AllTrim(aLines[i])
      nLineWidth := HPDF_Page_TextWidth( ::hPage, cDrawLine )
      nPdfX := ::MM_X( ::nX ) 
      
      SWITCH Upper(cAlignment)
         CASE "C"
            nPdfX := nPdfX + (nWidth - nLineWidth) / 2
            EXIT
         CASE "R"
            nPdfX := nPdfX + (nWidth - nLineWidth)
            EXIT
      ENDSWITCH

      HPDF_Page_TextOut( ::hPage, nPdfX, nYOffset, cDrawLine )
      nYOffset -= (nPdfFontSize + nLineSpacing)
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


METHOD DrawBarcodeZPL( cData, cType ) CLASS TZebraToPdf
   Local hZebra
   Local nFlags := 0 // Flags de configuração do hbzebra (ex: exibir texto, checksum)
   Local bDrawBlock

   // Se o usuário solicitou texto abaixo do código (geralmente controlado por outros comandos)
   // nFlags := HB_ZEBRA_FLAG_PRINT // Exemplo

   SWITCH cType
      // Códigos 1D
      CASE "B3" // Code 39
         hZebra := hb_zebra_create_code39( cData, nFlags )
         EXIT
      CASE "BC" // Code 128
         hZebra := hb_zebra_create_code128( cData, nFlags )
         EXIT
      CASE "BE" // EAN-13
         hZebra := hb_zebra_create_ean13( cData, nFlags )
         EXIT
      CASE "B8" // EAN-8
         hZebra := hb_zebra_create_ean8( cData, nFlags )
         EXIT
      CASE "BU" // UPC-A
         hZebra := hb_zebra_create_upca( cData, nFlags )
         EXIT
      CASE "B9" // UPC-E
         hZebra := hb_zebra_create_upce( cData, nFlags )
         EXIT
         
      // Códigos 2D
      CASE "BQ" // QR Code
         // O ZPL envia o QR code geralmente com prefixos de qualidade, ex: "QA,texto"
         // Será necessário limpar cData se ele contiver "QA," ou "M2," etc.
         If Substr(cData, 2, 1) == ","
            cData := SubStr(cData, 3)
         Endif
         hZebra := hb_zebra_create_qrcode( cData, nFlags )
         EXIT
      CASE "B7" // PDF417
         hZebra := hb_zebra_create_pdf417( cData, nFlags )
         EXIT
      CASE "BX" // Data Matrix
         hZebra := hb_zebra_create_datamatrix( cData, nFlags )
         EXIT
      OTHERWISE
         // Fallback padrão se não reconhecer
         hZebra := hb_zebra_create_code128( cData, nFlags )
   ENDSWITCH

   If hZebra != Nil
      
      // Garante que o preenchimento será preto para o código de barras
      HPDF_Page_SetRGBFill( ::hPage, 0, 0, 0 )

      // Cria a "ponte": O hbzebra envia (x, y, w, h) para cada barra, 
      // e nós traduzimos isso para retângulos no HaruPDF considerando a escala.
      bDrawBlock := {| x, y, w, h | ;
         HPDF_Page_Rectangle( ::hPage, ;
                              ::MM_X( ::nX + x ), ;
                              ::MM_Y( ::nY + y ) - (h * ::nScale), ;
                              w * ::nScale, ;
                              h * ::nScale ), ;
         HPDF_Page_Fill( ::hPage ), ;
         Nil ;
      }

      // Chama a função genérica de desenho do hbzebra passando o bloco, 
      // começando em offset 0,0 (pois o bloco já soma ::nX e ::nY)
      hb_zebra_draw( hZebra, bDrawBlock, 0, 0, ::nBarWidth, ::nBarHeight )
      
      hb_zebra_destroy( hZebra )
   Endif
   
Return Nil

METHOD MM_X( nDotX ) CLASS TZebraToPdf
Return (nDotX * ::nScale)

METHOD MM_Y( nDotY ) CLASS TZebraToPdf
Return ::nHeight - (nDotY * ::nScale)

// Legacy Custom Hex
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

METHOD DrawCircleZPL( nDiameter, nThickness ) CLASS TZebraToPdf
   Local nRadius, x, y

   If Empty( nDiameter )
      Return Nil
   Endif
   
   nThickness := If( Empty(nThickness), 1, nThickness )
   
   // Aplica a escala para as dimensões
   nRadius := (nDiameter / 2) * ::nScale
   nThickness := nThickness * ::nScale
   
   // Converte as coordenadas
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
   
   // Aplica a escala
   nRadiusX := (nWidth / 2) * ::nScale
   nRadiusY := (nHeight / 2) * ::nScale
   nThickness := nThickness * ::nScale
   
   // Converte as coordenadas
   x := ::MM_X( ::nX )
   y := ::MM_Y( ::nY )
   
   HPDF_Page_SetLineWidth( ::hPage, Max(nThickness, 0.5) )
   HPDF_Page_Ellipse( ::hPage, x + nRadiusX, y - nRadiusY, nRadiusX, nRadiusY )
   HPDF_Page_Stroke( ::hPage )
Return Nil