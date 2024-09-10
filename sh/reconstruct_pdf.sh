#!/bin/bash

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

# Verificar e instalar dependencias
check_and_install_dependency() {
    if ! command -v $1 &> /dev/null; then
        print_message "$1 no está instalado. Intentando instalar..."
        sudo apt update && sudo apt install -y $2
        check_success "No se pudo instalar $1. Por favor, instálelo manualmente." || exit 1
    else
        print_message "$1 ya está instalado."
    fi
}

check_and_install_dependency "pdftoppm" "poppler-utils"
check_and_install_dependency "img2pdf" "img2pdf"

# Verificar si se proporcionaron argumentos
if [ $# -eq 0 ]; then
    print_error "No se proporcionaron archivos PDF. Uso: $0 archivo1.pdf archivo2.pdf ..."
    exit 1
fi

# Función para mostrar una barra de progreso simple
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((width * current / total))
    printf "\rProgreso: [%-${width}s] %d%%" "$(printf '%0.s#' $(seq 1 $completed))" "$percentage"
}

# Función para procesar un solo PDF
process_pdf() {
    local pdf_path=$1
    local resolution=${2:-300}  # Resolución por defecto: 300 DPI
    
    print_message "Procesando archivo: $pdf_path"

    # Crear un directorio temporal para las imágenes
    local temp_dir=$(mktemp -d)
    local base_name=$(basename "$pdf_path" .pdf)

    # Obtener el número total de páginas
    local total_pages=$(pdfinfo "$pdf_path" | grep Pages | awk '{print $2}')

    # Convertir PDF a imágenes, una por página
    print_message "Convirtiendo $pdf_path a imágenes de alta resolución..."
    for ((page=1; page<=total_pages; page++)); do
        if ! pdftoppm -png -r "$resolution" -f $page -l $page "$pdf_path" "$temp_dir/${base_name}_page_$page"; then
            print_error "Error al convertir la página $page de $pdf_path"
            rm -rf "$temp_dir"
            return 1
        fi
        show_progress $page $total_pages
    done
    echo

    # Convertir imágenes de vuelta a PDF
    local output_pdf="${pdf_path%.*}_reconstructed.pdf"
    print_message "Convirtiendo imágenes de vuelta a PDF: $output_pdf"
    if ! img2pdf "$temp_dir"/*.png -o "$output_pdf" --auto-orient --fit shrink; then
        print_error "Error al convertir las imágenes de vuelta a PDF."
        rm -rf "$temp_dir"
        return 1
    fi

    # Limpiar archivos temporales
    rm -rf "$temp_dir"
    print_message "Proceso completado para $pdf_path. Nuevo PDF creado: $output_pdf"
    return 0
}

# Verificar argumentos
if [ $# -eq 0 ]; then
    print_error "No se proporcionaron archivos PDF. Uso: $0 [-r resolución] archivo1.pdf [archivo2.pdf ...]"
    exit 1
fi

# Procesar opciones
resolution=150
while getopts ":r:" opt; do
    case $opt in
        r) resolution="$OPTARG"
        ;;
        \?) print_error "Opción inválida: -$OPTARG" >&2
        exit 1
        ;;
    esac
done
shift $((OPTIND-1))

# Procesar cada archivo PDF
for pdf_path in "$@"; do
    if [ -f "$pdf_path" ] && [[ "$(file -b --mime-type "$pdf_path")" == "application/pdf" ]]; then
        process_pdf "$pdf_path" "$resolution"
    else
        print_error "El archivo $pdf_path no existe o no es un PDF válido. Saltando..."
    fi
done

print_message "Todos los archivos han sido procesados."