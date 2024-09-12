require 'hexapdf'
require "zlib"
require_relative 'common'
require_relative 'utils'

class PDFCleaner < Common::PDFProcessor
  include Common::PDFCleanerOperations

  def initialize(logger, verbose = false)
    super(logger, verbose)
  end

  def clean(input_file, output_file)
    return unless Utils.valid_pdf?(input_file)
  
    safe_process("Limpieza de PDF") do
      doc = HexaPDF::Document.open(input_file)
      
      log_document_info(doc, "Antes de cualquier procesamiento")
      initial_clean(doc)
      log_document_info(doc, "Después de limpieza inicial")
      decompress_and_clean(doc)
      log_document_info(doc, "Después de descompresión")
      selective_stream_removal(doc)
      log_document_info(doc, "Después de eliminación de streams")
      
      analyze_and_remove_actions(doc)
      log_document_info(doc, "Después de eliminar acciones")
      
      preserve_content(doc)
      log_document_info(doc, "Después de preservar contenido")
      
      rebuild_document(doc)
      log_document_info(doc, "Después de reconstruir documento")
  
      verify_pdf_content(doc)
      
      doc.write(output_file, optimize: true)
      ensure_output_file_created(output_file)
      log_document_info(HexaPDF::Document.open(output_file), "Archivo final")
    end
  end

  private

  def log_document_info(doc, prefix = "Información del documento")
    @logger.info("#{prefix}:")
    @logger.info("  Número de páginas: #{doc.pages.count}")
    @logger.info("  Número total de objetos: #{doc.each.count}")
    doc.pages.each_with_index do |page, index|
      content = page[:Contents]
      if content.nil?
        @logger.warn("  Página #{index + 1}: Sin contenido")
      elsif content.is_a?(Array)
        @logger.info("  Página #{index + 1}: #{content.size} streams de contenido")
      else
        @logger.info("  Página #{index + 1}: 1 stream de contenido (#{content.stream.size} bytes)")
      end
    end
  end

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

  def rebuild_document(doc)
    @logger.info("Reconstruyendo documento")
    new_doc = HexaPDF::Document.new
  
    doc.pages.each_with_index do |old_page, index|
      new_page = new_doc.pages.add
      if old_page[:Contents]
        new_contents = deep_copy_object(old_page[:Contents], new_doc)
        if new_contents.is_a?(HexaPDF::Stream)
          new_page[:Contents] = new_contents
          @logger.info("  Página #{index + 1}: Contenido copiado (Stream)")
        elsif new_contents.is_a?(Array)
          new_page[:Contents] = new_contents.map { |obj| obj.is_a?(HexaPDF::Stream) ? obj : new_doc.add(obj) }
          @logger.info("  Página #{index + 1}: Contenido copiado (Array de #{new_contents.size} elementos)")
        elsif new_contents.is_a?(HexaPDF::Dictionary)
          new_stream = new_doc.add({Type: :XObject, Subtype: :Form, BBox: [0, 0, 100, 100]})
          new_stream.stream = decompress_flate(new_contents)
          new_page[:Contents] = new_stream
          @logger.info("  Página #{index + 1}: Contenido convertido de Dictionary a Stream")
        else
          @logger.warn("  Página #{index + 1}: Contenido no es un Stream, Array, ni Dictionary (#{new_contents.class})")
          new_page[:Contents] = new_doc.add(new_contents)
        end
      else
        @logger.warn("  Página #{index + 1}: Sin contenido para copiar")
      end
      new_page[:Resources] = deep_copy_resources(old_page[:Resources], new_doc)
      new_page[:MediaBox] = old_page[:MediaBox] || [0, 0, 612, 792]  # Tamaño de página por defecto
      @logger.info("  Página #{index + 1} reconstruida")
    end

    # Reemplazar todas las páginas del documento original con las nuevas páginas
    while doc.pages.count > 0
      doc.pages.delete(doc.pages[0])
    end
    
    new_doc.pages.each do |new_page|
      doc.pages.add(doc.import(new_page))
    end

    # Copiar metadatos y otras propiedades importantes
    [:Info, :ViewerPreferences, :PageLayout, :PageMode].each do |key|
      doc.catalog[key] = deep_copy_object(new_doc.catalog[key], doc) if new_doc.catalog.key?(key)
    end

    @logger.info("Documento reconstruido exitosamente")
  end

  def decompress_flate(obj)
    if obj[:Filter] == :FlateDecode && obj[:Length].is_a?(Integer)
      begin
        if obj.is_a?(HexaPDF::Stream)
          Zlib::Inflate.inflate(obj.stream)
        elsif obj.is_a?(HexaPDF::Dictionary)
          # Si es un diccionario, intentamos obtener el stream del objeto referenciado
          stream_obj = obj.document.object(obj)
          if stream_obj.is_a?(HexaPDF::Stream)
            Zlib::Inflate.inflate(stream_obj.stream)
          else
            @logger.warn("No se pudo obtener el stream del objeto")
            obj.value[:Length].to_s  # Devolvemos la longitud como string
          end
        else
          @logger.warn("Objeto no es ni Stream ni Dictionary")
          ''
        end
      rescue Zlib::DataError => e
        @logger.error("Error al descomprimir stream: #{e.message}")
        ''
      end
    else
      if obj.is_a?(HexaPDF::Stream)
        obj.stream
      else
        @logger.warn("Objeto no tiene un stream válido")
        ''
      end
    end
  end
  
  def deep_copy_object(obj, new_doc)
    case obj
    when HexaPDF::Dictionary
      new_dict = new_doc.add({})
      obj.each do |key, value|
        new_dict[key] = deep_copy_object(value, new_doc)
      end
      new_dict
    when HexaPDF::Stream
      new_stream = new_doc.add({})
      obj.value.each do |key, value|
        new_stream[key] = deep_copy_object(value, new_doc)
      end
      new_stream.stream = obj.stream.dup
      new_stream
    when HexaPDF::Reference
      deep_copy_object(obj.value, new_doc)
    when Array
      obj.map { |item| deep_copy_object(item, new_doc) }
    else
      if obj.respond_to?(:dup)
        obj.dup
      else
        obj
      end
    end
  rescue => e
    @logger.warn("Error al copiar objeto: #{e.message}. Tipo de objeto: #{obj.class}")
    obj
  end

  def verify_pdf_content(doc)
    @logger.info("Verificando contenido del PDF reconstruido")
    doc.pages.each_with_index do |page, index|
      if page[:Contents].nil?
        @logger.warn("  Página #{index + 1}: Sin contenido")
      elsif page[:Contents].is_a?(HexaPDF::Stream)
        content = page[:Contents].stream
        @logger.info("  Página #{index + 1}: Contenido (#{content.size} bytes)")
        @logger.debug("    Primeros 100 bytes: #{content[0..100]}")
      elsif page[:Contents].is_a?(Array)
        @logger.info("  Página #{index + 1}: #{page[:Contents].size} streams de contenido")
      else
        @logger.warn("  Página #{index + 1}: Contenido de tipo inesperado (#{page[:Contents].class})")
      end
    end
  end

  def deep_copy_resources(resources, new_doc)
    return unless resources.is_a?(HexaPDF::Dictionary)
    new_resources = new_doc.add({})
    resources.each do |key, value|
      new_resources[key] = deep_copy_object(value, new_doc)
    end
    new_resources
  end

end