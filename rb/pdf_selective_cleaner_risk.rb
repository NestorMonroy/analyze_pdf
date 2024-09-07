#!/usr/bin/env ruby
require 'hexapdf'

def clean_pdf(input_file, output_file)
  puts "Limpiando #{input_file}"
  begin
    doc = HexaPDF::Document.open(input_file)
    clean_catalog(doc.catalog)
    doc.pages.each_with_index do |page, index|
      puts "Limpiando página #{index + 1}"
      clean_page(page)
    end
    doc.write(output_file, optimize: true)
    puts "PDF limpio guardado como #{output_file}"
  rescue => e
    puts "Error al limpiar el PDF: #{e.message}"
  end
end

def clean_catalog(catalog)
  keys_to_remove = [:Names, :OpenAction, :AA, :AcroForm, :JavaScript, :JS]
  keys_to_remove.each do |key|
    if catalog.key?(key)
      catalog.delete(key)
      puts "Eliminado #{key} del catálogo del documento"
    end
  end
end

def clean_page(page)
  [:Annots, :AA, :JS].each do |key|
    if page.key?(key)
      page.delete(key)
      puts "Eliminado #{key} de la página"
    end
  end
  if page.key?(:Resources)
    clean_resources(page[:Resources])
  end
end

def clean_resources(resources)
  [:JavaScript, :JS].each do |key|
    if resources.key?(key)
      resources.delete(key)
      puts "Eliminado #{key} de los recursos"
    end
  end
end

def check_risks(file)
  doc = HexaPDF::Document.open(file)
  risk_score = 0
  risk_factors = []
  
  doc.pages.each_with_index do |page, index|
    page_risks = []
    [:Annots, :AA, :JS].each do |key|
      if page.key?(key)
        risk_score += 1
        page_risks << key.to_s
      end
    end
    if page_risks.any?
      risk_factors.concat(page_risks)
      puts "Página #{index + 1}: Riesgos detectados - #{page_risks.join(', ')}"
    end
  end
  
  root = doc.catalog
  [:Names, :OpenAction, :AA, :AcroForm, :JavaScript, :JS].each do |key|
    if root.key?(key)
      risk_score += 1
      risk_factors << key.to_s
      puts "Catálogo: Riesgo detectado - #{key}"
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