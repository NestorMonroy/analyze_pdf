require_relative 'common'
require_relative 'utils'

class ExternalToolCleaner < Common::PDFProcessor
  def initialize(logger)
    super(logger)
  end

  def clean(input_file, output_file)
    return unless Utils.valid_pdf?(input_file)

    temp_file = Utils.temp_filename("external_clean")

    safe_process("Limpieza con herramientas externas") do
      clean_with_qpdf(input_file, temp_file)
      clean_with_pdftk(temp_file, output_file)
      clean_with_ghostscript(output_file, output_file)
    end

    Utils.delete_file(temp_file)
  end

  private

  def clean_with_qpdf(input_file, output_file)
    log_info("Limpiando con qpdf: #{input_file}")
    cmd = "qpdf --linearize --object-streams=disable --remove-unreferenced-resources=yes #{input_file} #{output_file}"
    success, output = Utils.execute_command(cmd)
    
    if success
      log_info("qpdf completado exitosamente")
    else
      log_error("Error en qpdf: #{output}")
      raise "qpdf falló: #{output}"
    end
  end

  def clean_with_pdftk(input_file, output_file)
    log_info("Limpiando con pdftk: #{input_file}")
    cmd = "pdftk #{input_file} output #{output_file} flatten"
    success, output = Utils.execute_command(cmd)
    
    if success
      log_info("pdftk completado exitosamente")
    else
      log_error("Error en pdftk: #{output}")
      raise "pdftk falló: #{output}"
    end
  end

  def clean_with_ghostscript(input_file, output_file)
    log_info("Limpiando con Ghostscript: #{input_file}")
    cmd = "gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/default -dNOPAUSE -dQUIET -dBATCH -sOutputFile=#{output_file} #{input_file}"
    success, output = Utils.execute_command(cmd)
    
    if success
      log_info("Ghostscript completado exitosamente")
    else
      log_error("Error en Ghostscript: #{output}")
      raise "Ghostscript falló: #{output}"
    end
  end
end
