#!/bin/bash

# Configuración
directorio_salida="archivos_salida_1.5"
archivo_log="$directorio_salida/proceso_pdf.log"
archivo_transformados="$directorio_salida/pdfs_transformados.txt"
archivo_analisis_pre="$directorio_salida/analisis_pre_limpieza.txt"
archivo_analisis_post="$directorio_salida/analisis_post_limpieza.txt"
num_cores=$(nproc --all)

# Crear directorios necesarios
mkdir -p "$directorio_salida"
temp_dir=$(mktemp -d)
fifo="$temp_dir/pdf_fifo"
mkfifo "$fifo"

# Función para registrar mensajes
log_message() {
    local mensaje="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo "$mensaje"
    echo "$mensaje" >> "$archivo_log"
}

# Verificar herramientas necesarias
for cmd in qpdf pdftk gs pdfinfo pdfid; do
    if ! command -v $cmd &> /dev/null; then
        log_message "Error: $cmd no está instalado. Por favor, instálalo primero."
        exit 1
    fi
done

# Función para analizar un PDF con pdfid
analyze_pdf() {
    local pdf_file="$1"
    local output_file="$2"
    echo "Analizando: $pdf_file" | tee -a "$output_file"
    pdfid "$pdf_file" >> "$output_file"
    echo "-----------------------------------------" >> "$output_file"
}

# Función para verificar la versión del PDF
check_pdf_version() {
    pdfinfo "$1" | grep "PDF version" | awk '{print $3}'
}

# Función para transformar el PDF a versión 1.5
transform_to_1_5() {
    local input_file="$1"
    local output_file="$2"
    
    log_message "ADVERTENCIA: Se va a transformar $input_file a PDF versión 1.5."
    log_message "Esta operación puede afectar algunas características del documento."
    
    if gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.5 -dPDFSETTINGS=/default \
       -dNOPAUSE -dQUIET -dBATCH \
       -sOutputFile="$output_file" \
       "$input_file"; then
        log_message "Transformación a PDF 1.5 completada: $output_file"
        echo "$input_file -> $output_file" >> "$archivo_transformados"
        return 0
    else
        log_message "Error al transformar $input_file a PDF 1.5"
        return 1
    fi
}

# Función principal de limpieza de PDF
clean_pdf() {
    local input_file="$1"
    local base_name=$(basename "$input_file" .pdf)
    local temp_dir="${temp_dir}/${base_name}_temp"
    mkdir -p "$temp_dir"
    local temp_file1="${temp_dir}/${base_name}_temp1.pdf"
    local temp_file2="${temp_dir}/${base_name}_temp2.pdf"
    local temp_file3="${temp_dir}/${base_name}_temp3.pdf"
    local output_file="$directorio_salida/${base_name}_limpio.pdf"
    
    # Analizar PDF antes de la limpieza
    analyze_pdf "$input_file" "$archivo_analisis_pre"
    
    # Verificar la versión del PDF
    local version=$(check_pdf_version "$input_file")
    
    if [ "$version" != "1.5" ]; then
        log_message "El archivo $input_file no es versión 1.5 (es versión $version)"
        if ! transform_to_1_5 "$input_file" "$temp_file1"; then
            rm -rf "$temp_dir"
            return 1
        fi
    else
        cp "$input_file" "$temp_file1"
    fi
    
    # Método 1: Usar qpdf para optimizar y limpiar el PDF
    log_message "Aplicando método 1: qpdf para optimizar y limpiar el PDF"
    if ! qpdf "$temp_file1" --object-streams=generate --compress-streams=y --decode-level=specialized "$temp_file2"; then
        log_message "Error en el método 1 de limpieza"
        cp "$temp_file1" "$temp_file2"
    fi

    # Método 2: Usar qpdf para eliminar metadatos y aplanar
    log_message "Aplicando método 2: qpdf para eliminar metadatos y aplanar"
    if ! qpdf "$temp_file2" --remove-page-labels --flatten-annotations=all --generate-appearances "$temp_file3"; then
        log_message "Error en el método 2 de limpieza"
        cp "$temp_file2" "$temp_file3"
    fi

    # Método pdftk: Usar pdftk para "aplanar" el PDF
    log_message "Aplicando método pdftk: pdftk para eliminar metadatos y aplanar"
    if pdftk "$temp_file1" output "$temp_file2" flatten 2>/dev/null; then
        log_message "PDFTK aplanó el archivo con éxito."
    else
        log_message "PDFTK encontró problemas. Continuando con el archivo sin aplanar."
        cp "$temp_file1" "$temp_file2"
    fi

    # Método sed: Usar sed para eliminar referencias a JavaScript y acciones automáticas
    log_message "Aplicando método sed: Usar sed para eliminar referencias a JavaScript y acciones automáticas"

    if qpdf --qdf --replace-input "$temp_file2" 2>/dev/null; then
        sed -i '/\/JS/d; /\/JavaScript/d; /\/AA/d; /\/OpenAction/d' "$temp_file2"
        qpdf --linearize --replace-input "$temp_file2" 2>/dev/null
        log_message "Eliminación de JavaScript y acciones automáticas completada."
    else
        log_message "No se pudo realizar la eliminación de JavaScript y acciones automáticas."
    fi

    # Método 3: Usar Ghostscript para "reimprimir" el PDF
    log_message "Aplicando método 3: Ghostscript para reimprimir el PDF"
    if gs -sDEVICE=pdfwrite -dPDFSETTINGS=/default -dNOPAUSE -dQUIET -dBATCH \
       -dCompatibilityLevel=1.5 \
       -sOutputFile="$output_file" \
       "$temp_file3"; then
        log_message "Método 3 de limpieza completado con éxito"
    else
        log_message "Error en el método 3 de limpieza"
        cp "$temp_file3" "$output_file"
    fi

    # Analizar PDF después de la limpieza
    analyze_pdf "$output_file" "$archivo_analisis_post"

    # Limpieza de archivos temporales
    rm -rf "$temp_dir"
    
    log_message "Limpieza completada para $input_file"
    log_message "Archivo limpio guardado como $output_file"
}

# Función de procesamiento para cada subshell
process_pdfs() {
    while read -r pdf_file; do
        if [ -f "$pdf_file" ]; then
            clean_pdf "$pdf_file"
        else
            log_message "Archivo no encontrado: $pdf_file"
        fi
    done
}

# Iniciar el archivo de log y los archivos de análisis
echo "Inicio del proceso de análisis y limpieza de PDFs: $(date)" > "$archivo_log"
echo "PDFs transformados a versión 1.5:" > "$archivo_transformados"
echo "Análisis de PDFs antes de la limpieza:" > "$archivo_analisis_pre"
echo "Análisis de PDFs después de la limpieza:" > "$archivo_analisis_post"

# Iniciar procesos en background
for ((i=0; i<num_cores; i++)); do
    process_pdfs < "$fifo" &
done

# Escribir nombres de archivos PDF en el FIFO
find "$@" -type f -name "*.pdf" > "$fifo"

# Esperar a que todos los procesos terminen
wait

# Limpieza
rm -rf "$temp_dir"

log_message "Proceso de análisis y limpieza completado."
log_message "Fin del proceso: $(date)"
log_message "Los PDFs transformados se han listado en $archivo_transformados"
log_message "Análisis pre-limpieza en $archivo_analisis_pre"
log_message "Análisis post-limpieza en $archivo_analisis_post"