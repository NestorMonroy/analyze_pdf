#!/bin/bash

# Función para registrar mensajes
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Verifica si las herramientas necesarias están instaladas
for cmd in qpdf pdftk gs; do
    if ! command -v $cmd &> /dev/null; then
        log_message "$cmd no está instalado. Por favor, instálalo primero."
        exit 1
    fi
done

clean_pdf() {
    input_file="$1"
    base_name=$(basename "$input_file" .pdf)
    temp_file1="${base_name}_temp1.pdf"
    temp_file2="${base_name}_temp2.pdf"
    output_file="${base_name}_limpio.pdf"
    gs_log="${base_name}_gs_log.txt"

    log_message "Limpiando $input_file usando múltiples métodos..."

    # Método 1: Usar qpdf para linearizar y eliminar elementos no referenciados
    if qpdf --linearize --object-streams=disable --remove-unreferenced-resources=yes "$input_file" "$temp_file1" 2>/dev/null; then
        log_message "QPDF procesó el archivo con éxito."
    else
        log_message "QPDF encontró problemas. Continuando con el archivo original."
        cp "$input_file" "$temp_file1"
    fi

    # Método 2: Usar pdftk para "aplanar" el PDF
    if pdftk "$temp_file1" output "$temp_file2" flatten 2>/dev/null; then
        log_message "PDFTK aplanó el archivo con éxito."
    else
        log_message "PDFTK encontró problemas. Continuando con el archivo sin aplanar."
        cp "$temp_file1" "$temp_file2"
    fi

    # Método 3: Usar sed para eliminar referencias a JavaScript y acciones automáticas
    if qpdf --qdf --replace-input "$temp_file2" 2>/dev/null; then
        sed -i '/\/JS/d; /\/JavaScript/d; /\/AA/d; /\/OpenAction/d' "$temp_file2"
        qpdf --linearize --replace-input "$temp_file2" 2>/dev/null
        log_message "Eliminación de JavaScript y acciones automáticas completada."
    else
        log_message "No se pudo realizar la eliminación de JavaScript y acciones automáticas."
    fi

    # Método 4: Usar Ghostscript para "reimprimir" el PDF
    if gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/default \
       -dNOPAUSE -dQUIET -dBATCH \
       -dFirstPage=1 \
       -sOutputFile="$output_file" \
       "$temp_file2" > "$gs_log" 2>&1; then
        if grep -q "Error:" "$gs_log" || grep -q "No pages will be processed" "$gs_log"; then
            log_message "Ghostscript encontró errores. Usando el resultado del paso anterior."
            cp "$temp_file2" "$output_file"
            log_message "Errores de Ghostscript:"
            cat "$gs_log"
        else
            log_message "Ghostscript procesó el archivo con éxito."
        fi
    else
        log_message "Ghostscript falló. Usando el resultado del paso anterior."
        cp "$temp_file2" "$output_file"
    fi

    # Limpieza de archivos temporales
    rm -f "$temp_file1" "$temp_file2" "$gs_log"
    
    log_message "PDF limpio guardado como $output_file"
}

# Verifica si se proporcionaron argumentos
if [ $# -eq 0 ]; then
    echo "Uso: $0 archivo1.pdf archivo2.pdf ..."
    exit 1
fi

# Procesa cada archivo proporcionado como argumento
for file in "$@"; do
    if [ -f "$file" ] && [[ "$file" == *.pdf ]]; then
        clean_pdf "$file"
    elif [ ! -f "$file" ]; then
        log_message "Error: El archivo $file no existe."
    else
        log_message "Error: $file no es un archivo PDF."
    fi
done

log_message "Proceso de limpieza completado."