require 'hexapdf'
require 'logger'
require 'fileutils'
require 'open3'
require 'digest'
require 'thread'
require 'etc'

def check_and_install_dependencies
  missing_gems = []
  missing_tools = []

  # Verificar gemas de Ruby
  required_gems = ['hexapdf', 'logger', 'fileutils', 'open3', 'digest']
  required_gems.each do |gem|
    begin
      require gem
    rescue LoadError
      missing_gems << gem
    end
  end

  # Verificar herramientas externas
  required_tools = ['qpdf', 'pdftk', 'gs']
  required_tools.each do |tool|
    missing_tools << tool unless system("which #{tool} > /dev/null 2>&1")
  end

  if missing_gems.any? || missing_tools.any?
    puts "Se detectaron dependencias faltantes:"
    puts "Gemas de Ruby faltantes: #{missing_gems.join(', ')}" if missing_gems.any?
    puts "Herramientas externas faltantes: #{missing_tools.join(', ')}" if missing_tools.any?

    if missing_gems.any?
      print "\n¿Desea intentar instalar las gemas de Ruby faltantes? (s/n): "
      if gets.chomp.downcase == 's'
        install_missing_gems(missing_gems)
      else
        puts "Por favor, instale las gemas manualmente con: gem install #{missing_gems.join(' ')}"
      end
    end

    if missing_tools.any?
      puts "\nPara las herramientas externas faltantes, por favor siga estas instrucciones:"
      provide_tool_installation_instructions(missing_tools)
    end

    puts "\nPor favor, asegúrese de que todas las dependencias estén instaladas antes de continuar."
    exit 1
  else
    puts "Todas las dependencias están instaladas correctamente."
  end
end

def install_missing_gems(gems)
  gems.each do |gem|
    puts "Intentando instalar #{gem}..."
    system("gem install #{gem}")
    if $?.success?
      puts "#{gem} instalado correctamente."
    else
      puts "Error al instalar #{gem}. Por favor, instálelo manualmente."
    end
  end
end

def provide_tool_installation_instructions(tools)
  tools.each do |tool|
    puts "\nPara instalar #{tool}:"
    case tool
    when 'qpdf'
      # puts "  - En Ubuntu/Debian: sudo apt-get install qpdf"
      # puts "  - En macOS con Homebrew: brew install qpdf"
      # puts "  - En Windows: Descargue desde https://qpdf.sourceforge.io/"
    when 'pdftk'
      # puts "  - En Ubuntu/Debian: sudo apt-get install pdftk"
      # puts "  - En macOS con Homebrew: brew install pdftk-java"
      # puts "  - En Windows: Descargue desde https://www.pdflabs.com/tools/pdftk-the-pdf-toolkit/"
    when 'gs'
      # puts "  - En Ubuntu/Debian: sudo apt-get install ghostscript"
      # puts "  - En macOS con Homebrew: brew install ghostscript"
      # puts "  - En Windows: Descargue desde https://www.ghostscript.com/releases/gsdnld.html"
    end
  end
end

class AdvancedPDFCleaner
  def initialize
    @logger = Logger.new(STDOUT)
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
    end
    @output_folder = create_output_folder
    @queue = Queue.new
    @threads = []
    @max_threads = Etc.nprocessors  # Obtiene el número de núcleos disponibles
  end

  def clean_pdfs(input_files)
    # Llenar la cola con los archivos de entrada
    input_files.each { |file| @queue << file }

    # Crear hilos de trabajo
    @max_threads.times do
      @threads << Thread.new do
        while !@queue.empty?
          file = @queue.pop(true) rescue nil
          break unless file
          clean_single_pdf(file)
        end
      end
    end

    # Esperar a que todos los hilos terminen
    @threads.each(&:join)

    @logger.info("Todos los PDFs han sido procesados.")
  end

  def clean_pdf(input_file)
    unless File.exist?(input_file)
      @logger.error("El archivo de entrada no existe: #{input_file}")
      return
    end

    unless valid_pdf?(input_file)
      @logger.error("El archivo no es un PDF válido: #{input_file}")
      return
    end

    base_name = File.basename(input_file, ".*")
    temp_file1 = File.join(@output_folder, "#{base_name}_temp1.pdf")
    temp_file2 = File.join(@output_folder, "#{base_name}_temp2.pdf")
    output_file = File.join(@output_folder, "#{base_name}_limpio.pdf")

    @logger.info("Iniciando limpieza avanzada de #{input_file}")

    steps = [
      { method: :deep_structure_analysis, input: input_file, output: nil },
      { method: :clean_with_qpdf, input: input_file, output: temp_file1 },
      { method: :initial_clean_with_hexapdf, input: temp_file1, output: temp_file2 },
      { method: :decompress_and_clean, input: temp_file2, output: temp_file1 },
      { method: :selective_stream_removal, input: temp_file1, output: temp_file2 },
      { method: :analyze_and_remove_actions, input: temp_file2, output: temp_file1 },
      { method: :rebuild_document, input: temp_file1, output: temp_file2 },
      { method: :advanced_clean_with_external_tools, input: temp_file2, output: output_file }
    ]

    steps.each_with_index do |step, index|
      @logger.info("Paso #{index + 1}: #{step[:method]}")
      begin
        if step[:output]
          unless step_necessary?(step[:input], step[:method])
            @logger.info("  Paso omitido: no es necesario")
            FileUtils.cp(step[:input], step[:output])
            next
          end
        end
        
        send(step[:method], step[:input], step[:output])
        
        if step[:output] && !File.exist?(step[:output])
          raise "El archivo de salida no se creó: #{step[:output]}"
        end
        
        @logger.info("  Paso completado exitosamente")
      rescue => e
        @logger.error("Error en el paso #{index + 1} (#{step[:method]}): #{e.message}")
        @logger.error(e.backtrace.join("\n"))
        return
      end
    end

    # Limpieza de archivos temporales
    [temp_file1, temp_file2].each { |f| File.delete(f) if File.exist?(f) }

    @logger.info("Proceso de limpieza completado. Archivo final: #{output_file}")
    
    # Verificación final de riesgos
    check_final_risks(output_file)
  end

  private

  def create_output_folder
    output_folder = File.join(Dir.pwd, "PDFs_limpios_avanzado")
    FileUtils.mkdir_p(output_folder) unless Dir.exist?(output_folder)
    @logger.info("Usando carpeta de salida: #{output_folder}")
    output_folder
  end

  def valid_pdf?(file)
    File.open(file, 'rb') { |f| f.read(4) } == '%PDF'
  end

  def step_necessary?(input_file, method)
    current_hash = Digest::MD5.file(input_file).hexdigest
    if @step_hashes[method] == current_hash
      false
    else
      @step_hashes[method] = current_hash
      true
    end
  end

  def deep_structure_analysis(input_file, _output_file)
    @logger.info("Realizando análisis estructural profundo de #{input_file}")
    doc = HexaPDF::Document.open(input_file)
    
    doc.each do |obj|
      @logger.debug("Objeto #{obj.oid} #{obj.gen} #{obj.type}")
      if obj.is_a?(HexaPDF::Dictionary)
        obj.each do |key, value|
          @logger.debug("  #{key}: #{value.class}")
          if value.is_a?(HexaPDF::Stream)
            stream_data = value.stream
            @logger.debug("    Stream (#{stream_data.size} bytes): #{stream_data[0..50]}...")
          end
        end
      elsif obj.is_a?(HexaPDF::Stream)
        stream_data = obj.stream
        @logger.debug("  Stream (#{stream_data.size} bytes): #{stream_data[0..50]}...")
      end
    end
  end

  def clean_with_qpdf(input_file, output_file)
    @logger.info("Limpiando con qpdf: #{input_file}")
    cmd = "qpdf --linearize --object-streams=disable --remove-unreferenced-resources=yes #{input_file} #{output_file}"
    
    Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
      exit_status = wait_thr.value
      if exit_status.success?
        @logger.info("qpdf completado exitosamente")
      else
        error_msg = stderr.read
        @logger.error("Error en qpdf: #{error_msg}")
        raise "qpdf falló: #{error_msg}"
      end
    end
  end

  def initial_clean_with_hexapdf(input_file, output_file)
    @logger.info("Limpieza inicial con HexaPDF de #{input_file}")
    doc = HexaPDF::Document.open(input_file)
    
    doc.pages.each_with_index do |page, index|
      [:Annots, :AA, :JS].each do |key|
        if page.key?(key)
          @logger.info("  Eliminando #{key} de la página #{index + 1}")
          page.delete(key)
        end
      end
    end

    [:Names, :OpenAction, :AA, :AcroForm, :JavaScript, :JS, :Outlines].each do |key|
      if doc.catalog.key?(key)
        @logger.info("  Eliminando #{key} del catálogo")
        doc.catalog.delete(key)
      end
    end

    doc.write(output_file, optimize: true)
  end

  def decompress_and_clean(input_file, output_file)
    @logger.info("Descomprimiendo y limpiando #{input_file}")
    doc = HexaPDF::Document.open(input_file)
    
    decompressed_count = 0
    doc.revisions.each do |revision|
      revision.xref.each do |oid, xref_entry|
        if xref_entry.in_use? && xref_entry.compressed?
          obj = doc.object(oid)
          doc.add(obj)
          decompressed_count += 1
        end
      end
    end
    
    @logger.info("  Descomprimidos #{decompressed_count} objetos")
    
    doc.config['object_streams.write'] = false
    doc.write(output_file, optimize: true)
  end

  def selective_stream_removal(input_file, output_file)
    @logger.info("Eliminación selectiva de streams en #{input_file}")
    doc = HexaPDF::Document.open(input_file)
    
    removed_count = 0
    doc.each do |obj|
      if obj.is_a?(HexaPDF::Stream)
        stream_data = obj.stream
        if stream_data.include?('/JavaScript') || stream_data.include?('/JS')
          @logger.info("  Eliminando stream sospechoso en objeto #{obj.oid}")
          obj.stream = ''
          removed_count += 1
        end
      end
    end
    
    @logger.info("  Eliminados #{removed_count} streams sospechosos")
    doc.write(output_file)
  end

  def analyze_and_remove_actions(input_file, output_file)
    @logger.info("Analizando y eliminando acciones en #{input_file}")
    doc = HexaPDF::Document.open(input_file)
    
    action_count = 0
    doc.pages.each_with_index do |page, index|
      if page.key?(:AA)
        @logger.info("  Encontradas acciones adicionales en la página #{index + 1}")
        page.delete(:AA)
        action_count += 1
      end
      
      if page.key?(:Annots)
        page[:Annots].value.each do |annot|
          if annot[:A] || annot[:AA]
            @logger.info("  Encontrada acción en anotación en página #{index + 1}")
            annot.delete(:A)
            annot.delete(:AA)
            action_count += 1
          end
        end
      end
    end
    
    if doc.catalog.key?(:OpenAction)
      @logger.info("  Eliminando OpenAction del catálogo")
      doc.catalog.delete(:OpenAction)
      action_count += 1
    end
    
    @logger.info("  Total de acciones eliminadas: #{action_count}")
    doc.write(output_file)
  end

  def rebuild_document(input_file, output_file)
    @logger.info("Reconstruyendo documento #{input_file}")
    original = HexaPDF::Document.open(input_file)
    new_doc = HexaPDF::Document.new
    
    page_count = 0
    original.pages.each do |old_page|
      new_page = new_doc.pages.add
      new_page[:Contents] = new_doc.add(old_page[:Contents])
      new_page[:Resources] = deep_copy_resources(old_page[:Resources], new_doc)
      page_count += 1
    end
    
    @logger.info("  Reconstruidas #{page_count} páginas")
    new_doc.write(output_file)
  end

  def deep_copy_resources(resources, new_doc)
    return unless resources.is_a?(HexaPDF::Dictionary)
    
    new_resources = new_doc.add({})
    resources.each do |key, value|
      new_resources[key] = if value.is_a?(HexaPDF::Dictionary)
                             deep_copy_resources(value, new_doc)
                           else
                             new_doc.add(value)
                           end
    end
    new_resources
  end

  def advanced_clean_with_external_tools(input_file, output_file)
    @logger.info("Limpieza avanzada con herramientas externas de #{input_file}")
    temp_file = "temp_#{Time.now.to_i}.pdf"
    
    # Usar pdftk para 'aplanar' el documento
    pdftk_cmd = "pdftk #{input_file} output #{temp_file} flatten"
    execute_command(pdftk_cmd, "pdftk")

    # Usar Ghostscript para una limpieza adicional
    gs_cmd = "gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/default -dNOPAUSE -dQUIET -dBATCH -sOutputFile=#{output_file} #{temp_file}"
    execute_command(gs_cmd, "Ghostscript")
    
    File.delete(temp_file) if File.exist?(temp_file)
  end

  def execute_command(cmd, tool_name)
    Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
      exit_status = wait_thr.value
      if exit_status.success?
        @logger.info("  #{tool_name} completado exitosamente")
      else
        error_msg = stderr.read
        @logger.error("Error en #{tool_name}: #{error_msg}")
        raise "#{tool_name} falló: #{error_msg}"
      end
    end
  end

  def check_final_risks(file)
    @logger.info("Verificación final de riesgos en #{file}")
    doc = HexaPDF::Document.open(file)
    risk_factors = []

    # Verificar el catálogo
    [:Names, :OpenAction, :AA, :AcroForm, :JavaScript, :JS, :Outlines].each do |key|
      if doc.catalog.key?(key)
        risk_factors << key.to_s
        @logger.warn("Riesgo detectado en el catálogo: #{key}")
      end
    end

    # Verificar todas las páginas
    doc.pages.each_with_index do |page, index|
      [:Annots, :AA, :JS].each do |key|
        if page.key?(key)
          risk_factors << "#{key} en página #{index + 1}"
          @logger.warn("Riesgo detectado en página #{index + 1}: #{key}")
        end
      end
    end

    if risk_factors.empty?
      @logger.info("No se detectaron factores de riesgo en el archivo final.")
    else
      @logger.warn("Factores de riesgo restantes: #{risk_factors.join(', ')}")
    end
  end
end

# Código principal
if ARGV.empty?
  puts "Uso: #{$PROGRAM_NAME} archivo1.pdf [archivo2.pdf ...]"
  exit 1
end

cleaner = AdvancedPDFCleaner.new
ARGV.each do |file|
  if File.file?(file) && File.extname(file).downcase == '.pdf'
    cleaner.clean_pdf(file)
  elsif !File.exist?(file)
    cleaner.instance_variable_get(:@logger).error("Error: El archivo #{file} no existe.")
  else
    cleaner.instance_variable_get(:@logger).error("Error: #{file} no es un archivo PDF válido.")
  end
end
