require_relative 'common'
require_relative 'utils'
require 'hexapdf'
require_relative 'pdf_rebuilder'

class ExternalToolCleaner < Common::PDFProcessor
  include PDFRebuilder

  def initialize(logger, verbose = false)
    super(logger, verbose)
    initialize_pdf_rebuilder(logger, verbose)
  end

  def clean(input_file, output_file)
    return unless Utils.valid_pdf?(input_file)
  
    temp_file = Utils.temp_filename("external_clean")
    
    safe_process("Limpieza con herramientas externas") do
      begin
        clean_with_qpdf(input_file, temp_file)
        clean_with_pdftk(temp_file, output_file)
        success = clean_with_ghostscript(output_file, output_file)
        
        unless success
          @logger.warn("Ghostscript falló, usando el resultado de pdftk")
          FileUtils.cp(temp_file, output_file)
        end
  
        doc = HexaPDF::Document.open(output_file)
        doc = rebuild_document(doc)
        log_document_info(doc, "Después de reconstruir documento")
        verify_pdf_content(doc)
     
        doc.write(output_file, optimize: true)
      rescue => e
        @logger.error("Error durante el proceso de limpieza: #{e.message}")
        @logger.error(e.backtrace.join("\n"))
        FileUtils.cp(input_file, output_file)
      ensure
        Utils.delete_file(temp_file)
      end
    end
  
    ensure_output_file_created(output_file)
    log_document_info(HexaPDF::Document.open(output_file), "Archivo final")
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

  def clean_with_ghostscript(input_file, output_file)
    @logger.info("Limpiando con Ghostscript: #{input_file}")
    cmd = "gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.5 -dPDFSETTINGS=/prepress -dNOPAUSE -dQUIET -dBATCH -sOutputFile=#{output_file} #{input_file}"
    success, output = Utils.execute_command(cmd)
   
    if success
      @logger.info("Ghostscript completado exitosamente")
     
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