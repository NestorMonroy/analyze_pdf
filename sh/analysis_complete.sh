#!/bin/bash

set -e  # Detiene la ejecución en caso de error

# Configuración
directorio_salida="resultados_analisis_completo"
archivo_log="$directorio_salida/proceso_analisis.log"
archivo_analisis="$directorio_salida/analisis_completo_pdfs.txt"
archivo_estado="$directorio_salida/estado_analisis.txt"
num_cores=$(nproc --all)

# Asegurar que se use UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Crear directorios necesarios
mkdir -p "$directorio_salida"
temp_dir=$(mktemp -d)
fifo="$temp_dir/pdf_fifo"
mkfifo "$fifo"

# Función para registrar mensajes
log_message() {
    local nivel="$1"
    local mensaje="$2"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [$nivel] $mensaje" | tee -a "$archivo_log"
}

# Verificar herramientas necesarias
check_tools() {
    local tools=("pdfid" "pdfinfo" "exiftool" "strings" "file" "qpdf")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_message "ERROR" "$tool no está instalado. Por favor, instálalo primero."
            exit 1
        fi
    done
    log_message "INFO" "Todas las herramientas necesarias están instaladas."
}

# Función para analizar un PDF
analyze_pdf() {
    local pdf_file="$1"
    local base_name=$(basename "$pdf_file")
    local output_file="$directorio_salida/${base_name}.analysis"
    
    # Verificar si el análisis ya se ha realizado
    if [ -f "$output_file" ] && [ "$output_file" -nt "$pdf_file" ]; then
        log_message "INFO" "Análisis ya realizado para $pdf_file. Omitiendo."
        return 0
    fi
    
    {
        echo "========== Analizando: $pdf_file =========="
        echo "Fecha de análisis: $(date)"
        echo

        echo "--- Análisis básico con pdfid ---"
        if ! pdfid "$pdf_file" 2>&1; then
            log_message "WARN" "pdfid falló para $pdf_file"
        fi
        echo

        echo "--- Información general del PDF con pdfinfo ---"
        if ! pdfinfo "$pdf_file" 2>&1; then
            log_message "WARN" "pdfinfo falló para $pdf_file"
        fi
        echo

        echo "--- Metadatos con exiftool ---"
        if ! exiftool "$pdf_file" 2>&1; then
            log_message "WARN" "exiftool falló para $pdf_file"
        fi
        echo

        echo "--- Búsqueda de cadenas sospechosas ---"
        if ! strings "$pdf_file" | grep -iE "javascript|js|jscript|eval|payload|exploit|vulnerability|CVE|XSS|injection" 2>&1; then
            echo "No se encontraron cadenas sospechosas."
        fi
        echo

        echo "--- Tipo de archivo detectado ---"
        if ! file -i "$pdf_file" 2>&1; then
            log_message "WARN" "file falló para $pdf_file"
        fi
        echo

        echo "--- Análisis de estructura con qpdf ---"
        if ! qpdf --check "$pdf_file" 2>&1; then
            log_message "WARN" "qpdf falló para $pdf_file"
        fi
        echo

        echo "--- Búsqueda de URLs embebidas ---"
        if ! strings "$pdf_file" | grep -Eo '(http|https)://[^"< ]+' 2>&1; then
            echo "No se encontraron URLs embebidas."
        fi
        echo

        echo "-----------------------------------------"
    } > "$output_file"
    
    log_message "INFO" "Análisis completo completado para $pdf_file"
    echo "$pdf_file:completado" >> "$archivo_estado"
}

# Función de procesamiento para cada subshell
process_pdfs() {
    while read -r pdf_file; do
        if [ -f "$pdf_file" ]; then
            if analyze_pdf "$pdf_file"; then
                log_message "INFO" "Análisis exitoso: $pdf_file"
            else
                log_message "ERROR" "Fallo en el análisis: $pdf_file"
            fi
        else
            log_message "ERROR" "Archivo no encontrado: $pdf_file"
        fi
    done
}

# Función principal
main() {
    log_message "INFO" "Inicio del proceso de análisis completo de PDFs"
    
    check_tools
    
    # Iniciar el archivo de estado
    > "$archivo_estado"
    
    # Iniciar procesos en background
    for ((i=0; i<num_cores; i++)); do
        process_pdfs < "$fifo" &
    done
    
    # Escribir nombres de archivos PDF en el FIFO
    find "$@" -type f -name "*.pdf" -print0 | xargs -0 -I {} echo {} > "$fifo"
    
    # Esperar a que todos los procesos terminen
    wait
    
    # Combinar todos los análisis en un solo archivo
    cat "$directorio_salida"/*.analysis > "$archivo_analisis"
    
    # Limpieza
    rm -rf "$temp_dir"
    rm "$directorio_salida"/*.analysis
    
    log_message "INFO" "Proceso de análisis completo finalizado."
    log_message "INFO" "Los resultados del análisis completo se han guardado en $archivo_analisis (UTF-8)"
    log_message "INFO" "El estado del análisis se ha guardado en $archivo_estado"
}

# Ejecutar la función principal con manejo de errores
if ! main "$@"; then
    log_message "ERROR" "El script falló. Revisa el log para más detalles."
    exit 1
fi