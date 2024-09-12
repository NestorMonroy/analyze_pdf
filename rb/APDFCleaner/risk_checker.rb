require 'hexapdf'
require_relative 'common'
require_relative 'utils'

class RiskChecker < Common::PDFProcessor
  def initialize(logger, verbose = false)
    super(logger, verbose)
    @risk_factors = []
  end

  def check_risks(file)
    return unless Utils.valid_pdf?(file)

    safe_process("Verificación final de riesgos") do
      doc = HexaPDF::Document.open(file)
      
      check_catalog_risks(doc)
      check_page_risks(doc)
      check_stream_risks(doc)
      check_metadata_risks(doc)
      
      report_risks
    end
  end

  private

  def check_catalog_risks(doc)
    @logger.info("Verificando riesgos en el catálogo")
    risky_keys = [:Names, :OpenAction, :AA, :AcroForm, :JavaScript, :JS, :Outlines]
    risky_keys.each do |key|
      if doc.catalog.key?(key)
        add_risk("Elemento potencialmente riesgoso en el catálogo: #{key}")
      end
    end
  end

  def check_page_risks(doc)
    @logger.info("Verificando riesgos en las páginas")
    doc.pages.each_with_index do |page, index|
      [:Annots, :AA, :JS].each do |key|
        if page.key?(key)
          add_risk("Elemento potencialmente riesgoso en la página #{index + 1}: #{key}")
        end
      end
    end
  end

  def check_stream_risks(doc)
    @logger.info("Verificando riesgos en streams")
    doc.each do |obj|
      if obj.is_a?(HexaPDF::Stream)
        stream_data = obj.stream
        if stream_data.include?('/JavaScript') || stream_data.include?('/JS')
          add_risk("Stream sospechoso encontrado en objeto #{obj.oid}")
        end
      end
    end
  end

  def check_metadata_risks(doc)
    @logger.info("Verificando riesgos en metadatos")
    if doc.trailer.key?(:Info)
      info = doc.trailer[:Info]
      suspicious_keys = [:Creator, :Producer, :Author, :Title, :Subject, :Keywords]
      suspicious_keys.each do |key|
        if info.key?(key) && info[key].to_s.include?('script')
          add_risk("Metadato sospechoso encontrado: #{key}")
        end
      end
    end
  end

  def add_risk(description)
    @risk_factors << description
    @logger.warn(description)
  end

  def report_risks
    if @risk_factors.empty?
      @logger.info("No se detectaron factores de riesgo en el archivo final.")
    else
      @logger.warn("Se detectaron los siguientes factores de riesgo:")
      @risk_factors.each_with_index do |risk, index|
        @logger.warn("  #{index + 1}. #{risk}")
      end
    end
  end
end