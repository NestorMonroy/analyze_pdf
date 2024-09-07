#!/usr/bin/env ruby

require 'hexapdf'
require 'logger'
require 'fileutils'
require 'tempfile'

# Crear un logger global
$logger = Logger.new(STDOUT)
$logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}\n"
end

def sanitize_with_pdftk(input_file, output_file)
  $logger.info("Sanitizando #{input_file} con pdftk")
  begin
    system("pdftk", input_file, "output", output_file, "uncompress")
    if $?.success?
      $logger.info("Descompresión con pdftk completada")
      true
    else
      $logger.error("Error al descomprimir con pdftk")
      false
    end
  rescue => e
    $logger.error("Error al ejecutar pdftk: #{e.message}")
    false
  end
end

def aggressive_clean(input_file, output_file)
  $logger.info("Limpieza agresiva de #{input_file}")
  content = File.binread(input_file)
  
  # Convertir contenido a UTF-8, ignorando caracteres inválidos
  content = content.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
  
  # Eliminar todos los streams de JavaScript
  content.gsub!(/\/JS\s*<<.*?>>/m, '')
  content.gsub!(/\/JavaScript\s*<<.*?>>/m, '')
  
  # Eliminar todas las acciones automáticas
  content.gsub!(/\/AA\s*<<.*?>>/m, '')
  
  # Eliminar todas las anotaciones
  content.gsub!(/\/Annots\s*\[.*?\]/m, '')
  
  # Eliminar referencias a OpenAction
  content.gsub!(/\/OpenAction\s*<<.*?>>/m, '')
  
  File.binwrite(output_file, content)
  $logger.info("Limpieza agresiva completada")
end

def recompress_pdf(input_file, output_file)
  $logger.info("Recomprimiendo #{input_file}")
  begin
    system("pdftk", input_file, "output", output_file, "compress")
    if $?.success?
      $logger.info("Recompresión con pdftk completada")
      true
    else
      $logger.error("Error al recomprimir con pdftk")
      false
    end
  rescue => e
    $logger.error("Error al ejecutar pdftk: #{e.message}")
    false
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
  $logger.info("Factores de riesgo encontrados: #{risk_factors.join(', ')}")
  $logger.info("Puntuación de riesgo: #{risk_score}")
  
  [risk_score, risk_factors]
end

def clean_pdf(input_file)
  base_name = File.basename(input_file, ".*")
  temp_file1 = Tempfile.new([base_name, '.pdf'])
  temp_file2 = Tempfile.new([base_name, '.pdf'])
  output_file = "#{base_name}_limpio.pdf"

  begin
    # Paso 1: Descomprimir con pdftk
    if sanitize_with_pdftk(input_file, temp_file1.path)
      # Paso 2: Limpieza agresiva
      aggressive_clean(temp_file1.path, temp_file2.path)
      
      # Paso 3: Recomprimir con pdftk
      if recompress_pdf(temp_file2.path, output_file)
        # Paso 4: Verificar riesgos restantes
        final_risk_score, final_risk_factors = check_risks(output_file)
        
        if final_risk_score > 0
          $logger.warn("Atención: Aún se detectan factores de riesgo después de la limpieza.")
          $logger.warn("Factores de riesgo restantes: #{final_risk_factors.join(', ')}")
          $logger.warn("Puntuación de riesgo final: #{final_risk_score}")
        else
          $logger.info("Todos los factores de riesgo conocidos han sido eliminados.")
        end
      else
        $logger.warn("La recompresión falló, usando el archivo de limpieza agresiva")
        FileUtils.cp(temp_file2.path, output_file)
      end
    else
      $logger.warn("La descompresión con pdftk falló, usando el archivo original")
      FileUtils.cp(input_file, output_file)
    end
  rescue => e
    $logger.error("Error durante el proceso de limpieza: #{e.message}")
    $logger.error(e.backtrace.join("\n"))
    $logger.warn("Usando el archivo original debido a un error")
    FileUtils.cp(input_file, output_file)
  ensure
    temp_file1.close
    temp_file1.unlink
    temp_file2.close
    temp_file2.unlink
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