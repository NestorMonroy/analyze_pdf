require 'fileutils'
require 'digest'
require 'open3'

module Utils
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
end