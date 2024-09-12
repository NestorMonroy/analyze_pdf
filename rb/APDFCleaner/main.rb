require_relative 'utils'
require_relative 'common'
require_relative 'pdf_analyzer'
require_relative 'pdf_cleaner'
require_relative 'external_tool_cleaner'
require_relative 'risk_checker'

class AdvancedPDFCleaner
  def initialize
    @logger = Common.create_logger
    @output_folder = Utils.create_output_folder(Dir.pwd, "PDFs_limpios_avanzado")
    @analyzer = PDFAnalyzer.new(@logger)
    @cleaner = PDFCleaner.new(@logger)
    @external_cleaner = ExternalToolCleaner.new(@logger)
    @risk_checker = RiskChecker.new(@logger)
  end

  def clean_pdf(input_file)
    unless File.exist?(input_file)
      @logger.error("El archivo de entrada no existe: #{input_file}")
      return
    end

    unless Utils.valid_pdf?(input_file)
      @logger.error("El archivo no es un PDF válido: #{input_file}")
      return
    end

    base_name = File.basename(input_file, ".*")
    temp_file1 = File.join(@output_folder, "#{base_name}_temp1.pdf")
    temp_file2 = File.join(@output_folder, "#{base_name}_temp2.pdf")
    output_file = File.join(@output_folder, "#{base_name}_limpio.pdf")

    @logger.info("Iniciando limpieza avanzada de #{input_file}")

    begin
      # Paso 1: Análisis inicial
      @analyzer.analyze(input_file)

      # Paso 2: Limpieza con herramientas externas
      @external_cleaner.clean(input_file, temp_file1)

      # Paso 3: Limpieza interna
      @cleaner.clean(temp_file1, temp_file2)

      # Paso 4: Limpieza final con herramientas externas
      @external_cleaner.clean(temp_file2, output_file)

      # Paso 5: Verificación final de riesgos
      @risk_checker.check_risks(output_file)

      # Limpieza de archivos temporales
      Utils.delete_file(temp_file1)
      Utils.delete_file(temp_file2)

      @logger.info("Proceso de limpieza completado. Archivo final: #{output_file}")
    rescue => e
      @logger.error("Error durante el proceso de limpieza: #{e.message}")
      @logger.error(e.backtrace.join("\n"))
    end
  end

  def clean_pdfs(input_files)
    input_files.each do |file|
      clean_pdf(file)
    end
    @logger.info("Todos los PDFs han sido procesados.")
  end
end

# Código principal
if __FILE__ == $0
  if ARGV.empty?
    puts "Uso: ruby #{$0} archivo1.pdf [archivo2.pdf ...]"
    exit 1
  end

  cleaner = AdvancedPDFCleaner.new
  input_files = ARGV.select { |file| File.file?(file) && File.extname(file).downcase == '.pdf' }

  if input_files.empty?
    puts "No se encontraron archivos PDF válidos."
    exit 1
  end

  cleaner.clean_pdfs(input_files)
end