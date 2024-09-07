#!/usr/bin/env ruby

require 'hexapdf'

def clean_pdf(input_file, output_file)
  puts "Limpiando #{input_file}"
  
  begin
    doc = HexaPDF::Document.open(input_file)
    
    # Limpiar el catálogo del documento
    clean_catalog(doc.catalog)
    
    # Limpiar cada página
    doc.pages.each_with_index do |page, index|
      puts "Limpiando página #{index + 1}"
      clean_page(page)
    end
    
    # Guardar el documento limpio
    doc.write(output_file, optimize: true)
    puts "PDF limpio guardado como #{output_file}"
  rescue => e
    puts "Error al limpiar el PDF: #{e.message}"
  end
end

def clean_catalog(catalog)
  keys_to_remove = [:Names, :OpenAction, :AA, :AcroForm, :JavaScript]
  keys_to_remove.each do |key|
    if catalog.key?(key)
      catalog.delete(key)
      puts "Eliminado #{key} del catálogo del documento"
    end
  end
end

def clean_page(page)
  # Eliminar anotaciones
  if page.key?(:Annots)
    page.delete(:Annots)
    puts "Eliminadas anotaciones de la página"
  end
  
  # Eliminar acciones automáticas
  if page.key?(:AA)
    page.delete(:AA)
    puts "Eliminadas acciones automáticas de la página"
  end
  
  # Limpiar recursos de la página
  if page.key?(:Resources)
    clean_resources(page[:Resources])
  end
end

def clean_resources(resources)
  if resources.key?(:JavaScript)
    resources.delete(:JavaScript)
    puts "Eliminado JavaScript de los recursos"
  end
end

def check_risks(file)
  doc = HexaPDF::Document.open(file)
  risk_score = 0
  risk_factors = []

  doc.pages.each do |page|
    risk_score += 1 if page[:Annots]
    risk_score += 1 if page[:AA]
    risk_score += 1 if page[:JS]
    risk_factors << "Annots" if page[:Annots]
    risk_factors << "AA" if page[:AA]
    risk_factors << "JS" if page[:JS]
  end

  root = doc.catalog
  [:Names, :OpenAction, :AA, :AcroForm, :Outlines, :JavaScript].each do |key|
    if root.key?(key)
      risk_score += 1
      risk_factors << key.to_s
    end
  end

  risk_factors.uniq!
  puts "Factores de riesgo encontrados: #{risk_factors.join(', ')}"
  puts "Puntuación de riesgo: #{risk_score}"
  
  [risk_score, risk_factors]
rescue => e
  puts "Error al verificar riesgos: #{e.message}"
  [0, []]
end

if ARGV.empty?
  puts "Uso: #{$PROGRAM_NAME} archivo1.pdf [archivo2.pdf ...]"
  exit 1
end

ARGV.each do |file|
  if File.file?(file) && File.extname(file).downcase == '.pdf'
    output_file = "#{File.basename(file, '.pdf')}_limpio.pdf"
    clean_pdf(file, output_file)
    
    puts "Verificando riesgos en el archivo limpio..."
    risk_score, risk_factors = check_risks(output_file)
    
    if risk_score > 0
      puts "Advertencia: Aún se detectan factores de riesgo después de la limpieza."
      puts "Factores de riesgo restantes: #{risk_factors.join(', ')}"
      puts "Puntuación de riesgo final: #{risk_score}"
    else
      puts "No se detectaron factores de riesgo en el archivo limpio."
    end
  else
    puts "Error: #{file} no es un archivo PDF válido."
  end
end