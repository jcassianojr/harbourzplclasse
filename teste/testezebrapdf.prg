PROCEDURE TesteZebra()
   LOCAL oZPL

   // Inicia uma etiqueta padrão 4x6 polegadas (100x150mm) a 203dpi
   oZPL := ZPLDocument():New( 100, 150, 8 )

   oZPL:AddRaw( "^FX Top section with logo, name and address." )
   oZPL:AddBox( 50, 50, 100, 100, 100 )
   oZPL:AddRaw( "^FO75,75^FR^GB100,100,100^FS" ) // ^FR (Inversao) injetado via Raw
   oZPL:AddBox( 93, 93, 40, 40, 40 )
   
   oZPL:AddText( 220, 50, "Intershipping, Inc.", 60, "0" )
   oZPL:AddText( 220, 115, "1000 Shipping Lane", 30, "0" )
   oZPL:AddText( 220, 155, "Shelbyville TN 38102", 30, "0" )
   oZPL:AddText( 220, 195, "United States (USA)", 30, "0" )
   oZPL:AddLine( 50, 250, 700, 3, 3 )

   oZPL:AddRaw( "^FX Second section with recipient address and permit information." )
   oZPL:AddText( 50, 300, "John Doe", 30, "A" )
   oZPL:AddText( 50, 340, "100 Main Street", 30, "A" )
   oZPL:AddText( 50, 380, "Springfield TN 39021", 30, "A" )
   oZPL:AddText( 50, 420, "United States (USA)", 30, "A" )
   
   oZPL:AddBox( 600, 300, 150, 150, 3 )
   oZPL:AddText( 638, 340, "Permit", 15, "A" )
   oZPL:AddText( 638, 390, "123456", 15, "A" )
   oZPL:AddLine( 50, 500, 700, 3, 3 )

   oZPL:AddRaw( "^FX Third section with bar code." )
   // Usando AddRaw para forçar a largura 5 do seu BY customizado, 
   // mas a classe padrão faria: oZPL:AddBarcode128( 100, 550, "12345678", 270 )
   oZPL:AddRaw( "^BY5,2,270^FO100,550^BC^FD12345678^FS" )

   oZPL:AddRaw( "^FX Fourth section (the two boxes on the bottom)." )
   oZPL:AddBox( 50, 900, 700, 250, 3 )
   oZPL:AddLine( 400, 900, 3, 250, 3 )
   
   oZPL:AddText( 100, 960, "Ctr. X34B-1", 40, "0" )
   oZPL:AddText( 100, 1010, "REF1 F00B47", 40, "0" )
   oZPL:AddText( 100, 1060, "REF2 BL4H8", 40, "0" )
   oZPL:AddText( 470, 955, "CA", 190, "0" )

   // Agora você pode gerar o PDF para a tela ou mandar pra porta RAW!
   oZPL:SaveToPDF( "etiqueta_sedex.pdf" )

RETURN