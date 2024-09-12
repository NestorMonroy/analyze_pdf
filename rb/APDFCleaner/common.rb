require 'logger'
require_relative 'utils'

module Common
  # Crea y configura un logger consistente
  def self.create_logger(log_file = STDOUT)
    logger = Logger.new(log_file)
    logger.formatter = proc do |severity, datetime, progname, msg|
      "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
    end
    logger
  end

  # Clase base para procesadores de PDF
  class PDFProcessor
    def initialize(logger)
      @logger = logger
      @step_hashes = {}
    end

    protected

    def log_info(message)
      @logger.info(message)
    end

    def log_error(message)
      @logger.error(message)
    end

    def log_warn(message)
      @logger.warn(message)
    end

    def step_necessary?(input_file, method_name)
      current_hash = Utils.file_hash(input_file)
      if @step_hashes[method_name] == current_hash
        log_info("Paso #{method_name} omitido: no es necesario")
        false
      else
        @step_hashes[method_name] = current_hash
        true
      end
    end

    def ensure_output_file_created(output_file)
      unless Utils.file_exists?(output_file)
        raise "El archivo de salida no se creó: #{output_file}"
      end
    end

    def safe_process(step_name)
      log_info("Iniciando paso: #{step_name}")
      yield
      log_info("Paso completado: #{step_name}")
    rescue => e
      log_error("Error en paso #{step_name}: #{e.message}")
      log_error(e.backtrace.join("\n"))
      raise
    end
  end

  # Mixin para operaciones comunes de limpieza de PDF
  module PDFCleanerOperations
    def remove_item_from_pages(doc, item_key)
      doc.pages.each_with_index do |page, index|
        if page.key?(item_key)
          log_info("  Eliminando #{item_key} de la página #{index + 1}")
          page.delete(item_key)
        end
      end
    end

    def remove_items_from_catalog(doc, items)
      items.each do |item|
        if doc.catalog.key?(item)
          log_info("  Eliminando #{item} del catálogo")
          doc.catalog.delete(item)
        end
      end
    end
  end
end