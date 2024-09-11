#!/bin/bash

# Asegurar el uso de UTF-8
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

set -e  # Detiene la ejecución en caso de error
set -u  # Trata las variables no definidas como un error

# Colores para la salida
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para imprimir mensajes de error
error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

# Función para imprimir mensajes de información
info() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

# Función para imprimir mensajes de advertencia
warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

check_dependencies() {
    info "Verificando dependencias..."
    if ! command -v pdfid &> /dev/null; then
        error "pdfid no está instalado. Por favor, instálalo primero."
        exit 1
    fi
    info "Todas las dependencias están instaladas."
}

analyze_pdf_health() {
    local pdf_file="$1"
    local output_folder="$2"
    local base_name=$(basename "$pdf_file")

    if [ ! -f "$pdf_file" ]; then
        error "El archivo $pdf_file no existe o no es accesible."
        return 1
    fi

    info "Analizando: $base_name"
    local output
    if ! output=$(pdfid -n "$pdf_file" 2>&1); then
        error "Error al analizar $base_name: $output"
        return 1
    fi

    local status="safe"
    if echo "$output" | grep -q -E "/JS|/JavaScript|/AA|/OpenAction|/JBIG2Decode|/RichMedia|/Launch|/EmbeddedFile|/XFA|/ObjStm"; then
        status="suspicious"
    elif echo "$output" | grep -q -E "/AcroForm|/Outlines|/Annots"; then
        status="attention"
    fi

    local dest_folder="$output_folder/$status"
    if [ ! -d "$dest_folder" ]; then
        mkdir -p "$dest_folder"
    fi

    if [ -f "$dest_folder/$base_name" ]; then
        warn "El archivo $base_name ya existe en $dest_folder. Omitiendo..."
        return 0
    fi

    if ! mv "$pdf_file" "$dest_folder/"; then
        error "No se pudo mover $base_name a $dest_folder"
        return 1
    fi

    case "$status" in
        "suspicious")
            echo "ADVERTENCIA: $base_name puede contener elementos sospechosos."
            ;;
        "attention")
            echo "ATENCIÓN: $base_name contiene elementos que requieren revisión adicional."
            ;;
        "safe")
            echo "OK: $base_name parece estar sano."
            ;;
    esac
    info "Movido a: $dest_folder/$base_name"
}

analyze_and_categorize_pdfs() {
    if [ $# -eq 0 ]; then
        error "Uso: $0 <carpeta_entrada> [carpeta_salida]"
        exit 1
    fi
    
    local input_folder="$1"
    local output_folder="${2:-resultados_pdf}"
    local output_file="$output_folder/analisis_resultados.txt"
    
    if [ ! -d "$input_folder" ]; then
        error "La carpeta de entrada '$input_folder' no existe."
        exit 1
    fi
    
    check_dependencies
    
    info "Creando carpetas de salida..."
    mkdir -p "$output_folder"/{safe,suspicious,attention}
    
    info "Iniciando análisis de PDFs en $input_folder"
    echo "Resultados del análisis de PDFs" > "$output_file"
    echo "================================" >> "$output_file"
    
    local num_cores=$(nproc)
    info "Utilizando $num_cores núcleos para el procesamiento paralelo"
    # Crear un directorio temporal y un FIFO
    local temp_dir=$(mktemp -d)
    local fifo="$temp_dir/fifo"
    mkfifo "$fifo"

    # Iniciar procesos en background
    for ((i=1; i<=num_cores; i++)); do
        while read -r pdf_file; do
            analyze_pdf_health "$pdf_file" "$output_folder" | tee -a "$output_file"
        done < "$fifo" &
    done

    # Procesar archivos
    find "$input_folder" -type f -name "*.pdf" > "$fifo"

    # Cerrar explícitamente el FIFO
    exec {fifo_fd}>"$fifo"
    exec {fifo_fd}>&-

    # Esperar a que todos los procesos terminen
    wait

    # Limpiar
    rm -rf "$temp_dir"
    
    echo "-----------------------------------------" >> "$output_file"
    info "Análisis y categorización completados."
    info "PDFs seguros movidos a: $output_folder/safe"
    info "PDFs que requieren atención movidos a: $output_folder/attention"
    info "PDFs sospechosos movidos a: $output_folder/suspicious"
    info "Resultados detallados guardados en: $output_file"
}

# Manejo de señales para limpieza
trap 'echo -e "\n${RED}Script interrumpido por el usuario.${NC}"; exit 1' INT TERM

# Ejecutar la función principal
analyze_and_categorize_pdfs "$@"
