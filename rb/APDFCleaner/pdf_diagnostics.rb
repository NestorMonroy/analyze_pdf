require 'hexapdf'

module PDFDiagnostics
  def self.log_object_details(doc, object_number, logger)
    obj = doc.object(object_number)
    logger.info("Detalles del objeto #{object_number}:")
    if obj.nil?
      logger.info("  El objeto no existe")
    elsif obj.is_a?(HexaPDF::Stream)
      logger.info("  Tipo: Stream")
      logger.info("  Tamaño del stream: #{obj.stream.size} bytes")
      logger.info("  Diccionario del stream: #{obj.value.inspect}")
    elsif obj.is_a?(HexaPDF::Dictionary)
      logger.info("  Tipo: Dictionary")
      logger.info("  Contenido: #{obj.value.inspect}")
    else
      logger.info("  Tipo: #{obj.class}")
      logger.info("  Valor: #{obj.inspect}")
    end
  end

  def self.analyze_document_at_stage(stage_name, file_path, logger)
    logger.info("Analizando documento en la etapa: #{stage_name}")
    begin
      doc = HexaPDF::Document.open(file_path)
      logger.info("Número de páginas: #{doc.pages.count}")
      logger.info("Número total de objetos: #{doc.each.count}")
      
      # Analizar el objeto 4 específicamente
      log_object_details(doc, 4, logger)
      
      # Analizar el contenido de la primera página
      page = doc.pages[0]
      if page
        logger.info("Contenido de la primera página:")
        if page[:Contents].is_a?(HexaPDF::Stream)
          logger.info("  Stream de #{page[:Contents].stream.size} bytes")
        elsif page[:Contents].is_a?(Array)
          logger.info("  Array de #{page[:Contents].size} elementos")
        else
          logger.info("  Tipo inesperado: #{page[:Contents].class}")
        end
      else
        logger.warn("No se encontró la primera página")
      end
    rescue => e
      logger.error("Error al analizar el documento en la etapa #{stage_name}: #{e.message}")
    end
  end

  def self.investigate_cleaning_process(input_file, logger, cleaner)
    # Analizar el documento original
    analyze_document_at_stage("Original", input_file, logger)
    
    # Limpiar con qpdf y analizar
    qpdf_output = Utils.temp_filename("qpdf_clean")
    cleaner.clean_with_qpdf(input_file, qpdf_output)
    analyze_document_at_stage("Después de qpdf", qpdf_output, logger)
    
    # Limpiar con pdftk y analizar
    pdftk_output = Utils.temp_filename("pdftk_clean")
    cleaner.clean_with_pdftk(qpdf_output, pdftk_output)
    analyze_document_at_stage("Después de pdftk", pdftk_output, logger)
    
    # Limpiar con Ghostscript y analizar
    gs_output = Utils.temp_filename("gs_clean")
    cleaner.clean_with_ghostscript(pdftk_output, gs_output)
    analyze_document_at_stage("Después de Ghostscript", gs_output, logger)
    
    # Limpiar archivos temporales
    [qpdf_output, pdftk_output, gs_output].each { |file| Utils.delete_file(file) }
  end
end
