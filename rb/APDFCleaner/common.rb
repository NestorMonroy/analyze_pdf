require_relative 'utils'

module Common
  class PDFProcessor
    def initialize(logger)
      @logger = logger
      @step_hashes = {}
    end

    protected

    def log_debug(message)
      @logger.debug(message)
    end

    def log_info(message)
      @logger.info(message)
    end

    def log_warn(message)
      @logger.warn(message)
    end

    def log_error(message)
      @logger.error(message)
    end

    def step_necessary?(input_file, method_name)
      current_hash = Utils.file_hash(input_file)
      if @step_hashes[method_name] == current_hash
        log_debug("Paso #{method_name} omitido: no es necesario")
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
      log_debug(e.backtrace.join("\n"))
      raise
    end
  end

  # Mixin para operaciones comunes de limpieza de PDF
  module PDFCleanerOperations
    def remove_item_from_pages(doc, item_key)
      doc.pages.each_with_index do |page, index|
        if page.key?(item_key)
          log_debug("  Eliminando #{item_key} de la página #{index + 1}")
          page.delete(item_key)
        end
      end
    end

    def remove_items_from_catalog(doc, items)
      items.each do |item|
        if doc.catalog.key?(item)
          log_debug("  Eliminando #{item} del catálogo")
          doc.catalog.delete(item)
        end
      end
    end
  end

  def self.check_permissions(output_folder, external_tools)
    Utils.check_write_permissions(output_folder)
    Utils.check_external_tools(*external_tools)
  end
end