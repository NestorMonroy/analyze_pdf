#!/bin/bash

set -e  # Salir inmediatamente si un comando falla

# Asegurar el uso de UTF-8
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

# Directorio de destino para los archivos de salida
directorio_salida="archivos_salida"
# Archivo de log
archivo_log="$directorio_salida/proceso_pdf.log"

# Variables para el resumen
declare -A summary

# Límite de tiempo para procesar cada archivo (en segundos)
tiempo_limite=600 # 10 minutos

# Variable para controlar la interrupción
interrumpido=0

# Contador de archivos procesados
processed_count=0

# Al principio del script, después de las declaraciones iniciales
declare -i archivos_procesados=0
declare -i archivos_exitosos=0
declare -i archivos_fallidos=0

# Función para manejar la interrupción
manejar_interrupcion() {
    echo "Interrupción detectada. Limpiando y saliendo..."
    interrumpido=1
    kill -- -$$  # Envía SIGTERM a todos los procesos en el grupo
}

# Configurar el manejador de interrupciones
trap manejar_interrupcion INT TERM

verbose=0
while getopts "v" opt; do
  case $opt in
    v) verbose=$((verbose + 1)) ;;
  esac
done
shift $((OPTIND - 1))


# Función para registrar mensajes
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
  echo "[$timestamp] [$level] $message" >> "$archivo_log"
}

# Función para verificar si un comando está instalado
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_message "ERROR" "$1 no está instalado. Por favor, instálalo primero."
        exit 1
    fi
}

# Función para sanitizar nombres de archivo
sanitize_filename() {
    local filename="$1"
    # Reemplazar caracteres no alfanuméricos con guiones bajos, excepto espacios
    echo "${filename//[^a-zA-Z0-9. ]/_}"
}

# Verifica si las herramientas necesarias están instaladas
for cmd in qpdf pdftk gs timeout; do
    check_command "$cmd"
done

clean_pdf() {
    local input_file="$1"
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

    # Incrementar el contador de archivos procesados al inicio de la función
    ((archivos_procesados++))

    log_message "INFO" "Iniciando limpieza de \"$input_file\""

    echo "Archivos procesados: $archivos_procesados" >> "$archivo_log"
    
    # Verificar si el archivo de salida ya existe
    if [ -f "$output_file" ]; then
        log_message "INFO" "El archivo \"$output_file\" ya existe. Omitiendo procesamiento."
        summary["Ya existentes"]=$((${summary["Ya existentes"]} + 1))
        return 0
    fi

    # Función para procesar el PDF con límite de tiempo
    if ! process_with_timeout "$input_file" "$temp_file1" "$temp_file2" "$output_file" "$temp_dir" "$gs_log" "$pdftk_log" "$qpdf_log"; then
        log_message "WARN" "El procesamiento de \"$input_file\" excedió el límite de tiempo de $tiempo_limite segundos."
        summary["Tiempo excedido"]=$((${summary["Tiempo excedido"]} + 1))
        return 1
    fi

    # Verificar si el archivo de salida se creó correctamente
    if [ -f "$output_file" ] && [ -s "$output_file" ]; then
        log_message "INFO" "PDF limpio guardado como \"$output_file\""
        summary["Procesados exitosamente"]=$((${summary["Procesados exitosamente"]} + 1))
                # Usar una variable global para contar los éxitos
        ((archivos_exitosos++))

        # Incrementar el contador de archivos procesados
        {
            flock -x 200
            ((archivos_procesados++))
            echo "Archivo procesado: $input_file (Total: $archivos_procesados)" >> "$archivo_log"
        } 200>$temp_dir/count.lock
        
        # Limpieza de archivos temporales
        rm -rf "$temp_dir"
        return 0
    else
        log_message "ERROR" "No se pudo crear el archivo de salida \"$output_file\""
        summary["Fallidos"]=$((${summary["Fallidos"]} + 1))
        # Usar una variable global para contar los fallos
        
        ((archivos_fallidos++))     
        # Limpieza de archivos temporales incluso en caso de fallo
        # rm -rf "$temp_dir"
        return 1
    fi

}

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
        # Inicio del subshell para el procesamiento del PDF
        set +e  # Desactivar salida inmediata en caso de error

        # Método 1: Usar qpdf para linearizar y eliminar elementos no referenciados
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

        # Método 2: Usar pdftk para 'aplanar' el PDF
        pdftk_script="${temp_dir}/run_pdftk.sh"
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

        # Método 3: Usar sed para eliminar referencias a JavaScript y acciones automáticas
        if qpdf --qdf --replace-input "$temp_file2" 2>> "$qpdf_log"; then
            sed -i '/\/JS/d; /\/JavaScript/d; /\/AA/d; /\/OpenAction/d' "$temp_file2"
            qpdf --linearize --replace-input "$temp_file2" 2>> "$qpdf_log"
            log_message "DEBUG" "Eliminación de JavaScript y acciones automáticas completada."
        else
            log_message "WARN" "No se pudo realizar la eliminación de JavaScript y acciones automáticas."
        fi

        # Método 4: Usar Ghostscript para 'reimprimir' el PDF
        if gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/default \
        -dNOPAUSE -dQUIET -dBATCH \
        -dFirstPage=1 \
        -sOutputFile="$output_file" \
        "$temp_file2" > "$gs_log" 2>&1; then
            if grep -q 'Error:' "$gs_log" || grep -q 'No pages will be processed' "$gs_log"; then
                log_message "WARN" "Ghostscript encontró errores. Usando el resultado del paso anterior."
                cp "$temp_file2" "$output_file"
            else
                log_message "DEBUG" "Ghostscript procesó el archivo con éxito."
            fi
        else
            log_message "WARN" "Ghostscript falló. Usando el resultado del paso anterior."
            cp "$temp_file2" "$output_file"
        fi

        exit 0  # Salir del subshell con éxito
    ) &

    pid=$!

    # Esperar el tiempo límite o hasta que el proceso termine
    if ! wait_with_timeout $pid $tiempo_limite; then
        log_message "WARN" "El procesamiento excedió el límite de tiempo. Terminando el proceso."
        kill -TERM $pid 2>/dev/null
        timeout_occurred=1
    fi

    # Verificar si el proceso terminó correctamente
    if [ $timeout_occurred -eq 0 ] && wait $pid; then
        return 0  # El proceso terminó correctamente dentro del tiempo límite
    else
        return 1  # El proceso falló o excedió el tiempo límite
    fi
}

# Función auxiliar para esperar con timeout
wait_with_timeout() {
    local pid=$1
    local timeout=$2
    local count=0
    while [ $count -lt $timeout ]; do
        if ! kill -0 $pid 2>/dev/null; then
            return 0  # El proceso terminó antes del timeout
        fi
        sleep 1
        ((count++))
    done
    return 1  # Timeout ocurrió
}

# Crear el directorio de salida si no existe
mkdir -p "$directorio_salida"

# Iniciar el archivo de log
log_message "INFO" "Inicio del proceso de limpieza de PDFs"

# Verificar si se proporcionaron argumentos
if [ $# -eq 0 ]; then
    log_message "ERROR" "Uso: $0 <directorio_pdfs>"
    exit 1
fi

# Directorio de PDFs a procesar
directorio_pdfs="$1"

# Verificar si el directorio existe
if [ ! -d "$directorio_pdfs" ]; then
    log_message "ERROR" "El directorio \"$directorio_pdfs\" no existe."
    echo "Directorio proporcionado: \"$directorio_pdfs\""
    echo "Directorio actual: $(pwd)"
    echo "Contenido del directorio actual:"
    ls -la
    exit 1
fi

# Contar el número total de archivos PDF
total_archivos=$(find "$directorio_pdfs" -type f -name "*.pdf" | wc -l)
if [ $? -ne 0 ]; then
    log_message "ERROR" "Error al buscar archivos PDF en \"$directorio_pdfs\""
    echo "Contenido de \"$directorio_pdfs\":"
    ls -la "$directorio_pdfs"
    exit 1
fi

log_message "INFO" "Se encontraron $total_archivos archivos PDF para procesar en \"$directorio_pdfs\""


if [ $total_archivos -eq 0 ]; then
    log_message "WARN" "No se encontraron archivos PDF en \"$directorio_pdfs\""
    echo "Contenido de \"$directorio_pdfs\":"
    ls -la "$directorio_pdfs"
    exit 1
fi

# Crear un directorio temporal para el FIFO
temp_dir=$(mktemp -d)
fifo="$temp_dir/pdf_fifo"
mkfifo "$fifo"

# Determinar el número de núcleos del sistema
num_cores=$(nproc --all)
log_message "INFO" "Utilizando $num_cores núcleos para procesamiento paralelo"

# Función para procesar archivos desde el FIFO
process_files() {
    local file
    while IFS= read -r file; do
        if [ $interrumpido -eq 1 ]; then
            break
        fi
        if [ -f "$file" ] && [[ "$file" == *.pdf ]]; then
            log_message "DEBUG" "Iniciando procesamiento de: $file"
            if clean_pdf "$file"; then
                log_message "INFO" "Procesado con éxito: $file"
            else
                log_message "ERROR" "Falló el procesamiento de: $file"
            fi
        elif [ ! -f "$file" ]; then
            log_message "ERROR" "El archivo no existe: $file"
        else
            log_message "ERROR" "No es un archivo PDF: $file"
        fi
    done < "$fifo"
}

#process_files() {
#    while IFS= read -r file; do
#        if [ $interrumpido -eq 1 ]; then
#            break
#        fi
#        if [ -f "$file" ] && [[ "$file" == *.pdf ]]; then
#            clean_pdf "$file"
#        elif [ ! -f "$file" ]; then
#            log_message "ERROR" "El archivo \"$file\" no existe."
#            summary["No existentes"]=$((${summary["No existentes"]} + 1))
#        else
#            log_message "ERROR" "\"$file\" no es un archivo PDF."
#            summary["No PDF"]=$((${summary["No PDF"]} + 1))
#        fi
#        echo "Progreso: $archivos_procesados de $total_archivos"
#    done < "$fifo"
#}


# Iniciar procesos en segundo plano
for ((i=0; i<num_cores; i++)); do
    process_files &
done

# Encontrar archivos PDF y escribirlos en el FIFO
log_message "INFO" "Buscando archivos PDF en \"$directorio_pdfs\""
find "$directorio_pdfs" -type f -name "*.pdf" -print0 | 
while IFS= read -r -d '' file; do
    if [ $interrumpido -eq 1 ]; then
        break
    fi
    echo "$file" > "$fifo"
done

# Cerrar el FIFO
exec 3>&-

# Esperar a que todos los procesos en segundo plano terminen
wait

log_message "INFO" "Procesamiento paralelo completado. Verificando resultados..."
for file in "$directorio_pdfs"/*.pdf; do
    output_file="$directorio_salida/$(basename "${file%.*}")_limpio.pdf"
    if [ ! -f "$output_file" ]; then
        log_message "WARN" "No se encontró archivo de salida para: $file"
    fi
done

# Limpiar archivos temporales finales
rm -rf "$temp_dir"  # Este es el directorio temporal creado para el FIFO

if [ $interrumpido -eq 1 ]; then
    log_message "WARN" "Proceso interrumpido por el usuario."
else
    log_message "INFO" "Proceso de limpieza completado."
fi

# Limpieza final de cualquier archivo temporal que pueda haber quedado
find "$directorio_salida" -type d -name "temp_*" -exec rm -rf {} +

log_message "INFO" "Conteo final de archivos procesados: $archivos_procesados"
log_message "INFO" "Archivos procesados exitosamente: $archivos_exitosos"
log_message "INFO" "Archivos con fallos en el procesamiento: $archivos_fallidos"

# Imprimir resumen
echo "Resumen del proceso:"
echo "Total de archivos encontrados: $total_archivos"
echo "Total de archivos procesados: $archivos_procesados"
echo "Archivos procesados exitosamente: $archivos_exitosos"
echo "Archivos con fallos en el procesamiento: $archivos_fallidos"

# Contar archivos en el directorio de salida
archivos_salida=$(find "$directorio_salida" -name "*_limpio.pdf" | wc -l)
echo "Archivos encontrados en el directorio de salida: $archivos_salida"

if [ $archivos_procesados -ne $total_archivos ] || [ $archivos_salida -ne $archivos_exitosos ]; then
    log_message "WARN" "Discrepancia en el número de archivos. Procesados: $archivos_procesados, Exitosos: $archivos_exitosos, En salida: $archivos_salida, Total esperado: $total_archivos"
fi

for status in "${!summary[@]}"; do
    echo "$status: ${summary[$status]}"
done