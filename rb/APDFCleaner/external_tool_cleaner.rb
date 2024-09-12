require_relative 'common'
require_relative 'utils'
require 'hexapdf'

class ExternalToolCleaner < Common::PDFProcessor
  def initialize(logger, verbose = false)
    super(logger, verbose)
  end

  def clean(input_file, output_file)
    return unless Utils.valid_pdf?(input_file)
    doc = HexaPDF::Document.open(input_file)
    temp_file = Utils.temp_filename("external_clean")
    
    safe_process("Limpieza con herramientas externas") do
      clean_with_qpdf(input_file, temp_file)
      clean_with_pdftk(temp_file, output_file)
      success = clean_with_ghostscript(output_file, output_file)
      unless success
        @logger.warn("Ghostscript falló, usando el resultado de pdftk")
        FileUtils.cp(temp_file, output_file)
      end
    end
    doc = rebuild_document(doc)
    log_document_info(doc, "Después de reconstruir documento")

    verify_pdf_content(doc)
    
    doc.write(output_file, optimize: true)
    ensure_output_file_created(output_file)
    log_document_info(HexaPDF::Document.open(output_file), "Archivo final")
    Utils.delete_file(temp_file)
  end

  private

  def clean_with_qpdf(input_file, output_file)
    @logger.info("Limpiando con qpdf: #{input_file}")

    cmd = "qpdf --linearize --object-streams=disable --compress-streams=y --decode-level=specialized --remove-page-labels --flatten-annotations=all --generate-appearances #{input_file} #{output_file}"
    success, output = Utils.execute_command(cmd)
   
    if success
      @logger.info("qpdf completado exitosamente")
    else
      @logger.error("Error en qpdf: #{output}")
      raise "qpdf falló: #{output}"
    end
  end

  def clean_with_pdftk(input_file, output_file)
    @logger.info("Limpiando con pdftk: #{input_file}")
    cmd = "pdftk #{input_file} output #{output_file} flatten"
    success, output = Utils.execute_command(cmd)
    
    if success
      @logger.info("pdftk completado exitosamente")
    else
      @logger.error("Error en pdftk: #{output}")
      raise "pdftk falló: #{output}"
    end
  end

  # #cmd = "gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.5 -dPDFSETTINGS=/prepress -dDetectDuplicateImages=false -dNOPAUSE -dQUIET -dBATCH -dNOOUTERSAVE -dNOCCITT -sOutputFile=#{output_file} #{input_file}"

  def clean_with_ghostscript(input_file, output_file)
    @logger.info("Limpiando con Ghostscript: #{input_file}")
    cmd = "gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.5 -dPDFSETTINGS=/prepress -dNOPAUSE -dQUIET -dBATCH -sOutputFile=#{output_file} #{input_file}"
    success, output = Utils.execute_command(cmd)
   
    if success
      @logger.info("Ghostscript completado exitosamente")
     
      # Verificar que el archivo de salida tiene contenido
      if File.size(output_file) > 0
        doc = HexaPDF::Document.open(output_file)
        if doc.pages.count == 0
          @logger.error("Ghostscript produjo un documento sin páginas")
          return false
        end
      else
        @logger.error("Ghostscript produjo un archivo vacío")
        return false
      end
     
      true
    else
      @logger.error("Error en Ghostscript: #{output}")
      false
    end
  end
  
end
