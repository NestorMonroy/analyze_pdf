require 'hexapdf'
require 'zlib'
require_relative 'common'
require_relative 'utils'
require_relative 'external_tool_cleaner'
require_relative 'pdf_rebuilder'

class PDFCleaner < Common::PDFProcessor
  include Common::PDFCleanerOperations
  include PDFRebuilder

  def initialize(logger, verbose = false)
    super(logger, verbose)
    initialize_pdf_rebuilder(logger, verbose)
    @external_cleaner = ExternalToolCleaner.new(logger, verbose)
  end

  def clean(input_file, output_file)
    return unless Utils.valid_pdf?(input_file)
  
    safe_process("Limpieza de PDF") do
      doc = HexaPDF::Document.open(input_file)
      
      log_document_info(doc, "Antes de cualquier procesamiento")
      initial_clean(doc)
      log_document_info(doc, "Después de limpieza inicial")

      temp_file1 = Utils.temp_filename("clean_1")
      temp_file2 = Utils.temp_filename("clean_2")

      doc.write(temp_file1)

      @external_cleaner.clean(temp_file1, temp_file2)

      doc = HexaPDF::Document.open(temp_file2)
      
      decompress_and_clean(doc)
      log_document_info(doc, "Después de descompresión")
      
      selective_stream_removal(doc)
      log_document_info(doc, "Después de eliminación de streams")
      
      analyze_and_remove_actions(doc)
      log_document_info(doc, "Después de eliminar acciones")
      
      preserve_content(doc)
      log_document_info(doc, "Después de preservar contenido")
      
      doc = rebuild_document(doc)
      log_document_info(doc, "Después de reconstruir documento")
  
      verify_pdf_content(doc)
      
      doc.write(output_file, optimize: true)
      ensure_output_file_created(output_file)
      log_document_info(HexaPDF::Document.open(output_file), "Archivo final")

      [temp_file1, temp_file2].each { |file| File.delete(file) if File.exist?(file) }
    end
  end

  private

  def initial_clean(doc)
    @logger.info("Realizando limpieza inicial")
    remove_item_from_pages(doc, :Annots)
    remove_item_from_pages(doc, :AA)
    remove_item_from_pages(doc, :JS)
    remove_items_from_catalog(doc, [:Names, :OpenAction, :AA, :AcroForm, :JavaScript, :JS, :Outlines])
  end

  def decompress_and_clean(doc)
    @logger.info("Descomprimiendo y limpiando objetos")
    decompressed_count = 0
    doc.each do |obj|
      if obj.is_a?(HexaPDF::Stream) && stream_compressed?(obj)
        begin
          obj.stream
          decompressed_count += 1
        rescue => e
          @logger.error("Error al descomprimir stream (objeto #{obj.oid},#{obj.gen}): #{e.message}")
        end
      end
    end
    @logger.info("  Descomprimidos #{decompressed_count} objetos")
    doc.config['object_streams.write'] = false
  end

  def stream_compressed?(stream)
    stream.value.key?(:Filter) ||
    (stream.value[:Length].to_i > 0 && stream.raw_stream && stream.raw_stream.frozen?)
  end

  def selective_stream_removal(doc)
    @logger.info("Realizando eliminación selectiva de streams")
    removed_count = 0
    doc.each(only_current: false) do |obj|
      if obj.kind_of?(HexaPDF::Stream)
        begin
          stream_data = obj.stream
          if stream_contains_javascript?(stream_data)
            obj.stream = ''
            removed_count += 1
          end
        rescue => e
          @logger.error("Error al procesar stream (objeto #{obj.oid},#{obj.gen}): #{e.message}")
        end
      end
    end
    @logger.info("  Eliminados #{removed_count} streams sospechosos")
  end

  def stream_contains_javascript?(stream_data)
    stream_data.include?('/JavaScript') ||
    stream_data.include?('/JS') ||
    stream_data.include?('javascript:') ||
    stream_data.downcase.include?('function(') ||
    stream_data.downcase.include?('eval(')
  end

  def analyze_and_remove_actions(doc)
    @logger.info("Analizando y eliminando acciones")
    action_count = 0
    doc.pages.each_with_index do |page, index|
      if page.key?(:AA)
        page.delete(:AA)
        action_count += 1
      end
      if page.key?(:Annots)
        page[:Annots].value.each do |annot|
          if annot[:A] || annot[:AA]
            annot.delete(:A)
            annot.delete(:AA)
            action_count += 1
          end
        end
      end
    end
    if doc.catalog.key?(:OpenAction)
      doc.catalog.delete(:OpenAction)
      action_count += 1
    end
    @logger.info("  Total de acciones eliminadas: #{action_count}")
  end

  def preserve_content(doc)
    @logger.info("Preservando contenido de las páginas")
    doc.pages.each_with_index do |page, index|
      if page[:Contents].nil? || (page[:Contents].kind_of?(HexaPDF::Stream) && page[:Contents].stream.empty?)
        @logger.warn("  Página #{index + 1} está vacía")
      else
        @logger.info("  Página #{index + 1} tiene contenido")
      end
    end
  end
end