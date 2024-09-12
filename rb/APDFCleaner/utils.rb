require 'fileutils'
require 'digest'
require 'open3'
require 'logger'
require 'colorize'

module Utils
  class AdvancedLogger
    SEVERITY_COLORS = {
      DEBUG: :light_blue,
      INFO: :green,
      WARN: :yellow,
      ERROR: :red,
      FATAL: :red
    }

    def initialize(log_file = nil, verbose = false)
      @loggers = []
      @verbose = verbose

      # Logger para la consola
      @loggers << Logger.new(STDOUT)

      # Logger para el archivo si se proporciona
      if log_file
        FileUtils.mkdir_p(File.dirname(log_file))
        @loggers << Logger.new(log_file)
      end

      @loggers.each do |logger|
        logger.formatter = proc do |severity, datetime, progname, msg|
          color = SEVERITY_COLORS[severity.to_sym] || :default
          formatted_msg = "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
          severity == "DEBUG" ? formatted_msg : formatted_msg.colorize(color)
        end
      end
    end

    def debug(message)
      log('DEBUG', message) if @verbose
    end

    def info(message)
      log('INFO', message)
    end

    def warn(message)
      log('WARN', message)
    end

    def error(message)
      log('ERROR', message)
    end

    def fatal(message)
      log('FATAL', message)
    end

    private

    def log(severity, message)
      @loggers.each { |logger| logger.send(severity.downcase, message) }
    end
  end

  def self.create_logger(log_file = nil, verbose = false)
    AdvancedLogger.new(log_file, verbose)
  end

  # Crea una carpeta de salida si no existe
  def self.create_output_folder(base_dir, folder_name)
    output_folder = File.join(base_dir, folder_name)
    FileUtils.mkdir_p(output_folder) unless Dir.exist?(output_folder)
    output_folder
  end

  # Verifica si un archivo es un PDF válido
  def self.valid_pdf?(file)
    File.open(file, 'rb') { |f| f.read(4) } == '%PDF'
  end

  # Calcula el hash MD5 de un archivo
  def self.file_hash(file)
    Digest::MD5.file(file).hexdigest
  end

  # Ejecuta un comando externo y devuelve el resultado
  def self.execute_command(cmd)
    Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
      exit_status = wait_thr.value
      if exit_status.success?
        [true, stdout.read]
      else
        [false, stderr.read]
      end
    end
  end

  # Verifica si un archivo existe
  def self.file_exists?(file)
    File.exist?(file)
  end

  # Copia un archivo
  def self.copy_file(source, destination)
    FileUtils.cp(source, destination)
  end

  # Elimina un archivo si existe
  def self.delete_file(file)
    File.delete(file) if file_exists?(file)
  end

  # Genera un nombre de archivo temporal
  def self.temp_filename(prefix = 'temp', suffix = '.pdf')
    "#{prefix}_#{Time.now.to_i}#{suffix}"
  end

  def self.check_write_permissions(directory)
    unless File.writable?(directory)
      raise "No tienes permisos de escritura en el directorio: #{directory}"
    end
  end

  def self.check_external_tools(*tools)
    missing_tools = tools.reject { |tool| system("which #{tool} > /dev/null 2>&1") }
    unless missing_tools.empty?
      raise "Las siguientes herramientas no están instaladas o no son ejecutables: #{missing_tools.join(', ')}"
    end
  end

  def self.check_read_permissions(file)
    unless File.readable?(file)
      raise "No tienes permisos de lectura para el archivo: #{file}"
    end
  end

  def self.check_permissions(output_folder, external_tools)
    check_write_permissions(output_folder)
    check_external_tools(*external_tools)
  end

  def self.validate_pdf_file(file)
    unless File.file?(file)
      raise "#{file} no es un archivo."
    end
    check_read_permissions(file)
    unless File.extname(file).downcase == '.pdf'
      raise "#{file} no es un archivo PDF."
    end
    unless valid_pdf?(file)
      raise "#{file} no es un PDF válido."
    end
  end

  def self.sanitize_filename(filename)
    filename.gsub(/[^0-9A-Za-z.]/, '_')
  end

  def self.rename_pdf_file(file, logger = nil)
    dir = File.dirname(file)
    filename = File.basename(file)
    newname = filename.dup

    patterns = [
      '_limpio',
      '_unlockedlimpio',
      'limpio',
      '__unlocked',
      'Lulu.com'
    ]

    patterns.each do |pattern|
      newname.gsub!(/#{Regexp.escape(pattern)}(\.pdf)?$/, '.pdf')
      newname.gsub!(pattern, '')
    end

    if filename != newname
      newpath = File.join(dir, sanitize_filename(newname))
      begin
        FileUtils.mv(file, newpath)
        message = "Renombrado: #{file} -> #{newpath}"
        logger ? logger.info(message) : puts(message)
        return newpath
      rescue => e
        error_message = "Error al renombrar #{file}: #{e.message}"
        logger ? logger.error(error_message) : puts(error_message)
      end
    end

    file  # Devuelve el nombre original si no se renombró
  end

end
