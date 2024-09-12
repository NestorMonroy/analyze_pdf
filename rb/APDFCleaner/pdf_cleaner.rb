require 'hexapdf'
require_relative 'common'
require_relative 'utils'

class PDFCleaner < Common::PDFProcessor
  include Common::PDFCleanerOperations

  def initialize(logger)
    super(logger)
  end

  def clean(input_file, output_file)
    return unless Utils.valid_pdf?(input_file)

    safe_process("Limpieza de PDF") do
      doc = HexaPDF::Document.open(input_file)
      
      initial_clean(doc)
      decompress_and_clean(doc)
      selective_stream_removal(doc)
      analyze_and_remove_actions(doc)
      rebuild_document(doc)

      doc.write(output_file, optimize: true)
      ensure_output_file_created(output_file)
    end
  end

  private

  def initial_clean(doc)
    log_info("Realizando limpieza inicial")
    remove_item_from_pages(doc, :Annots)
    remove_item_from_pages(doc, :AA)
    remove_item_from_pages(doc, :JS)
    remove_items_from_catalog(doc, [:Names, :OpenAction, :AA, :AcroForm, :JavaScript, :JS, :Outlines])
  end

  def decompress_and_clean(doc)
    log_info("Descomprimiendo y limpiando objetos")
    decompressed_count = 0
    doc.each do |obj|
      if obj.is_a?(HexaPDF::Stream) && obj.compressed?
        obj.stream
        decompressed_count += 1
      end
    end
    log_info("  Descomprimidos #{decompressed_count} objetos")
    doc.config['object_streams.write'] = false
  end

  def selective_stream_removal(doc)
    log_info("Realizando eliminación selectiva de streams")
    removed_count = 0
    doc.each do |obj|
      if obj.is_a?(HexaPDF::Stream)
        stream_data = obj.stream
        if stream_data.include?('/JavaScript') || stream_data.include?('/JS')
          obj.stream = ''
          removed_count += 1
        end
      end
    end
    log_info("  Eliminados #{removed_count} streams sospechosos")
  end

  def analyze_and_remove_actions(doc)
    log_info("Analizando y eliminando acciones")
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
    log_info("  Total de acciones eliminadas: #{action_count}")
  end

  def rebuild_document(doc)
    log_info("Reconstruyendo documento")
    new_doc = HexaPDF::Document.new
    doc.pages.each_with_index do |old_page, index|
      new_page = new_doc.pages.add
      new_page[:Contents] = new_doc.add(old_page[:Contents])
      new_page[:Resources] = deep_copy_resources(old_page[:Resources], new_doc)
      log_info("  Página #{index + 1} reconstruida")
    end
    doc.replace(new_doc)
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
end