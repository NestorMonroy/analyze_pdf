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



# Definir códigos de color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

shorten_filename() {
    local filename="$1"
    local max_length=50  # Ajusta este valor según tus preferencias
    if [ ${#filename} -gt $max_length ]; then
        echo "${filename:0:$((max_length-3))}..."
    else
        echo "$filename"
    fi
}


log_message() {
    local nivel="${1:-INFO}"
    local mensaje="${2:-No message provided}"
    local archivo="${3:-}"
    local etapa="${4:-}"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp]"
    local color=""

    # Asignar color según el nivel de log
    case $nivel in
        "ERROR")   color="$RED" ;;
        "WARN")    color="$YELLOW" ;;
        "INFO")    color="$GREEN" ;;
        "DEBUG")   color="$BLUE" ;;
        *)         color="$NC" ;;
    esac

    log_entry+=" [${color}${nivel}${NC}]"

    if [[ -n "$archivo" ]]; then
        local short_filename=$(shorten_filename "$archivo")
        log_entry+=" [Archivo: $short_filename]"
    fi

    if [[ -n "$archivo" ]]; then
        log_entry+=" [Archivo: $archivo]"
    fi
    if [[ -n "$etapa" ]]; then
        log_entry+=" [Etapa: $etapa]"
    fi
    
    log_entry+=" $mensaje"

    # Imprimir en la consola con colores si es una terminal
    if [ -t 1 ]; then
        echo -e "$log_entry"
    else
        # Eliminar códigos de color si la salida no es a una terminal
        echo -e "$log_entry" | sed 's/\x1b\[[0-9;]*m//g'
    fi

    # Guardar en el archivo de log sin colores
    echo -e "$log_entry" | sed 's/\x1b\[[0-9;]*m//g' >> "$ARCHIVO_LOG"

    echo -e "$log_entry" | tee -a "$ARCHIVO_LOG"
    
    # Añadir logging adicional para diagnóstico
    if [[ "$nivel" == "ERROR" || "$nivel" == "WARN" ]]; then
        echo "Contenido del directorio temporal:" >> "$ARCHIVO_LOG"
        ls -l "$temp_dir" >> "$ARCHIVO_LOG" 2>&1
        echo "Tamaño del archivo de entrada: $(du -h "$input_file" | cut -f1)" >> "$ARCHIVO_LOG"
        echo "Tamaño del archivo de salida: $(du -h "$temp_output" 2>/dev/null | cut -f1)" >> "$ARCHIVO_LOG"
    fi

}

check_pdf_files() {
    local pdf_count=$(find "$@" -type f -name "*.pdf" | wc -l)
    
    if [ "$pdf_count" -eq 0 ]; then
        log_message "ERROR" "No se encontraron archivos PDF para procesar. Terminando el script."
        exit 1
    else
        log_message "INFO" "Se encontraron $pdf_count archivos PDF para procesar."
    fi
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
    
    local cleaning_steps=(
        "optimizar"
        "eliminar_aa"
        "eliminar_aa_sed"        
        "aplanar_metadatos"
        "aplanar_pdftk"
        "eliminar_js"
        "reimprimir"
    )
    
    local current_file="$input_file"
    local step_counter=0
    local error_occurred=false
    
    for step in "${cleaning_steps[@]}"; do
        step_counter=$((step_counter + 1))
        local temp_output="$temp_dir/temp_${step_counter}.pdf"
        
        log_message "INFO" "Aplicando método de limpieza: $step" "$input_file" "limpieza_$step"
        
        case $step in
            "optimizar")
                if ! qpdf "$current_file" --object-streams=disable --compress-streams=y --decode-level=specialized "$temp_output" 2>/dev/null; then
                    log_message "WARN" "Fallo en el método de limpieza: $step. Continuando con el archivo original." "$input_file" "limpieza_$step"
                    cp "$current_file" "$temp_output"
                fi
                ;;
            "aplanar_metadatos")
            # --remove-page-labels --generate-appearances   --flatten-annotations=all no exite
                if ! qpdf "$current_file" --flatten-annotations=all  "$temp_output" 2>/dev/null; then
                    log_message "WARN" "Fallo en el método de limpieza: $step. Continuando con el archivo original." "$input_file" "limpieza_$step"
                    cp "$current_file" "$temp_output"
                fi
                ;;
            "aplanar_pdftk")
                if ! pdftk "$current_file" output "$temp_output" flatten 2>/dev/null; then
                    log_message "WARN" "Fallo al aplanar con pdftk. Continuando con el archivo original." "$input_file" "limpieza_$step"
                    cp "$current_file" "$temp_output"
                else
                    log_message "INFO" "PDF aplanado con pdftk" "$input_file" "limpieza_$step"
                fi
                ;;
            "eliminar_js")
                cp "$current_file" "$temp_output"
                local qdf_output
                if qdf_output=$(qpdf --qdf --replace-input "$temp_output" 2>&1); then
                    log_message "INFO" "Conversión a formato QDF exitosa" "$input_file" "limpieza_$step"
                    if sed -i '/\/JS/d; /\/JavaScript/d; /\/AA/d; /\/OpenAction/d' "$temp_output"; then
                        log_message "INFO" "Eliminación de referencias a JavaScript y acciones completada" "$input_file" "limpieza_$step"
                        
                        # Verificar si el archivo fue modificado
                        if ! diff -q "$current_file" "$temp_output" >/dev/null 2>&1; then
                            log_message "INFO" "Se detectaron y eliminaron elementos de JavaScript o acciones" "$input_file" "limpieza_$step"
                        else
                            log_message "INFO" "No se encontraron elementos de JavaScript o acciones para eliminar" "$input_file" "limpieza_$step"
                        fi
                        
                        local linearize_output
                        if linearize_output=$(qpdf --linearize --replace-input "$temp_output" 2>&1); then
                            log_message "INFO" "Linearización exitosa" "$input_file" "limpieza_$step"
                        else
                            log_message "WARN" "Fallo en la linearización después de eliminar JavaScript y acciones. Continuando con el archivo sin linearizar." "$input_file" "limpieza_$step"
                            log_message "DEBUG" "Error de linearización: $linearize_output" "$input_file" "limpieza_$step"
                        fi
                    else
                        log_message "ERROR" "Fallo al intentar eliminar referencias a JavaScript y acciones" "$input_file" "limpieza_$step"
                        cp "$current_file" "$temp_output"
                    fi
                else
                    log_message "WARN" "Fallo en la conversión a formato QDF. Continuando con el archivo original." "$input_file" "limpieza_$step"
                    log_message "DEBUG" "Error de conversión QDF: $qdf_output" "$input_file" "limpieza_$step"
                    cp "$current_file" "$temp_output"
                fi
                ;;
            "reimprimir")
                if ! gs -sDEVICE=pdfwrite -dPDFSETTINGS=/default -dNOPAUSE -dQUIET -dBATCH \
                   -dCompatibilityLevel=1.5 \
                   -sOutputFile="$temp_output" \
                   "$current_file" 2>/dev/null; then
                    log_message "WARN" "Fallo en el método de limpieza: $step. Continuando con el archivo original." "$input_file" "limpieza_$step"
                    cp "$current_file" "$temp_output"
                fi
                ;;
            "eliminar_aa")
                local temp_aa_output="${temp_dir}/temp_aa_${step_counter}.pdf"
                if qpdf --remove-page-piece-dict "$current_file" "$temp_aa_output" 2>/dev/null; then
                    log_message "INFO" "AA eliminadas con qpdf" "$input_file" "limpieza_$step"
                    mv "$temp_aa_output" "$temp_output"
                else
                    log_message "WARN" "Fallo al intentar eliminar AA con qpdf. Continuando con el archivo original." "$input_file" "limpieza_$step"
                    cp "$current_file" "$temp_output"
                fi
                
                # Verificar si el archivo de salida existe y no está vacío
                if [ ! -f "$temp_output" ] || [ ! -s "$temp_output" ]; then
                    log_message "ERROR" "Archivo de salida no creado o vacío en el paso $step" "$input_file" "limpieza_$step"
                    cp "$current_file" "$temp_output"  # Usar el archivo original si algo falla
                fi
                ;;
            "eliminar_aa_sed")
                cp "$current_file" "$temp_output"
                if sed -i '/\/AA/d; /\/A <<.*>>/d; /\/A \[.*\]/d' "$temp_output"; then
                    log_message "INFO" "AA eliminadas con sed" "$input_file" "limpieza_$step"
                else
                    log_message "WARN" "Fallo al intentar eliminar AA con sed" "$input_file" "limpieza_$step"
                fi
                ;;
        esac
        
        if [ ! -f "$temp_output" ] || [ ! -s "$temp_output" ]; then
            log_message "ERROR" "Archivo de salida no creado o vacío en el paso $step" "$input_file" "limpieza_$step"
            if [ "$step" != "eliminar_aa" ]; then  # Ya manejamos este caso específicamente
                cp "$current_file" "$temp_output"  # Usar el archivo original si algo falla
            fi
        else
            current_file="$temp_output"
        fi
    done
    
   if [ "$error_occurred" = false ]; then
        cp "$current_file" "$output_file"
        log_message "INFO" "Todos los métodos de limpieza aplicados" "$input_file" "limpieza_completa"
        return 0
    else
        log_message "ERROR" "Proceso de limpieza fallido" "$input_file" "limpieza_completa"
        return 1
    fi

    if [ "$error_occurred" = true ]; then
        log_message "WARN" "Intentando reconstruir el PDF" "$input_file" "reconstruccion"
        reconstruct_pdf "$current_file" "$temp_output"
        if [ $? -eq 0 ]; then
            log_message "INFO" "Reconstrucción del PDF exitosa" "$input_file" "reconstruccion"
        else
            log_message "ERROR" "Fallo en la reconstrucción del PDF" "$input_file" "reconstruccion"
            cp "$current_file" "$temp_output"
        fi
    fi

    # verify_aa_removal
    if ! verify_aa_removal "$output_file"; then
        log_message "ERROR" "La eliminación de AA no fue completamente exitosa" "$input_file" "verificacion"
    fi
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
    
    # Verificar que no se hayan introducido ObjStm
    local objstm_count=$(pdfid "$output_file" | grep "/ObjStm" | awk '{print $2}')
    if [ "$objstm_count" -gt 0 ]; then
        log_message "WARN" "Se detectaron $objstm_count Object Streams en el archivo limpio" "$input_file" "verificacion"
    fi
    
    log_message "INFO" "Verificación de integridad exitosa" "$input_file" "verificacion"
    return 0
}

verify_aa_removal() {
    local file="$1"
    if grep -q "/AA" "$file" || grep -q "/A <<" "$file" || grep -q "/A \[" "$file"; then
        log_message "WARN" "Se detectaron AA residuales en el archivo" "$file" "verificacion"
        return 1
    fi
    log_message "INFO" "No se detectaron AA residuales" "$file" "verificacion"
    return 0
}

# Función principal para limpiar un PDF
clean_pdf() {

    if ! check_permissions_and_space "$DIRECTORIO_SALIDA"; then
        return 1
    fi

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
        "no_iniciado"|"analisis_pre")
            analyze_pdf "$input_file" "$ARCHIVO_ANALISIS_PRE" "analisis_pre"
            if [ $? -ne 0 ]; then
                log_message "ERROR" "Fallo en el análisis pre-limpieza" "$input_file" "analisis_pre"
                return 1
            fi
            local initial_checksum=$(calculate_checksum "$input_file")
            set_estado "$input_file" "analisis_pre" "$initial_checksum"
            ;&  # Fall through
        "reparacion")
            local repaired_file="${temp_dir}/${base_name}_repaired.pdf"
            repair_pdf "$input_file" "$repaired_file"
            if [ $? -ne 0 ]; then
                log_message "ERROR" "Fallo en la reparación del PDF" "$input_file" "reparacion"
                return 1
            fi
            set_estado "$input_file" "reparado" $(calculate_checksum "$repaired_file")
            ;&
        "transformacion")
            local version=$(pdfinfo "$repaired_file" | grep "PDF version" | awk '{print $3}')
            log_message "INFO" "Versión del PDF: $version" "$input_file" "version_check"
            local transformed_file="${temp_dir}/${base_name}_transformed.pdf"
            if [ "$version" != "1.5" ]; then
                transform_to_1_5 "$repaired_file" "$transformed_file"
                if [ $? -ne 0 ]; then
                    log_message "ERROR" "Fallo en la transformación a PDF 1.5" "$input_file" "transformacion"
                    return 1
                fi
            else
                cp "$repaired_file" "$transformed_file"
            fi
            set_estado "$input_file" "transformado" $(calculate_checksum "$transformed_file")
            ;&
        "limpieza")
            local cleaned_file="${temp_dir}/${base_name}_cleaned.pdf"
            apply_cleaning_methods "$transformed_file" "$cleaned_file" "$temp_dir"
            if [ $? -ne 0 ]; then
                log_message "ERROR" "Fallo en la aplicación de métodos de limpieza" "$input_file" "limpieza"
                return 1
            fi
            set_estado "$input_file" "limpiado" $(calculate_checksum "$cleaned_file")
            ;&
        "verificacion")
            if ! verify_pdf_integrity "$input_file" "$cleaned_file"; then
                log_message "ERROR" "Fallo en la verificación de integridad del PDF" "$input_file" "verificacion"
                return 1
            fi
            if ! verify_aa_removal "$cleaned_file"; then
                log_message "WARN" "Se detectaron AA residuales en el archivo limpio" "$input_file" "verificacion"
            fi
            cp "$cleaned_file" "$output_file"
            set_estado "$input_file" "verificado" $(calculate_checksum "$output_file")
            ;&
        "analisis_post")
            analyze_pdf "$output_file" "$ARCHIVO_ANALISIS_POST" "analisis_post"
            if [ $? -ne 0 ]; then
                log_message "ERROR" "Fallo en el análisis post-limpieza" "$input_file" "analisis_post"
                return 1
            fi
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
                return $?
            fi
            ;;
        *)
            log_message "ERROR" "Estado desconocido: $estado" "$input_file" "error"
            return 1
            ;;
    esac
    
    if [ -f "$output_file" ] && [ -s "$output_file" ]; then
        log_message "INFO" "Limpieza completada con éxito" "$input_file" "fin"
        rm -rf "$temp_dir"
        return 0
    else
        log_message "ERROR" "Archivo de salida no creado o vacío" "$input_file" "fin"
        return 1
    fi

}

reconstruct_pdf() {
    local input_file="$1"
    local output_file="$2"
    
    # Extraer páginas individuales
    pdftk "$input_file" burst output "${temp_dir}/page_%04d.pdf"
    
    # Reconstruir el PDF sin JavaScript
    pdftk "${temp_dir}"/page_*.pdf cat output "$output_file"
    
    # Limpiar archivos temporales
    rm "${temp_dir}"/page_*.pdf
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

check_permissions_and_space() {
    local dir="$1"
    if [ ! -w "$dir" ]; then
        log_message "ERROR" "No se tienen permisos de escritura en $dir" "$input_file" "verificacion"
        return 1
    fi
    
    local free_space=$(df -k "$dir" | awk 'NR==2 {print $4}')
    if [ "$free_space" -lt 1048576 ]; then  # Menos de 1GB libre
        log_message "ERROR" "Espacio insuficiente en disco en $dir" "$input_file" "verificacion"
        return 1
    fi
    
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
    
    # Verificar permisos
    if ! verificar_permisos; then
        log_message "ERROR" "No se tienen los permisos necesarios para ejecutar el script."
        exit 1
    fi
    
    # Verificar si hay archivos PDF para procesar
    check_pdf_files "$@"
    
    # Iniciar archivos de log y análisis
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