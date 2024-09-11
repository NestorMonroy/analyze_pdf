#!/usr/bin/env ruby
require 'hexapdf'
require 'logger'
require 'fileutils'

class CompletePDFCleaner
  def initialize
    @logger = Logger.new(STDOUT)
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
    end
    @output_folder = create_output_folder
  end

  def clean_pdf(input_file)
    base_name = File.basename(input_file, ".*")
    temp_file1 = File.join(@output_folder, "#{base_name}_temp1.pdf")
    temp_file2 = File.join(@output_folder, "#{base_name}_temp2.pdf")
    output_file = File.join(@output_folder, "#{base_name}_limpio.pdf")

    # Paso 1: Limpieza profunda con HexaPDF
    risk_score, risk_factors = deep_clean_pdf(input_file, temp_file1)

    # Paso 2: Sanitizar con HexaPDF
    if sanitize_with_hexapdf(temp_file1, temp_file2)
      # Paso 3: Segunda pasada de limpieza profunda
      final_risk_score, final_risk_factors = deep_clean_pdf(temp_file2, output_file)
      File.delete(temp_file1)
      File.delete(temp_file2)
      
      log_final_risks(final_risk_score, final_risk_factors)
    else
      @logger.warn("Usando el resultado de la primera limpieza como salida final")
      FileUtils.mv(temp_file1, output_file)
      File.delete(temp_file2) if File.exist?(temp_file2)
    end

    @logger.info("Proceso de limpieza completado. Archivo guardado en: #{output_file}")
  end

  def deep_clean_pdf(input_file, output_file)
    @logger.info("Limpieza profunda de #{input_file}")
    doc = HexaPDF::Document.open(input_file)
    risk_score = 0
    risk_factors = []

    doc.pages.each do |page|
      page_risks = deep_clean_page(page)
      risk_score += page_risks.size
      risk_factors.concat(page_risks)
    end

    catalog_risks = clean_document_catalog(doc)
    risk_score += catalog_risks.size
    risk_factors.concat(catalog_risks)
    risk_factors.uniq!

    log_risk_assessment(risk_factors, risk_score)
    doc.write(output_file, optimize: true)
    @logger.info("PDF limpio guardado como #{output_file}")

    [risk_score, risk_factors]
  end

  def sanitize_with_hexapdf(input_file, output_file)
    @logger.info("Sanitizando #{input_file} con HexaPDF")
    begin
      doc = HexaPDF::Document.open(input_file)
      
      # Configurar opciones de HexaPDF
      doc.config['object_streams.write'] = false
      doc.config['linearize'] = true
      doc.config['optimize_objects'] = true
      
      # Eliminar todos los JavaScript y acciones
      doc.each do |obj|
        if obj.kind_of?(HexaPDF::Dictionary)
          [:JS, :JavaScript, :AA, :A].each { |key| obj.delete(key) }
        end
      end
      
      # Escribir el documento optimizado
      doc.write(output_file, optimize: true)
      
      @logger.info("Sanitización con HexaPDF completada")
      true
    rescue => e
      @logger.error("Error al sanitizar con HexaPDF: #{e.message}")
      false
    end
  end

  def check_risks(file)
    doc = HexaPDF::Document.open(file)
    risk_score = 0
    risk_factors = []

    doc.pages.each_with_index do |page, index|
      page_risks = check_page_risks(page)
      if page_risks.any?
        risk_score += page_risks.size
        risk_factors.concat(page_risks)
        @logger.warn("Página #{index + 1}: Riesgos detectados - #{page_risks.join(', ')}")
      end
    end

    catalog_risks = check_catalog_risks(doc.catalog)
    risk_score += catalog_risks.size
    risk_factors.concat(catalog_risks)

    risk_factors.uniq!
    log_risk_assessment(risk_factors, risk_score)
    [risk_score, risk_factors]
  rescue => e
    @logger.error("Error al verificar riesgos: #{e.message}")
    [0, []]
  end

  private

  def create_output_folder
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    output_folder = File.join(Dir.pwd, "PDFs_limpios_#{timestamp}")
    FileUtils.mkdir_p(output_folder)
    @logger.info("Carpeta de salida creada: #{output_folder}")
    output_folder
  end

  def deep_clean_page(page)
    risks = []
    [:Annots, :AA, :JS].each do |key|
      if page[key]
        page.delete(key)
        risks << key.to_s
      end
    end
    risks
  end

  def clean_document_catalog(doc)
    root = doc.catalog
    keys_to_remove = [:Names, :OpenAction, :AA, :AcroForm, :Outlines, :JavaScript]
    risks = []
    keys_to_remove.each do |key|
      if root.key?(key)
        root.delete(key)
        risks << key.to_s
      end
    end
    risks
  end

  def check_page_risks(page)
    risks = []
    [:Annots, :AA, :JS].each do |key|
      risks << key.to_s if page.key?(key)
    end
    risks
  end

  def check_catalog_risks(catalog)
    risks = []
    [:Names, :OpenAction, :AA, :AcroForm, :JavaScript, :JS, :Outlines].each do |key|
      if catalog.key?(key)
        risks << key.to_s
        @logger.warn("Catálogo: Riesgo detectado - #{key}")
      end
    end
    risks
  end

  def log_risk_assessment(risk_factors, risk_score)
    @logger.info("Factores de riesgo encontrados: #{risk_factors.join(', ')}")
    @logger.info("Puntuación de riesgo: #{risk_score}")
  end

  def log_final_risks(final_risk_score, final_risk_factors)
    if final_risk_score > 0
      @logger.warn("Atención: Aún se detectan factores de riesgo después de la limpieza.")
      @logger.warn("Factores de riesgo restantes: #{final_risk_factors.join(', ')}")
      @logger.warn("Puntuación de riesgo final: #{final_risk_score}")
    else
      @logger.info("Todos los factores de riesgo conocidos han sido eliminados.")
    end
  end
end

# Código principal
if ARGV.empty?
  puts "Uso: #{$PROGRAM_NAME} archivo1.pdf [archivo2.pdf ...]"
  exit 1
end

cleaner = CompletePDFCleaner.new
ARGV.each do |file|
  if File.file?(file) && File.extname(file).downcase == '.pdf'
    cleaner.clean_pdf(file)
  elsif !File.exist?(file)
    cleaner.instance_variable_get(:@logger).error("Error: El archivo #{file} no existe.")
  else
    cleaner.instance_variable_get(:@logger).error("Error: #{file} no es un archivo PDF.")
  end
end