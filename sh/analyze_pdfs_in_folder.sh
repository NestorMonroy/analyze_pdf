#!/bin/bash

function analyze_pdf_health() {
    local pdf_file="$1"
    local output=$(pdfid "$pdf_file")
    local suspicious=false

    # Verificar características potencialmente peligrosas
    if echo "$output" | grep -q -E "/JS|/JavaScript|/AA|/OpenAction|/JBIG2Decode|/RichMedia|/Launch|/EmbeddedFile|/XFA"; then
        suspicious=true
    fi

    # Verificar si hay objetos ocultos
    if echo "$output" | grep -q "/ObjStm" && [ "$(echo "$output" | grep "/ObjStm" | awk '{print $2}')" -gt 0 ]; then
        suspicious=true
    fi

    # Verificar si hay páginas ocultas
    local pages=$(echo "$output" | grep "/Page" | awk '{print $2}')
    local count_pages=$(echo "$output" | grep "/Count" | awk '{print $2}')
    if [ "$pages" != "$count_pages" ]; then
        suspicious=true
    fi

    if [ "$suspicious" = true ]; then
        echo "ADVERTENCIA: El archivo $pdf_file puede contener elementos sospechosos."
    else
        echo "OK: El archivo $pdf_file parece estar sano."
    fi
}

function analyze_pdfs_in_folder() {
    if [ $# -eq 0 ]; then
        echo "Uso: analyze_pdfs_in_folder <carpeta> [archivo_salida.txt]"
        return 1
    fi
    
    local folder="$1"
    local output_file="${2:-pdfid_results.txt}"
    
    if [ ! -d "$folder" ]; then
        echo "Error: La carpeta '$folder' no existe."
        return 1
    fi
    
    if ! command -v pdfid &> /dev/null; then
        echo "Error: pdfid no está instalado. Instálalo con 'sudo apt-get install pdf-parser'."
        return 1
    fi
    
    echo "Analizando PDFs en $folder y guardando resultados en $output_file"
    
    # Limpia el archivo de salida si ya existe
    > "$output_file"
    
    find "$folder" -type f -name "*.pdf" | while read -r pdf_file; do
        echo "Analizando: $pdf_file" | tee -a "$output_file"
        pdfid "$pdf_file" >> "$output_file"
        analyze_pdf_health "$pdf_file" | tee -a "$output_file"
        echo "-----------------------------------------" >> "$output_file"
    done
    
    echo "Análisis completado. Resultados guardados en $output_file"
}

analyze_pdfs_in_folder "$@"
