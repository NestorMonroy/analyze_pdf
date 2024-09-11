#!/usr/bin/env ruby

require 'hexapdf'
require 'logger'
require 'fileutils'

class EnhancedPDFCleaner
  def initialize
    @logger = Logger.new(STDOUT)
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
    end
    @output_folder = create_output_folder
  end

  def clean_pdf(input_file)
    base_name = File.basename(input_file, ".*")
    output_file = File.join(@output_folder, "#{base_name}_limpio.pdf")

    @logger.info("Iniciando limpieza agresiva de #{input_file}")
    
    begin
      doc = HexaPDF::Document.open(input_file)
      
      # Limpieza agresiva
      aggressive_clean(doc)
      
      # Guardar el documento limpio
      doc.write(output_file, optimize: true)
      
      @logger.info("Limpieza completada. Archivo guardado en: #{output_file}")
      
      # Verificar riesgos después de la limpieza
      check_risks(output_file)
    rescue => e
      @logger.error("Error durante la limpieza del PDF: #{e.message}")
    end
  end

  private

  def create_output_folder
    output_folder = File.join(Dir.pwd, "limpieza")
    FileUtils.mkdir_p(output_folder)
    @logger.info("Carpeta de salida creada: #{output_folder}")
    output_folder
  end

  def aggressive_clean(doc)
    clean_catalog(doc.catalog)
    doc.pages.each { |page| clean_page(page) }
    clean_form_fields(doc)
    remove_all_aa(doc)
  end

  def clean_catalog(catalog)
    keys_to_remove = [:Names, :OpenAction, :AA, :AcroForm, :JavaScript, :JS, :Outlines]
    keys_to_remove.each do |key|
      if catalog.key?(key)
        catalog.delete(key)
        @logger.info("Eliminado #{key} del catálogo del documento")
      end
    end
  end

  def clean_page(page)
    [:Annots, :AA, :JS].each do |key|
      if page.key?(key)
        page.delete(key)
        @logger.info("Eliminado #{key} de la página")
      end
    end
    clean_resources(page[:Resources]) if page.key?(:Resources)
  end

  def clean_resources(resources)
    return unless resources.is_a?(HexaPDF::Dictionary)
    [:JavaScript, :JS].each do |key|
      if resources.key?(key)
        resources.delete(key)
        @logger.info("Eliminado #{key} de los recursos")
      end
    end
  end

  def clean_form_fields(doc)
    return unless doc.catalog.key?(:AcroForm)
    form = doc.catalog[:AcroForm]
    if form.key?(:Fields)
      form[:Fields].each do |field|
        clean_field(field)
      end
    end
  end

  def clean_field(field)
    [:A, :AA, :JS].each do |key|
      if field.key?(key)
        field.delete(key)
        @logger.info("Eliminado #{key} del campo de formulario")
      end
    end
  end

  def remove_all_aa(doc)
    doc.each do |obj|
      if obj.is_a?(HexaPDF::Dictionary) && obj.key?(:AA)
        obj.delete(:AA)
        @logger.info("Eliminado AA de un objeto del documento")
      end
    end
  end

  def check_risks(file)
    @logger.info("Verificando riesgos en el archivo limpio: #{file}")
    doc = HexaPDF::Document.open(file)
    risk_factors = []

    # Verificar el catálogo
    catalog_risks = check_catalog_risks(doc.catalog)
    risk_factors.concat(catalog_risks)

    # Verificar todas las páginas
    doc.pages.each_with_index do |page, index|
      page_risks = check_page_risks(page)
      if page_risks.any?
        @logger.warn("Página #{index + 1}: Riesgos detectados - #{page_risks.join(', ')}")
        risk_factors.concat(page_risks)
      end
    end

    # Verificar todos los objetos en busca de AA
    doc.each do |obj|
      if obj.is_a?(HexaPDF::Dictionary) && obj.key?(:AA)
        risk_factors << "AA en objeto"
        @logger.warn("Detectado AA en un objeto del documento")
      end
    end

    risk_factors.uniq!
    if risk_factors.empty?
      @logger.info("No se detectaron factores de riesgo en el archivo limpio.")
    else
      @logger.warn("Factores de riesgo encontrados: #{risk_factors.join(', ')}")
    end
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

  def check_page_risks(page)
    risks = []
    [:Annots, :AA, :JS].each do |key|
      risks << key.to_s if page.key?(key)
    end
    risks
  end
end

# Código principal
if ARGV.empty?
  puts "Uso: #{$PROGRAM_NAME} archivo1.pdf [archivo2.pdf ...]"
  exit 1
end

cleaner = EnhancedPDFCleaner.new
ARGV.each do |file|
  if File.file?(file) && File.extname(file).downcase == '.pdf'
    cleaner.clean_pdf(file)
  elsif !File.exist?(file)
    cleaner.instance_variable_get(:@logger).error("Error: El archivo #{file} no existe.")
  else
    cleaner.instance_variable_get(:@logger).error("Error: #{file} no es un archivo PDF.")
  end
end