#!/bin/bash

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if required tools are installed
for cmd in pdftk pdfid; do
    if ! command_exists $cmd; then
        echo "Error: $cmd is not installed. Please install it and try again."
        exit 1
    fi
done

# Function to analyze PDF with pdfid
analyze_pdf() {
    local file="$1"
    local analysis=$(pdfid "$file")
    local risk_score=0
    local risk_factors=""

    # Check for risk factors
    if echo "$analysis" | grep -q "/JS.*[1-9]"; then
        risk_score=$((risk_score + 2))
        risk_factors+="JS "
    fi
    if echo "$analysis" | grep -q "/JavaScript.*[1-9]"; then
        risk_score=$((risk_score + 2))
        risk_factors+="JavaScript "
    fi
    if echo "$analysis" | grep -q "/AA.*[1-9]"; then
        risk_score=$((risk_score + 2))
        risk_factors+="AA "
    fi
    if echo "$analysis" | grep -q "/OpenAction.*[1-9]"; then
        risk_score=$((risk_score + 1))
        risk_factors+="OpenAction "
    fi

    if [ $risk_score -gt 0 ]; then
        echo "Potencial riesgo (score: $risk_score). Factores de riesgo presentes: $risk_factors"
        return 1
    else
        echo "No se detectaron factores de riesgo comunes."
        return 0
    fi
}

# Process each input PDF
for input_file in "$@"; do
    # Check if input file exists
    if [ ! -f "$input_file" ]; then
        echo "Error: Input file '$input_file' does not exist. Skipping."
        continue
    fi

    echo "Analizando: $input_file"
    initial_analysis=$(analyze_pdf "$input_file")
    echo "$initial_analysis"

    if [ $? -eq 1 ]; then
        # Generate output filename
        filename=$(basename -- "$input_file")
        extension="${filename##*.}"
        filename="${filename%.*}"
        output_file="${filename}-clean.${extension}"

        echo "Limpiando PDF..."
        if pdftk "$input_file" output "$output_file" uncompress; then
            echo "PDF procesado. Analizando resultado:"
            final_analysis=$(analyze_pdf "$output_file")
            echo "$final_analysis"

            if [ $? -eq 0 ]; then
                echo "Limpieza exitosa. Archivo guardado como $output_file"
            else
                echo "Advertencia: Algunos factores de riesgo pueden persistir en $output_file"
            fi
        else
            echo "Error: Falló el procesamiento de PDF para $input_file."
        fi
    else
        echo "No se requiere limpieza para $input_file"
    fi

    echo "-----------------------------------------"
done

echo "Script completado."
