require 'hexapdf'
require_relative 'common'
require_relative 'utils'

class PDFAnalyzer < Common::PDFProcessor
  include Common::PDFCleanerOperations

  def initialize(logger, verbose = false)
    super(logger, verbose)
  end

  def analyze(input_file)
    @logger.info("Analizando #{input_file}")
    return unless Utils.valid_pdf?(input_file)

    safe_process("Análisis estructural profundo") do
      deep_structure_analysis(input_file)
    end
  end

  private

  def deep_structure_analysis(input_file)
    @logger.info("Realizando análisis estructural profundo de #{input_file}")
    doc = HexaPDF::Document.open(input_file)
    
    analyze_document_structure(doc)
    analyze_catalog(doc)
    analyze_pages(doc)
    analyze_objects(doc)

    @logger.info("Análisis estructural completado para #{input_file}")
  end

  def analyze_document_structure(doc)
    @logger.info("Estructura del documento:")
    @logger.info("  Versión PDF: #{doc.version}")
    @logger.info("  Número de páginas: #{doc.pages.count}")
    @logger.info("  Encriptado: #{doc.encrypted?}")
  end

  def analyze_catalog(doc)
    @logger.info("Analizando catálogo del documento:")
    [:Names, :OpenAction, :AA, :AcroForm, :JavaScript, :JS, :Outlines].each do |key|
      if doc.catalog.key?(key)
        @logger.warn("  Encontrado elemento potencialmente riesgoso en el catálogo: #{key}")
      end
    end
  end

  def analyze_pages(doc)
    doc.pages.each_with_index do |page, index|
      @logger.info("Analizando página #{index + 1}:")
      [:Annots, :AA, :JS].each do |key|
        if page.key?(key)
          @logger.warn("  Encontrado elemento potencialmente riesgoso en la página: #{key}")
        end
      end
      analyze_page_content(page, index + 1)
    end
  end

  def analyze_page_content(page, page_number)
    content = page[:Contents]
    if content.is_a?(HexaPDF::Stream)
      stream_data = content.stream
      @logger.info("  Contenido de la página #{page_number}: #{stream_data.size} bytes")
      if stream_data.include?('/JavaScript') || stream_data.include?('/JS')
        @logger.warn("  Posible JavaScript encontrado en el contenido de la página #{page_number}")
      end
    end
  end

  def analyze_objects(doc)
    object_types = Hash.new(0)
    doc.each do |obj|
      object_types[obj.type] += 1
      if obj.is_a?(HexaPDF::Stream)
        analyze_stream(obj)
      end
    end
    @logger.info("Resumen de objetos:")
    object_types.each do |type, count|
      @logger.info("  #{type}: #{count}")
    end
  end

  def analyze_stream(obj)
    stream_data = obj.stream
    if stream_data.include?('/JavaScript') || stream_data.include?('/JS')
      @logger.warn("  Stream sospechoso encontrado en objeto #{obj.oid}")
    end
  end
end