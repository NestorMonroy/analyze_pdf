#!/bin/bash

set -e
set -u

# Variables globales
DIRECTORIO_SALIDA="archivos_salida_1.5"
ARCHIVO_LOG="$DIRECTORIO_SALIDA/proceso_pdf.log"
ARCHIVO_TRANSFORMADOS="$DIRECTORIO_SALIDA/pdfs_transformados.txt"
ARCHIVO_ANALISIS_PRE="$DIRECTORIO_SALIDA/analisis_pre_limpieza.txt"
ARCHIVO_ANALISIS_POST="$DIRECTORIO_SALIDA/analisis_post_limpieza.txt"
ARCHIVO_PROGRESO="$DIRECTORIO_SALIDA/progreso.txt"
NUM_CORES=$(nproc --all)
TIEMPO_LIMITE=900
DIRECTORIO_ESTADO="$DIRECTORIO_SALIDA/estado"
TEMP_DIR=$(mktemp -d)
FIFO="$TEMP_DIR/pdf_fifo"


# Función para logging
log_message() {
    local nivel="${1:-INFO}"
    local mensaje="${2:-No message provided}"
    local archivo="${3:-}"
    local etapa="${4:-}"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] [$nivel]"
   
    if [[ -n "$archivo" ]]; then
        log_entry+=" [Archivo: $archivo]"
    fi
    if [[ -n "$etapa" ]]; then
        log_entry+=" [Etapa: $etapa]"
    fi
   
    log_entry+=" $mensaje"
    echo "$log_entry" | tee -a "$ARCHIVO_LOG"
}


# Función para obtener el estado de un archivo
get_estado() {
    local archivo="$1"
    local archivo_estado="$DIRECTORIO_ESTADO/$(basename "$archivo").estado"
    if [ -f "$archivo_estado" ]; then
        cat "$archivo_estado"
    else
        echo "no_iniciado"
    fi
}

# Función para establecer el estado de un archivo
set_estado() {
    local archivo="$1"
    local estado="$2"
    local checksum="${3:-}"
    local archivo_estado="$DIRECTORIO_ESTADO/$(basename "$archivo").estado"
    
    if [[ -z "$checksum" ]]; then
        echo "$estado" > "$archivo_estado"
    else
        echo "$estado:$checksum" > "$archivo_estado"
    fi
}

# Función para calcular el checksum de un archivo
calculate_checksum() {
    local file="$1"
    md5sum "$file" | awk '{ print $1 }'
}

# Función para verificar la integridad de un archivo
verify_integrity() {
    local file="$1"
    local stage="$2"
    local expected_checksum="$3"
    local current_checksum=$(calculate_checksum "$file")
    
    if [ "$current_checksum" != "$expected_checksum" ]; then
        log_message "ERROR" "Fallo en la verificación de integridad" "$file" "$stage"
        log_message "ERROR" "Checksum esperado: $expected_checksum, Actual: $current_checksum" "$file" "$stage"
        return 1
    else
        log_message "INFO" "Verificación de integridad exitosa" "$file" "$stage"
        return 0
    fi
}


# Función para analizar un PDF
analyze_pdf() {
    local input_file="$1"
    local output_file="$2"
    local paso="$3"
    
    # Verificar que todos los argumentos estén presentes
    if [[ -z "$input_file" || -z "$output_file" || -z "$paso" ]]; then
        log_message "ERROR" "Argumentos insuficientes para analyze_pdf" "$input_file" "analyze_pdf"
        return 1
    fi
    
    if [ "$(get_estado "$input_file")" = "$paso" ]; then
        log_message "INFO" "Análisis ya realizado, omitiendo" "$input_file" "$paso"
        return 0
    fi
    
    log_message "INFO" "Iniciando análisis" "$input_file" "$paso"
    if ! pdfid "$input_file" >> "$output_file" 2>&1; then
        log_message "ERROR" "Fallo en el análisis" "$input_file" "$paso"
        return 1
    fi
    echo "-----------------------------------------" >> "$output_file"
    local checksum=$(calculate_checksum "$input_file")
    set_estado "$input_file" "$paso" "$checksum"
    log_message "INFO" "Análisis completado" "$input_file" "$paso"
}



# Función para transformar un PDF a versión 1.5
transform_to_1_5() {
    local input_file="$1"
    local output_file="$2"
    
    local estado_actual=$(get_estado "$input_file")
    local estado=$(echo $estado_actual | cut -d':' -f1)
    local checksum=$(echo $estado_actual | cut -d':' -f2)
    
    if [ "$estado" = "transformado" ] && verify_integrity "$input_file" "transformacion_1.5" "$checksum"; then
        log_message "INFO" "PDF ya transformado a 1.5 y verificado, omitiendo" "$input_file" "transformacion_1.5"
        cp "$input_file" "$output_file"
        return 0
    fi
    
    log_message "INFO" "Iniciando transformación a PDF 1.5" "$input_file" "transformacion_1.5"
    local initial_checksum=$(calculate_checksum "$input_file")
    
    if ! timeout 900 gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.5 -dPDFSETTINGS=/default \
       -dNOPAUSE -dQUIET -dBATCH \
       -sOutputFile="$output_file" \
       "$input_file"; then
        log_message "ERROR" "Timeout o fallo en la transformación a PDF 1.5" "$input_file" "transformacion_1.5"
        return 1
    fi
    
    local final_checksum=$(calculate_checksum "$output_file")
    set_estado "$input_file" "transformado" "$final_checksum"
    log_message "INFO" "Transformación a PDF 1.5 completada" "$input_file" "transformacion_1.5"
}

# Función para reparar un PDF
repair_pdf() {
    local input_file="$1"
    local output_file="$2"
    
    local estado_actual=$(get_estado "$input_file")
    local estado=$(echo $estado_actual | cut -d':' -f1)
    local checksum=$(echo $estado_actual | cut -d':' -f2)
    
    if [ "$estado" = "reparado" ] && verify_integrity "$input_file" "reparacion" "$checksum"; then
        log_message "INFO" "PDF ya reparado y verificado, omitiendo" "$input_file" "reparacion"
        cp "$input_file" "$output_file"
        return 0
    fi
    
    log_message "INFO" "Iniciando reparación" "$input_file" "reparacion"
    local initial_checksum=$(calculate_checksum "$input_file")
    
    if ! qpdf --replace-input "$input_file" 2>/dev/null; then
        log_message "WARN" "qpdf no pudo reparar, intentando con pdftk" "$input_file" "reparacion"
        if ! pdftk "$input_file" output "$output_file" 2>/dev/null; then
            log_message "ERROR" "Falló la reparación" "$input_file" "reparacion"
            return 1
        fi
    else
        cp "$input_file" "$output_file"
    fi
    
    local final_checksum=$(calculate_checksum "$output_file")
    set_estado "$input_file" "reparado" "$final_checksum"
    log_message "INFO" "Reparación completada" "$input_file" "reparacion"
}

# Función para aplicar métodos de limpieza
apply_cleaning_methods() {
    local input_file="$1"
    local output_file="$2"
    local temp_dir="$3"
    
    local cleaning_steps=("optimizar" "aplanar" "eliminar_js" "reimprimir")
    local current_file="$input_file"
    
    for step in "${cleaning_steps[@]}"; do
        log_message "INFO" "Aplicando método de limpieza: $step" "$input_file" "limpieza_$step"
        
        local temp_output="$temp_dir/temp_$step.pdf"
        case $step in
            "optimizar")
                qpdf "$current_file" --object-streams=generate --compress-streams=y --decode-level=specialized "$temp_output"
                ;;
            "aplanar")
                qpdf "$current_file" --remove-page-labels --flatten-annotations=all --generate-appearances "$temp_output"
                ;;
            "eliminar_js")
                qpdf "$current_file" --remove-javascript --remove-reset-form --remove-all-actions "$temp_output"
                ;;
            "reimprimir")
                if ! gs -sDEVICE=pdfwrite -dPDFSETTINGS=/default -dNOPAUSE -dQUIET -dBATCH \
                   -dCompatibilityLevel=1.5 \
                   -sOutputFile="$temp_output" \
                   "$current_file"; then
                    log_message "WARN" "Fallo en el método de limpieza: reimprimir. Omitiendo este paso." "$input_file" "limpieza_reimprimir"
                    cp "$current_file" "$temp_output"
                fi
                ;;
        esac
        
        if [ ! -f "$temp_output" ] || [ ! -s "$temp_output" ]; then
            log_message "ERROR" "Archivo de salida no creado o vacío en el paso $step" "$input_file" "limpieza_$step"
            return 1
        fi
        
        current_file="$temp_output"
    done
    
    cp "$current_file" "$output_file"
    log_message "INFO" "Todos los métodos de limpieza aplicados" "$input_file" "limpieza_completa"
}

verify_pdf_integrity() {
    local input_file="$1"
    local output_file="$2"
    
    local input_pages=$(pdfinfo "$input_file" | grep "Pages:" | awk '{print $2}')
    local output_pages=$(pdfinfo "$output_file" | grep "Pages:" | awk '{print $2}')
    
    if [ "$input_pages" != "$output_pages" ]; then
        log_message "ERROR" "Discrepancia en el número de páginas. Original: $input_pages, Limpio: $output_pages" "$input_file" "verificacion"
        return 1
    fi
    
    # Añadir más verificaciones según sea necesario
    
    log_message "INFO" "Verificación de integridad exitosa" "$input_file" "verificacion"
    return 0
}


# Función principal para limpiar un PDF
clean_pdf() {
    local input_file="$1"
    local base_name=$(basename "$input_file" .pdf)
    local temp_dir="${DIRECTORIO_SALIDA}/${base_name}_temp"
    mkdir -p "$temp_dir"
    local output_file="$DIRECTORIO_SALIDA/${base_name}_limpio.pdf"
    
    log_message "INFO" "Iniciando proceso de limpieza" "$input_file" "inicio"
    
    local estado_actual=$(get_estado "$input_file")
    local estado=$(echo $estado_actual | cut -d':' -f1)
    local checksum=$(echo $estado_actual | cut -d':' -f2)
    
    case $estado in
        "no_iniciado")
            analyze_pdf "$input_file" "$ARCHIVO_ANALISIS_PRE" "analisis_pre"
            local initial_checksum=$(calculate_checksum "$input_file")
            set_estado "$input_file" "analisis_pre" "$initial_checksum"
            ;&  # Fall through
        "analisis_pre")
            local repaired_file="${temp_dir}/${base_name}_repaired.pdf"
            repair_pdf "$input_file" "$repaired_file"
            ;&
        "reparado")
            local version=$(pdfinfo "$repaired_file" | grep "PDF version" | awk '{print $3}')
            log_message "INFO" "Versión del PDF: $version" "$input_file" "version_check"
            if [ "$version" != "1.5" ]; then
                local transformed_file="${temp_dir}/${base_name}_transformed.pdf"
                transform_to_1_5 "$repaired_file" "$transformed_file"
            else
                local transformed_file="$repaired_file"
                set_estado "$input_file" "transformado" $(calculate_checksum "$transformed_file")
            fi
            ;&
        "transformado"|"optimizar"|"aplanar"|"eliminar_js")
            apply_cleaning_methods "$transformed_file" "$output_file" "$temp_dir"
            ;&
        "reimprimir")
            analyze_pdf "$output_file" "$ARCHIVO_ANALISIS_POST" "analisis_post"
            set_estado "$input_file" "completado" $(calculate_checksum "$output_file")
            ;;
        "completado")
            if verify_integrity "$output_file" "final" "$checksum"; then
                log_message "INFO" "Limpieza ya completada y verificada anteriormente" "$input_file" "fin"
                return 0
            else
                log_message "WARN" "Archivo final no íntegro, reiniciando proceso" "$input_file" "reinicio"
                set_estado "$input_file" "no_iniciado" ""
                clean_pdf "$input_file"
            fi
            ;;
        *)
            log_message "ERROR" "Estado desconocido: $estado" "$input_file" "error"
            return 1
            ;;
    esac
    
    # Usar esta función después de apply_cleaning_methods en clean_pdf
    if ! verify_pdf_integrity "$input_file" "$output_file"; then
        log_message "ERROR" "Fallo en la verificación de integridad. Revirtiendo a la versión original." "$input_file" "verificacion"
        cp "$input_file" "$output_file"
        return 1
    fi
    if [ ! -f "$output_file" ] || [ ! -s "$output_file" ]; then
        log_message "ERROR" "Archivo de salida no creado o vacío" "$input_file" "fin"
        return 1
    fi
    
    log_message "INFO" "Limpieza completada con éxito" "$input_file" "fin"
    rm -rf "$temp_dir"
}

verificar_permisos() {
    local directorios=("$DIRECTORIO_SALIDA" "$DIRECTORIO_ESTADO")
    for dir in "${directorios[@]}"; do
        if [ ! -d "$dir" ]; then
            if ! mkdir -p "$dir" 2>/dev/null; then
                echo "ERROR: No se pudo crear el directorio $dir" >&2
                return 1
            fi
        fi
        if [ ! -w "$dir" ]; then
            echo "ERROR: No tienes permisos de escritura en $dir" >&2
            return 1
        fi
    done
    
    # Crear archivos de log y análisis
    touch "$ARCHIVO_LOG" "$ARCHIVO_TRANSFORMADOS" "$ARCHIVO_ANALISIS_PRE" "$ARCHIVO_ANALISIS_POST" "$ARCHIVO_PROGRESO"
    
    return 0
}

# Función de procesamiento para cada subshell
process_pdfs() {
    while read -r pdf_file; do
        if [ -f "$pdf_file" ]; then
            local output_file="$DIRECTORIO_SALIDA/$(basename "$pdf_file" .pdf)_limpio.pdf"
            if [ -f "$output_file" ]; then
                log_message "INFO" "Archivo ya procesado. Omitiendo." "$pdf_file" "verificacion"
            else
                clean_pdf "$pdf_file" || log_message "ERROR" "Fallo en la limpieza" "$pdf_file" "proceso_completo"
            fi
        else
            log_message "WARN" "Archivo no encontrado" "$pdf_file" "verificacion"
        fi
    done
}

cleanup() {
    log_message "WARN" "Interrupción detectada. Limpiando y saliendo..."
    
    # Matar todos los procesos en ejecución
    for pid in "${!pids_en_ejecucion[@]}"; do
        if kill -0 $pid 2>/dev/null; then
            kill $pid
            log_message "INFO" "Proceso $pid terminado."
        fi
    done
    
    # Cerrar y eliminar el FIFO
    exec {fifo_fd}>"$FIFO"
    exec {fifo_fd}>&-
    rm -f "$FIFO"
    
    # Eliminar directorio temporal
    rm -rf "$TEMP_DIR"
    
    log_message "INFO" "Limpieza completada. Saliendo."
    exit 1
}

## Declarar array asociativo para PIDs
declare -A pids_en_ejecucion

# Verificar permisos y crear directorios/archivos necesarios
if ! verificar_permisos; then
    echo "ERROR: No se tienen los permisos necesarios para ejecutar el script." >&2
    exit 1
fi

# Crear FIFO
mkfifo "$FIFO"

# Configurar trap para manejo de interrupciones
trap cleanup SIGINT SIGTERM

# Función principal
main() {
    log_message "INFO" "Iniciando proceso de limpieza de PDFs"
    
    # Iniciar contenido de archivos de log y análisis
    echo "Inicio del proceso de análisis y limpieza de PDFs: $(date)" > "$ARCHIVO_LOG"
    echo "PDFs transformados a versión 1.5:" > "$ARCHIVO_TRANSFORMADOS"
    echo "Análisis de PDFs antes de la limpieza:" > "$ARCHIVO_ANALISIS_PRE"
    echo "Análisis de PDFs después de la limpieza:" > "$ARCHIVO_ANALISIS_POST"
    
    # Iniciar procesos en background
    for ((i=0; i<NUM_CORES; i++)); do
        process_pdfs < "$FIFO" &
        pids_en_ejecucion[$!]=1
    done
    
    # Escribir nombres de archivos PDF en el FIFO
    find "$@" -type f -name "*.pdf" > "$FIFO"
    
    # Cerrar explícitamente el FIFO
    exec {fifo_fd}>"$FIFO"
    exec {fifo_fd}>&-
    
    # Esperar a que todos los procesos terminen
    wait
    
    # Limpieza final
    rm -rf "$TEMP_DIR"
    
    log_message "INFO" "Proceso de limpieza de PDFs completado"
    log_message "INFO" "Fin del proceso: $(date)"
    log_message "INFO" "Los PDFs transformados se han listado en $ARCHIVO_TRANSFORMADOS"
    log_message "INFO" "Análisis pre-limpieza en $ARCHIVO_ANALISIS_PRE"
    log_message "INFO" "Análisis post-limpieza en $ARCHIVO_ANALISIS_POST"
}

# Ejecutar la función principal
main "$@"