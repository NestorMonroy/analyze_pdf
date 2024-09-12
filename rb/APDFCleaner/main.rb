require_relative 'utils'
require_relative 'common'
require_relative 'pdf_analyzer'
require_relative 'pdf_cleaner'
require_relative 'external_tool_cleaner'
require_relative 'risk_checker'
require 'optparse'

class AdvancedPDFCleaner
  def initialize(options)
    log_file = File.join(Dir.pwd, "pdf_cleaner_log.txt")
    @logger = Utils.create_logger(log_file, options[:verbose])
    @output_folder = Utils.create_output_folder(Dir.pwd, options[:output_folder] || "PDFs_limpios_avanzado")
    @analyzer = PDFAnalyzer.new(@logger)
    @cleaner = PDFCleaner.new(@logger)
    @external_cleaner = ExternalToolCleaner.new(@logger)
    @risk_checker = RiskChecker.new(@logger)
   
    check_permissions
  end

  def check_permissions
    begin
      Utils.check_permissions(@output_folder, ['qpdf', 'pdftk', 'gs'])
    rescue StandardError => e
      @logger.error(e.message)
      exit 1
    end
  end

  def clean_pdf(input_file)
    begin
      Utils.validate_pdf_file(input_file)
    rescue StandardError => e
      @logger.error(e.message)
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
      @logger.debug(e.backtrace.join("\n"))
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
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Uso: ruby #{$0} [opciones] archivo1.pdf [archivo2.pdf ...]"

    opts.on("-v", "--verbose", "Ejecutar en modo verbose") do
      options[:verbose] = true
    end

    opts.on("-o", "--output FOLDER", "Especificar carpeta de salida") do |folder|
      options[:output_folder] = folder
    end

    opts.on("-h", "--help", "Mostrar este mensaje de ayuda") do
      puts opts
      exit
    end
  end.parse!

  if ARGV.empty?
    puts "Error: No se proporcionaron archivos PDF para limpiar."
    puts "Uso: ruby #{$0} [opciones] archivo1.pdf [archivo2.pdf ...]"
    puts "Use -h o --help para más información sobre las opciones disponibles."
    exit 1
  end

  cleaner = AdvancedPDFCleaner.new(options)
  input_files = ARGV.select do |file|
    begin
      Utils.validate_pdf_file(file)
      true
    rescue StandardError => e
      puts "Error: #{e.message}"
      false
    end
  end

  if input_files.empty?
    puts "No se encontraron archivos PDF válidos y legibles."
    exit 1
  end

  cleaner.clean_pdfs(input_files)
end
