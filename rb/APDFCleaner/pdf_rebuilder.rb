require 'hexapdf'
require "zlib"
require_relative 'common'
require_relative 'utils'

module PDFRebuilder
  def self.included(base)
    base.send :attr_reader, :logger, :verbose
  end

  def initialize_pdf_rebuilder(logger, verbose = false)
    @logger = logger
    @verbose = verbose
  end

  def rebuild_document(doc)
    @logger.info("Reconstruyendo documento")
    new_doc = HexaPDF::Document.new
  
    doc.pages.each_with_index do |old_page, index|
      new_page = new_doc.pages.add
      if old_page[:Contents]
        new_contents = deep_copy_object(old_page[:Contents], new_doc)
        if new_contents.is_a?(HexaPDF::Dictionary)
          @logger.info("  Página #{index + 1}: Convirtiendo Dictionary a Stream")
          stream = new_doc.add({Type: :XObject, Subtype: :Form})
          stream.stream = decompress_flate(new_contents)
          new_page[:Contents] = stream
        else
          new_page[:Contents] = new_contents
        end
        @logger.info("  Página #{index + 1}: Contenido copiado")
      else
        @logger.warn("  Página #{index + 1}: Sin contenido para copiar")
      end
      
      new_page[:Resources] = deep_copy_resources(old_page[:Resources], new_doc)
      new_page[:MediaBox] = deep_copy_object(old_page[:MediaBox], new_doc) || [0, 0, 612, 792]
      
      [:CropBox, :BleedBox, :TrimBox, :ArtBox, :Rotate].each do |key|
        new_page[key] = deep_copy_object(old_page[key], new_doc) if old_page.key?(key)
      end
  
      @logger.info("  Página #{index + 1} reconstruida")
    end
  
    [:Info, :ViewerPreferences, :PageLayout, :PageMode].each do |key|
      new_doc.catalog[key] = deep_copy_object(doc.catalog[key], new_doc) if doc.catalog.key?(key)
    end
  
    @logger.info("Documento reconstruido exitosamente")
    new_doc
  end

  def deep_copy_object(obj, new_doc)
    case obj
    when HexaPDF::Dictionary
      if obj[:Type] == :XObject && obj[:Subtype] == :Form
        # Este es un caso especial donde el Dictionary debería ser un Stream
        new_stream = new_doc.add({Type: :XObject, Subtype: :Form})
        obj.each do |key, value|
          new_stream[key] = deep_copy_object(value, new_doc) unless key == :Length
        end
        new_stream.stream = obj.value[:Length] ? obj.document.object(obj).stream : ''
        new_stream
      else
        new_dict = new_doc.add({})
        obj.each do |key, value|
          new_dict[key] = deep_copy_object(value, new_doc)
        end
        new_dict
      end
    when HexaPDF::Stream
      new_stream = new_doc.add({})
      obj.value.each do |key, value|
        new_stream[key] = deep_copy_object(value, new_doc)
      end
      new_stream.stream = obj.stream.dup
      new_stream
    when HexaPDF::Reference
      deep_copy_object(obj.value, new_doc)
    when Array, HexaPDF::PDFArray
      obj.map { |item| deep_copy_object(item, new_doc) }
    when HexaPDF::Rectangle
      HexaPDF::Rectangle.new(*obj.value)
    else
      obj.respond_to?(:dup) ? obj.dup : obj
    end
  rescue => e
    @logger.warn("Error al copiar objeto: #{e.message}. Tipo de objeto: #{obj.class}")
    obj
  end

  def deep_copy_resources(resources, new_doc)
    return unless resources.is_a?(HexaPDF::Dictionary)
    new_resources = new_doc.add({})
    resources.each do |key, value|
      new_resources[key] = deep_copy_object(value, new_doc)
    end
    new_resources
  end

  def decompress_flate(obj)
    if obj.is_a?(HexaPDF::Dictionary) && obj[:Filter] == :FlateDecode && obj[:Length].is_a?(Integer)
      begin
        stream_obj = obj.document.object(obj)
        if stream_obj.is_a?(HexaPDF::Stream)
          Zlib::Inflate.inflate(stream_obj.stream)
        else
          @logger.warn("No se pudo obtener el stream del objeto")
          ''
        end
      rescue Zlib::DataError => e
        @logger.error("Error al descomprimir stream: #{e.message}")
        ''
      rescue => e
        @logger.error("Error inesperado al descomprimir: #{e.message}")
        ''
      end
    elsif obj.is_a?(HexaPDF::Stream) && obj[:Filter] == :FlateDecode
      begin
        Zlib::Inflate.inflate(obj.stream)
      rescue Zlib::DataError => e
        @logger.error("Error al descomprimir stream: #{e.message}")
        ''
      rescue => e
        @logger.error("Error inesperado al descomprimir: #{e.message}")
        ''
      end
    else
      obj.is_a?(HexaPDF::Stream) ? obj.stream : ''
    end
  end

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
      elsif content.is_a?(HexaPDF::Stream)
        @logger.info("  Página #{index + 1}: 1 stream de contenido (#{content.stream.size} bytes)")
      elsif content.is_a?(HexaPDF::Dictionary)
        @logger.info("  Página #{index + 1}: Contenido es un Dictionary (no un Stream)")
      else
        @logger.warn("  Página #{index + 1}: Tipo de contenido inesperado: #{content.class}")
      end
    end
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
      elsif page[:Contents].is_a?(HexaPDF::Dictionary)
        @logger.info("  Página #{index + 1}: Contenido es un Dictionary")
        content = decompress_flate(page[:Contents])
        @logger.info("    Tamaño del contenido descomprimido: #{content.size} bytes")
        @logger.debug("    Primeros 100 bytes: #{content[0..100]}")
      else
        @logger.warn("  Página #{index + 1}: Contenido de tipo inesperado (#{page[:Contents].class})")
      end
    end
  end
end