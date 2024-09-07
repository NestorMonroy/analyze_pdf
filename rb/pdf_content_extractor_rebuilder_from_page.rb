#!/usr/bin/env ruby

require 'hexapdf'
require 'fileutils'

def extract_and_rebuild_pdf(input_file, output_file)
  puts "Procesando #{input_file}"
  
  # Crear un nuevo documento
  new_doc = HexaPDF::Document.new

  begin
    # Abrir el documento original
    original_doc = HexaPDF::Document.open(input_file)
    
    original_doc.pages.each_with_index do |page, index|
      puts "Procesando página #{index + 1}"
      
      # Crear una nueva página
      new_page = new_doc.pages.add

      # Extraer y añadir contenido
      extract_and_add_content(page, new_page, new_doc)
    end

    # Guardar el nuevo documento
    new_doc.write(output_file)
    puts "Nuevo PDF creado: #{output_file}"
  rescue => e
    puts "Error al procesar el PDF: #{e.message}"
    puts "Intentando guardar el documento parcialmente procesado..."
    new_doc.write(output_file)
  end
end

def extract_and_add_content(old_page, new_page, new_doc)
  begin
    # Intentar extraer texto
    text = extract_text_from_page(old_page)
    unless text.empty?
      canvas = new_page.canvas
      canvas.font('Helvetica', size: 12)
      y_position = new_page.box.height - 50
      text.each_line do |line|
        break if y_position < 50
        canvas.text(line.chomp, at: [50, y_position])
        y_position -= 15
      end
    end

    # Intentar extraer imágenes
    extract_images_from_page(old_page, new_page, new_doc)
  rescue => e
    puts "Error al extraer o añadir contenido: #{e.message}"
  end
end

def extract_text_from_page(page)
  text = ""
  begin
    if page[:Contents].kind_of?(HexaPDF::Stream)
      content = page[:Contents].stream
      content.force_encoding('UTF-8')
      content.scrub!
      text << content.scan(/\((.*?)\)/).join(' ')
    elsif page[:Contents].kind_of?(Array)
      page[:Contents].each do |obj|
        if obj.kind_of?(HexaPDF::Stream)
          content = obj.stream
          content.force_encoding('UTF-8')
          content.scrub!
          text << content.scan(/\((.*?)\)/).join(' ')
        end
      end
    end
  rescue => e
    puts "Error al extraer texto: #{e.message}"
  end
  text
end

def extract_images_from_page(old_page, new_page, new_doc)
  begin
    if old_page[:Resources] && old_page[:Resources][:XObject]
      old_page[:Resources][:XObject].each do |name, xobject|
        if xobject.type == :Image
          new_image = new_doc.add(xobject)
          new_page.canvas.image(new_image, at: [50, new_page.box.height - 100], width: 200)
        end
      end
    end
  rescue => e
    puts "Error al extraer imágenes: #{e.message}"
  end
end

def check_risks(file)
  return unless File.exist?(file)
  
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
    output_file = "#{File.basename(file, '.pdf')}_reconstruido.pdf"
    extract_and_rebuild_pdf(file, output_file)
    
    puts "Verificando riesgos en el archivo reconstruido..."
    risk_score, risk_factors = check_risks(output_file)
    
    if risk_score > 0
      puts "Advertencia: Aún se detectan factores de riesgo después de la reconstrucción."
      puts "Factores de riesgo restantes: #{risk_factors.join(', ')}"
      puts "Puntuación de riesgo final: #{risk_score}"
    else
      puts "No se detectaron factores de riesgo en el archivo reconstruido."
    end
  else
    puts "Error: #{file} no es un archivo PDF válido."
  end
end