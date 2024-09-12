#!/bin/bash

# Configuración de directorios
BACKUP_DIR="copias_seguridad"
CLEAN_DIR="limpios_exif"
EXIFTOOL_VERSION="12.96"
EXIFTOOL_URL="https://exiftool.org/Image-ExifTool-${EXIFTOOL_VERSION}.tar.gz"

# Función para imprimir mensajes con formato
print_message() {
    echo -e "\n[INFO] $1"
}

# Función para imprimir errores
print_error() {
    echo -e "\n[ERROR] $1" >&2
}

# Función para verificar si un comando fue exitoso
check_success() {
    if [ $? -ne 0 ]; then
        print_error "$1"
        return 1
    fi
    return 0
}

# Función para verificar e instalar exiftool
check_and_install_exiftool() {
    if command -v exiftool &> /dev/null; then
        print_message "exiftool ya está instalado."
        return 0
    fi

    print_message "exiftool no está instalado. Iniciando proceso de instalación..."

    # Crear un directorio temporal para la instalación
    local temp_dir=$(mktemp -d)
    cd "$temp_dir" || return 1

    # Descargar ExifTool
    print_message "Descargando ExifTool..."
    wget "$EXIFTOOL_URL"
    check_success "No se pudo descargar ExifTool." || return 1

    # Descomprimir el archivo
    print_message "Descomprimiendo ExifTool..."
    gzip -dc "Image-ExifTool-${EXIFTOOL_VERSION}.tar.gz" | tar -xf -
    check_success "No se pudo descomprimir ExifTool." || return 1

    # Cambiar al directorio de ExifTool
    cd "Image-ExifTool-${EXIFTOOL_VERSION}" || return 1

    # Instalar ExifTool
    print_message "Instalando ExifTool..."
    perl Makefile.PL
    make test
    sudo make install
    check_success "No se pudo instalar ExifTool." || return 1

    # Actualizar la caché de la biblioteca dinámica
    sudo ldconfig
    check_success "No se pudo actualizar la caché de la biblioteca dinámica." || return 1

    # Limpiar archivos temporales
    cd
    rm -rf "$temp_dir"

    print_message "ExifTool se ha instalado correctamente."
}

# Función para crear directorios necesarios
create_directories() {
    mkdir -p "$BACKUP_DIR/metadatos" "$CLEAN_DIR/metadatos"
    check_success "No se pudieron crear los directorios necesarios." || exit 1
}

# Función para crear copia de seguridad
create_backup() {
    local pdf_path="$1"
    local pdf_filename=$(basename "$pdf_path")
    local backup_path="${BACKUP_DIR}/${pdf_filename%.*}_backup.pdf"
    
    cp "$pdf_path" "$backup_path"
    check_success "No se pudo crear la copia de seguridad para $pdf_path." || return 1
    print_message "Copia de seguridad creada: $backup_path"
}

# Función para guardar metadatos
save_metadata() {
    local pdf_path="$1"
    local output_dir="$2"
    local metadata_type="$3"
    local pdf_filename=$(basename "$pdf_path")
    local metadata_dir="${output_dir}/metadatos"
    local output_path="${metadata_dir}/${pdf_filename%.*}_metadata_${metadata_type}.txt"
    
    
    exiftool "$pdf_path" > "$output_path"
    check_success "No se pudieron guardar los metadatos $metadata_type." || return 1
    print_message "Metadatos $metadata_type guardados en: $output_path"
}

# Función para limpiar metadatos
clean_metadata() {
    local pdf_path="$1"
    local cleaned_pdf="$2"
    
    exiftool -all= \
             -XMP:all= \
             -IPTC:all= \
             -PDF:all= \
             -ThumbnailImage= \
             -trailer:all= \
             -o "$cleaned_pdf" \
             "$pdf_path"
    
    check_success "No se pudieron eliminar los metadatos de $pdf_path" || return 1
    print_message "Metadatos eliminados con éxito. Archivo limpio guardado en: $cleaned_pdf"
}
# Función principal para procesar un archivo PDF
process_pdf() {
    local pdf_path="$1"
    local pdf_filename=$(basename "$pdf_path")

    # Verificar si el archivo es un PDF válido
    if [ ! -f "$pdf_path" ] || [[ "$(file -b --mime-type "$pdf_path")" != "application/pdf" ]]; then
        print_error "El archivo $pdf_path no existe o no es un PDF válido. Saltando..."
        return 1
    fi

    print_message "Procesando archivo: $pdf_path"

    # Crear copia de seguridad
    create_backup "$pdf_path" || return 1

    # Guardar metadatos originales
    local original_metadata="${BACKUP_DIR}/${pdf_filename%.*}_metadata_original.txt"
    save_metadata "$pdf_path" "$BACKUP_DIR" "originales" || return 1

    # Limpiar metadatos
    local cleaned_pdf="${CLEAN_DIR}/${pdf_filename%.*}_limpio.pdf"
    clean_metadata "$pdf_path" "$cleaned_pdf" || return 1

    # Guardar metadatos después de la limpieza
    local cleaned_metadata="${CLEAN_DIR}/${pdf_filename%.*}_metadata_limpio.txt"
    save_metadata "$cleaned_pdf" "$CLEAN_DIR" "limpios" || return 1

    print_message "Proceso completado para $pdf_path"
}

# Función principal
main() {
    # Verificar argumentos
    if [ $# -eq 0 ]; then
        print_error "No se proporcionaron archivos PDF. Uso: $0 archivo1.pdf archivo2.pdf ..."
        exit 1
    fi

    # Verificar si hay archivos PDF válidos para procesar
    pdf_files=()
    for pdf_path in "$@"; do
        if [ -f "$pdf_path" ] && [[ "$(file -b --mime-type "$pdf_path")" == "application/pdf" ]]; then
            pdf_files+=("$pdf_path")
        else
            print_error "El archivo $pdf_path no existe o no es un PDF válido. Saltando..."
        fi
    done

    # Verificar si hay archivos PDF válidos para procesar
    if [ ${#pdf_files[@]} -eq 0 ]; then
        print_error "No se encontraron archivos PDF válidos para procesar."
        exit 1
    fi

    # Verificar e instalar exiftool
    check_and_install_exiftool || exit 1

    # Crear directorios necesarios
    create_directories

    # Procesar cada archivo PDF
    for pdf_path in "${pdf_files[@]}"; do
        process_pdf "$pdf_path"
    done

    print_message "Todos los archivos han sido procesados."
}

# Ejecutar la función principal
main "$@"
