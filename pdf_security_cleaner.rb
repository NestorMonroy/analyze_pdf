#!/usr/bin/env ruby

require 'hexapdf'
require 'logger'
require 'fileutils'

# Crear un logger global
$logger = Logger.new(STDOUT)
$logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}\n"
end

def deep_clean_pdf(input_file, output_file)
  $logger.info("Limpieza profunda de #{input_file}")
  doc = HexaPDF::Document.open(input_file)
  doc.pages.each do |page|
    deep_clean_page(page)
  end
  clean_document_catalog(doc)
  doc.write(output_file, optimize: true)
  $logger.info("PDF limpio guardado como #{output_file}")
end

def deep_clean_page(page)
  page.delete(:Annots)
  page.delete(:AA)
  page.delete(:JS)
end

def clean_document_catalog(doc)
  root = doc.catalog
  keys_to_remove = [:Names, :OpenAction, :AA, :AcroForm, :Outlines, :JavaScript]
  keys_to_remove.each do |key|
    root.delete(key)
  end
end

def sanitize_with_hexapdf(input_file, output_file)
  $logger.info("Sanitizando #{input_file} con HexaPDF")
  begin
    doc = HexaPDF::Document.open(input_file)
    
    # Desactivar compresión de objetos
    doc.config['object_streams.write'] = false
    
    # Linearizar el documento
    doc.config['linearize'] = true
    
    # Optimizar el documento
    doc.config['optimize_objects'] = true
    
    # Escribir el documento optimizado
    doc.write(output_file, optimize: true)
    
    $logger.info("Sanitización con HexaPDF completada")
    true
  rescue => e
    $logger.error("Error al sanitizar con HexaPDF: #{e.message}")
    false
  end
end

def clean_pdf(input_file)
  base_name = File.basename(input_file, ".*")
  temp_file1 = "#{base_name}_temp1.pdf"
  temp_file2 = "#{base_name}_temp2.pdf"
  output_file = "#{base_name}_limpio.pdf"

  # Paso 1: Limpieza profunda con HexaPDF
  deep_clean_pdf(input_file, temp_file1)

  # Paso 2: Sanitizar con HexaPDF
  if sanitize_with_hexapdf(temp_file1, temp_file2)
    # Paso 3: Segunda pasada de limpieza profunda
    deep_clean_pdf(temp_file2, output_file)
    File.delete(temp_file1)
    File.delete(temp_file2)
  else
    $logger.warn("Usando el resultado de la primera limpieza como salida final")
    FileUtils.mv(temp_file1, output_file)
    File.delete(temp_file2) if File.exist?(temp_file2)
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