#!/bin/bash
set -e

# Configuración global
export LC_ALL=C.UTF-8
export LANG=C.UTF-8
directorio_salida="archivos_salida"
archivo_log="$directorio_salida/proceso_pdf.log"
tiempo_limite=600
interrumpido=0
declare -A summary
declare -i archivos_procesados=0
declare -i archivos_exitosos=0
declare -i archivos_fallidos=0
verbose=0


# Función para crear el directorio de salida y el archivo de log
initialize_output_directory() {
    if [ ! -d "$directorio_salida" ]; then
        mkdir -p "$directorio_salida"
        echo "Directorio de salida creado: $directorio_salida"
    fi

    if [ ! -f "$archivo_log" ]; then
        touch "$archivo_log"
        echo "Archivo de log creado: $archivo_log"
    fi
}

# Verifica si un comando está instalado
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_message "ERROR" "$1 no está instalado. Por favor, instálalo primero."
        exit 1
    fi
}

# Sanitiza nombres de archivo
sanitize_filename() {
    local filename="$1"
    echo "${filename//[^a-zA-Z0-9. ]/_}"
}

# Maneja interrupciones del script
manejar_interrupcion() {
    echo "Interrupción detectada. Limpiando y saliendo..."
    interrumpido=1
    kill -- -$$
}

# Espera con timeout
wait_with_timeout() {
    local pid=$1
    local timeout=$2
    local count=0
    while [ $count -lt $timeout ]; do
        if ! kill -0 $pid 2>/dev/null; then
            return 0
        fi
        sleep 1
        ((count++))
    done
    return 1
}

# Registra mensajes en el log
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    case "$level" in
        "DEBUG")
            [ "$verbose" -ge 2 ] && echo "[$timestamp] [$level] $message"
            ;;
        "INFO")
            [ "$verbose" -ge 1 ] && echo "[$timestamp] [$level] $message"
            ;;
        *)
            echo "[$timestamp] [$level] $message"
            ;;
    esac
    if [ -f "$archivo_log" ]; then
        echo "[$timestamp] [$level] $message" >> "$archivo_log"
    fi
}

check_pdf_integrity() {
    local pdf_file="$1"
    if qpdf --check "$pdf_file" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

update_progress() {
    local current="$1"
    local total="$2"
    local filename="$3"

    # Verificar si current y total son números
    if [[ "$current" =~ ^[0-9]+$ ]] && [[ "$total" =~ ^[0-9]+$ ]]; then
        if [ "$total" -gt 0 ]; then
            local percentage=$((current * 100 / total))
            log_message "INFO" "Progreso: $current/$total ($percentage%) - Procesando: $filename"
        else
            log_message "INFO" "Procesando: $filename (Total de archivos es 0)"
        fi
    else
        log_message "WARN" "Valores no válidos para current ($current) o total ($total). Procesando: $filename"
    fi
}

# Función principal para limpiar PDFs
clean_pdf() {
    local input_file="$1"
    local current_file="$2"
    local total_files="$3"
    local base_name=$(basename "$input_file")
    local sanitized_base_name=$(sanitize_filename "${base_name%.*}")
    local temp_dir="$directorio_salida/temp_${sanitized_base_name// /_}"
    local temp_file1="${temp_dir}/${sanitized_base_name// /_}_temp1.pdf"
    local temp_file2="${temp_dir}/${sanitized_base_name// /_}_temp2.pdf"
    local output_file="$directorio_salida/${sanitized_base_name// /_}_limpio.pdf"
    local gs_log="${temp_dir}/${sanitized_base_name// /_}_gs_log.txt"
    local pdftk_log="${temp_dir}/${sanitized_base_name// /_}_pdftk_error.log"
    local qpdf_log="${temp_dir}/${sanitized_base_name// /_}_qpdf_log.txt"

    mkdir -p "$temp_dir"

    update_progress "$current_file" "$total_files" "$base_name"

    log_message "INFO" "Iniciando limpieza de \"$input_file\""

    if [ -f "$output_file" ]; then
        log_message "INFO" "El archivo \"$output_file\" ya existe. Omitiendo procesamiento."
        summary["Ya existentes"]=$((${summary["Ya existentes"]} + 1))
        return 0
    fi

    log_message "DEBUG" "Intentando crear archivo de salida: $output_file"

    if ! process_with_timeout "$input_file" "$temp_file1" "$temp_file2" "$output_file" "$temp_dir" "$gs_log" "$pdftk_log" "$qpdf_log"; then
        log_message "WARN" "El procesamiento de \"$input_file\" falló o excedió el límite de tiempo."
        summary["Tiempo excedido o fallido"]=$((${summary["Tiempo excedido o fallido"]} + 1))
        return 1
    fi

    if [ -f "$output_file" ] && [ -s "$output_file" ]; then
        if check_pdf_integrity "$output_file"; then
            log_message "INFO" "PDF limpio y verificado: \"$output_file\""
            {
                flock -x 200
                ((archivos_procesados++))
                ((archivos_exitosos++))
                echo "Archivo procesado y verificado: $input_file (Total: $archivos_procesados, Exitosos: $archivos_exitosos)" >> "$archivo_log"
            } 200>$temp_dir/count.lock
            
            rm -rf "$temp_dir"
            return 0
        else
            log_message "ERROR" "El archivo de salida \"$output_file\" no es un PDF válido"
            {
                flock -x 200
                ((archivos_procesados++))
                ((archivos_fallidos++))
                echo "Archivo procesado pero inválido: $input_file (Total: $archivos_procesados, Fallidos: $archivos_fallidos)" >> "$archivo_log"
            } 200>$temp_dir/count.lock
            rm "$output_file"  # Eliminar el archivo inválido
            return 1
        fi
    else
        log_message "ERROR" "No se pudo crear el archivo de salida \"$output_file\""
        {
            flock -x 200
            ((archivos_procesados++))
            ((archivos_fallidos++))
            echo "Archivo fallido: $input_file (Total: $archivos_procesados, Fallidos: $archivos_fallidos)" >> "$archivo_log"
        } 200>$temp_dir/count.lock
        return 1
    fi
}

# Procesa PDF con timeout
process_with_timeout() {
    local input_file="$1"
    local temp_file1="$2"
    local temp_file2="$3"
    local output_file="$4"
    local temp_dir="$5"
    local gs_log="$6"
    local pdftk_log="$7"
    local qpdf_log="$8"

    local timeout_occurred=0
    local pid

    (
        # Proceso de limpieza
        set +e

        process_qpdf "$input_file" "$temp_file1" "$qpdf_log" "$temp_dir"
        process_pdftk "$temp_file1" "$temp_file2" "$pdftk_log" "$temp_dir"
        remove_javascript "$temp_file2" "$qpdf_log"
        process_ghostscript "$temp_file2" "$output_file" "$gs_log"

        exit 0
    ) &

    local pid=$!
    local start_time=$(date +%s)

    while kill -0 $pid 2>/dev/null; do
        if [ $(($(date +%s) - start_time)) -gt $tiempo_limite ]; then
            kill $pid
            wait $pid 2>/dev/null
            log_message "WARN" "Tiempo de procesamiento excedido para \"$input_file\""
            return 1
        fi
        sleep 1
    done

    wait $pid
    return $?
}

# Procesa PDF con qpdf
process_qpdf() {
    local input_file="$1"
    local temp_file1="$2"
    local qpdf_log="$3"
    local temp_dir="$4"

    if qpdf --linearize --object-streams=disable --remove-unreferenced-resources=yes \
            "$input_file" "$temp_file1" > "$qpdf_log" 2>&1; then
        log_message "DEBUG" "QPDF procesó el archivo con éxito."
    else
        log_message "DEBUG" "QPDF encontró problemas. Intentando reparar."
        if qpdf --linearize --object-streams=disable --remove-unreferenced-resources=yes \
                --replace-input "$input_file" > "$qpdf_log" 2>&1 && \
        cp "$input_file" "$temp_file1"; then
            log_message "DEBUG" "QPDF reparó y procesó el archivo."
        else
            log_message "DEBUG" "QPDF no pudo reparar el archivo. Intentando método alternativo."
            if gs -sDEVICE=pdfwrite -dNOPAUSE -dBATCH -dSAFER \
                -dCompatibilityLevel=1.4 -sOutputFile="$temp_file1" "$input_file" > "${temp_dir}/gs_repair.log" 2>&1; then
                log_message "DEBUG" "Ghostscript logró reparar el archivo."
            else
                log_message "WARN" "No se pudo reparar el archivo. Continuando con el archivo original."
                cp "$input_file" "$temp_file1"
            fi
        fi
    fi
}

# Procesa PDF con pdftk
process_pdftk() {
    local temp_file1="$1"
    local temp_file2="$2"
    local pdftk_log="$3"
    local temp_dir="$4"

    local pdftk_script="${temp_dir}/run_pdftk.sh"
    echo '#!/bin/bash
    unset JAVA_TOOL_OPTIONS
    unset _JAVA_OPTIONS
    unset JAVA_OPTIONS
    exec pdftk "$@"' > "$pdftk_script"
    chmod +x "$pdftk_script"
    
    if "$pdftk_script" "$temp_file1" output "$temp_file2" flatten 2> "$pdftk_log"; then
        log_message "DEBUG" "PDFTK aplanó el archivo con éxito."
    else
        log_message "WARN" "PDFTK encontró problemas. Continuando con el archivo sin aplanar."
        cp "$temp_file1" "$temp_file2"
    fi
}

# Elimina JavaScript y acciones automáticas
remove_javascript() {
    local temp_file2="$1"
    local qpdf_log="$2"

    if qpdf --qdf --replace-input "$temp_file2" 2>> "$qpdf_log"; then
        sed -i '/\/JS/d; /\/JavaScript/d; /\/AA/d; /\/OpenAction/d' "$temp_file2"
        qpdf --linearize --replace-input "$temp_file2" 2>> "$qpdf_log"
        log_message "DEBUG" "Eliminación de JavaScript y acciones automáticas completada."
    else
        log_message "WARN" "No se pudo realizar la eliminación de JavaScript y acciones automáticas."
    fi
}

# Procesa PDF con Ghostscript
process_ghostscript() {
    local temp_file2="$1"
    local output_file="$2"
    local gs_log="$3"

    if gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/default \
    -dNOPAUSE -dQUIET -dBATCH \
    -dFirstPage=1 \
    -sOutputFile="$output_file" \
    "$temp_file2" > "$gs_log" 2>&1; then
        if grep -q 'Error:' "$gs_log" || grep -q 'No pages will be processed' "$gs_log"; then
            log_message "WARN" "Ghostscript encontró errores. Intentando método alternativo."
            if qpdf --linearize "$temp_file2" "$output_file" 2>> "$gs_log"; then
                log_message "INFO" "Archivo procesado con éxito usando qpdf como alternativa."
            else
                log_message "ERROR" "Falló el procesamiento con Ghostscript y qpdf. Usando el resultado del paso anterior."
                cp "$temp_file2" "$output_file"
            fi
        else
            log_message "DEBUG" "Ghostscript procesó el archivo con éxito."
        fi
    else
        log_message "WARN" "Ghostscript falló. Intentando método alternativo con qpdf."
        if qpdf --linearize "$temp_file2" "$output_file" 2>> "$gs_log"; then
            log_message "INFO" "Archivo procesado con éxito usando qpdf como alternativa."
        else
            log_message "ERROR" "Falló el procesamiento con Ghostscript y qpdf. Usando el resultado del paso anterior."
            cp "$temp_file2" "$output_file"
        fi
    fi
}

# Configuración del FIFO
setup_fifo() {
    local temp_dir=$(mktemp -d)
    local fifo="$temp_dir/pdf_fifo"
    mkfifo "$fifo"
    echo "$temp_dir" "$fifo"
}

# Función para procesar archivos desde el FIFO
process_files_from_fifo() {
    local fifo="$1"
    local total_files="$2"
    local current_file=0
    local file

    while IFS= read -r file; do
        # Verificar si es la señal de finalización
        if [ "$file" = "DONE" ]; then
            log_message "DEBUG" "Señal de finalización recibida"
            break
        fi

        # Verificar interrupción
        if [ $interrumpido -eq 1 ]; then
            log_message "WARN" "Proceso interrumpido"
            break
        fi

        ((current_file++))

        # Verificar que current_file y total_files sean números válidos
        if [[ "$current_file" =~ ^[0-9]+$ ]] && [[ "$total_files" =~ ^[0-9]+$ ]]; then
            update_progress "$current_file" "$total_files" "$(basename "$file")"
        else
            log_message "WARN" "Valores no válidos para current_file ($current_file) o total_files ($total_files)"
        fi

        # Procesar el archivo
        if [ -f "$file" ]; then
            if [[ "$file" == *.pdf ]]; then
                log_message "DEBUG" "Iniciando procesamiento de: $file"
                if clean_pdf "$file" "$current_file" "$total_files"; then
                    log_message "INFO" "Procesado con éxito: $file"
                else
                    log_message "ERROR" "Falló el procesamiento de: $file"
                fi
            else
                log_message "WARN" "No es un archivo PDF: $file"
            fi
        else
            log_message "ERROR" "El archivo no existe: $file"
        fi
    done < "$fifo"

    log_message "DEBUG" "Proceso de lectura del FIFO completado"
}

# Iniciar procesamiento paralelo
start_parallel_processing() {
    local fifo="$1"
    local num_cores="$2"
    local total_archivos="$3"
    
    for ((i=0; i<num_cores; i++)); do
        process_files_from_fifo "$fifo" "$total_archivos" &
    done
}


# Escribir archivos PDF en el FIFO
write_pdf_to_fifo() {
    local directorio_pdfs="$1"
    local fifo="$2"
    local total_archivos="$3"
    local current_file=0
    
    find "$directorio_pdfs" -type f -name "*.pdf" -print0 | 
    while IFS= read -r -d '' file; do
        if [ $interrumpido -eq 1 ]; then
            break
        fi
        ((current_file++))
        update_progress "$current_file" "$total_archivos" "$(basename "$file")"
        echo "$file" > "$fifo"
    done
    
    # Señal de finalización
    for ((i=0; i<num_cores; i++)); do
        echo "DONE" > "$fifo"
    done
}
# Limpiar recursos del FIFO
cleanup_fifo() {
    local temp_dir="$1"
    rm -rf "$temp_dir"
}

# Verificar argumentos de línea de comandos
check_arguments() {
    while getopts "v" opt; do
        case $opt in
            v) verbose=$((verbose + 1)) ;;
            *) return 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    if [ $# -ne 1 ]; then
        return 1
    fi

    return 0
}

# Verificar directorios
check_directories() {
    local directorio_pdfs="$1"

    if [ ! -d "$directorio_pdfs" ]; then
        log_message "ERROR" "El directorio \"$directorio_pdfs\" no existe."
        return 1
    fi

    if [ ! -r "$directorio_pdfs" ]; then
        log_message "ERROR" "No se tienen permisos de lectura en el directorio \"$directorio_pdfs\"."
        return 1
    fi

    return 0
}


# Inicializar el proceso
initialize() {
    for cmd in qpdf pdftk gs timeout; do
        if ! check_command "$cmd"; then
            log_message "ERROR" "Comando requerido no encontrado: $cmd"
            return 1
        fi
    done

    trap manejar_interrupcion INT TERM

    return 0
}
# Procesar PDFs
process_pdfs() {
    local directorio_pdfs="$1"

    # Contar archivos PDF
    local total_archivos
    total_archivos=$(find "$directorio_pdfs" -type f -name "*.pdf" | wc -l)
    
    # Verificar si el conteo fue exitoso y si hay archivos
    if [ $? -ne 0 ] || [ -z "$total_archivos" ] || [ "$total_archivos" -eq 0 ]; then
        log_message "ERROR" "No se pudieron encontrar archivos PDF o hubo un error en el conteo."
        handle_no_pdfs "$directorio_pdfs"
        return 1
    fi

    log_message "INFO" "Se encontraron $total_archivos archivos PDF para procesar en \"$directorio_pdfs\""

    # Configurar FIFO
    local temp_dir fifo
    read temp_dir fifo < <(setup_fifo)
    
    if [ -z "$temp_dir" ] || [ -z "$fifo" ]; then
        log_message "ERROR" "Fallo al configurar FIFO."
        return 1
    fi

    # Iniciar procesamiento paralelo
    local num_cores
    num_cores=$(nproc --all)
    log_message "INFO" "Utilizando $num_cores núcleos para procesamiento paralelo"
    
    start_parallel_processing "$fifo" "$num_cores" "$total_archivos"

    # Procesar archivos
    log_message "INFO" "Buscando archivos PDF en \"$directorio_pdfs\""
    write_pdf_to_fifo "$directorio_pdfs" "$fifo" "$total_archivos"

    # Cerrar el FIFO y esperar que terminen los procesos
    exec 3>&-
    wait

    # Verificar resultados
    verify_results "$directorio_pdfs"

    # Limpiar recursos
    cleanup_fifo "$temp_dir"
}

# Manejar caso de no encontrar PDFs
handle_no_pdfs() {
    local directorio_pdfs="$1"
    log_message "ERROR" "Error al buscar archivos PDF en \"$directorio_pdfs\" o no se encontraron archivos"
    echo "Contenido de \"$directorio_pdfs\":"
    ls -la "$directorio_pdfs"
}

# Verificar resultados del procesamiento
verify_results() {
    local directorio_pdfs="$1"
    log_message "INFO" "Procesamiento paralelo completado. Verificando resultados..."
    for file in "$directorio_pdfs"/*.pdf; do
        local output_file="$directorio_salida/$(basename "${file%.*}")_limpio.pdf"
        if [ ! -f "$output_file" ]; then
            log_message "WARN" "No se encontró archivo de salida para: $file"
        fi
    done
}

# Finalizar el proceso y mostrar resumen
finalize() {
    if [ $interrumpido -eq 1 ]; then
        log_message "WARN" "Proceso interrumpido por el usuario."
    else
        log_message "INFO" "Proceso de limpieza completado."
    fi

    # Limpieza final
    find "$directorio_salida" -type d -name "temp_*" -exec rm -rf {} +

    # Imprimir resumen
    print_summary
}

# Imprimir resumen del proceso
print_summary() {
    log_message "INFO" "Resumen del proceso:"
    log_message "INFO" "Total de archivos encontrados: $total_archivos"
    log_message "INFO" "Archivos procesados: $archivos_procesados"
    log_message "INFO" "Archivos procesados exitosamente: $archivos_exitosos"
    log_message "INFO" "Archivos con fallos en el procesamiento: $archivos_fallidos"

    local archivos_salida=$(find "$directorio_salida" -name "*_limpio.pdf" | wc -l)
    log_message "INFO" "Archivos encontrados en el directorio de salida: $archivos_salida"

    if [ $archivos_procesados -ne $total_archivos ] || [ $archivos_salida -ne $archivos_exitosos ]; then
        log_message "WARN" "Discrepancia en el número de archivos:"
        log_message "WARN" "  - Total esperado: $total_archivos"
        log_message "WARN" "  - Procesados: $archivos_procesados"
        log_message "WARN" "  - Exitosos: $archivos_exitosos"
        log_message "WARN" "  - En salida: $archivos_salida"
        log_message "WARN" "  - Fallidos: $archivos_fallidos"
    fi

    for status in "${!summary[@]}"; do
        log_message "INFO" "$status: ${summary[$status]}"
    done

    log_message "INFO" "Revise el archivo de log para más detalles: $archivo_log"
}

initialize_output_directory
# Función principal
main() {
    local directorio_pdfs

    # Verificar argumentos y directorios
    if ! check_arguments "$@"; then
        log_message "ERROR" "Uso: $0 [-v] <directorio_pdfs>"
        exit 1
    fi

    directorio_pdfs="$1"

    if ! check_directories "$directorio_pdfs"; then
        log_message "ERROR" "Directorio de PDFs no válido: $directorio_pdfs"
        exit 1
    fi

    # Inicializar
    if ! initialize; then
        log_message "ERROR" "Fallo en la inicialización"
        exit 1
    fi

    log_message "INFO" "Iniciando proceso de limpieza de PDFs"
    log_message "DEBUG" "Directorio de entrada: $directorio_pdfs"

    # Procesar PDFs
    if ! process_pdfs "$directorio_pdfs"; then
        log_message "ERROR" "Fallo en el procesamiento de PDFs"
        exit 1
    fi

    # Finalizar y mostrar resumen
    finalize
}

# Ejecutar la función principal
main "$@"