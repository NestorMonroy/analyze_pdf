#!/bin/bash

function analyze_pdfs_in_folder() {
    if [ $# -eq 0 ]; then
        echo "Uso: analyze_pdfs <carpeta> [archivo_salida.txt]"
        return 1
    fi

    folder="$1"
    output_file="${2:-pdfid_results.txt}"

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
        echo "-----------------------------------------" >> "$output_file"
    done

    echo "Análisis completado. Resultados guardados en $output_file"
}

analyze_pdfs_in_folder "$@"
