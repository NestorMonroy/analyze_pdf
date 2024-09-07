#!/usr/bin/env ruby

require 'hexapdf'
require 'logger'
require 'fileutils'

# Crear un logger global
$logger = Logger.new(STDOUT)
$logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}\n"
end

def sanitize_with_qpdf(input_file, output_file)
  $logger.info("Sanitizando #{input_file} con qpdf")
  qpdf_command = [
    "qpdf", 
    "--linearize",
    "--object-streams=disable",
    "--remove-unreferenced-resources=yes",
    "--pages", ".",  # Procesa todas las páginas
    "--",
    input_file,
    output_file
  ]

  begin
    system(*qpdf_command)
    if $?.success?
      $logger.info("Sanitización con qpdf completada")
      true
    else
      $logger.error("Error al sanitizar con qpdf")
      false
    end
  rescue => e
    $logger.error("Error al ejecutar qpdf: #{e.message}")
    false
  end
end

# El resto del script permanece igual...

def deep_clean_pdf(input_file, output_file)
  $logger.info("Limpieza profunda de #{input_file}")
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
  $logger.info("Factores de riesgo encontrados: #{risk_factors.join(', ')}")
  $logger.info("Puntuación de riesgo: #{risk_score}")

  doc.write(output_file, optimize: true)
  $logger.info("PDF limpio guardado como #{output_file}")
  
  [risk_score, risk_factors]
end

def deep_clean_page(page)
  risks = []
  if page[:Annots]
    page.delete(:Annots)
    risks << "Annots"
  end
  if page[:AA]
    page.delete(:AA)
    risks << "AA"
  end
  if page[:JS]
    page.delete(:JS)
    risks << "JS"
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

def clean_pdf(input_file)
  base_name = File.basename(input_file, ".*")
  temp_file1 = "#{base_name}_temp1.pdf"
  output_file = "#{base_name}_limpio.pdf"

  # Paso 1: Sanitizar con qpdf
  if sanitize_with_qpdf(input_file, temp_file1)
    # Paso 2: Limpieza profunda con HexaPDF
    final_risk_score, final_risk_factors = deep_clean_pdf(temp_file1, output_file)
    File.delete(temp_file1)
    
    if final_risk_score > 0
      $logger.warn("Atención: Aún se detectan factores de riesgo después de la limpieza.")
      $logger.warn("Factores de riesgo restantes: #{final_risk_factors.join(', ')}")
      $logger.warn("Puntuación de riesgo final: #{final_risk_score}")
    else
      $logger.info("Todos los factores de riesgo conocidos han sido eliminados.")
    end
  else
    $logger.warn("La sanitización con qpdf falló, usando el archivo original")
    FileUtils.cp(input_file, output_file)
  end

  $logger.info("Proceso de limpieza completado")
end

if ARGV.empty?
  puts "Uso: #{$PROGRAM_NAME} archivo1.pdf [archivo2.pdf ...]"
  exit 1
end

ARGV.each do |file|
  if File.file?(file) && File.extname(file).downcase == '.pdf'
    clean_pdf(file)
  elsif !File.exist?(file)
    $logger.error("Error: El archivo #{file} no existe.")
  else
    $logger.error("Error: #{file} no es un archivo PDF.")
  end
end