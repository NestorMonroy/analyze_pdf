#!/bin/bash

# Función para examinar un solo PDF
examine_pdf() {
    local PDF_FILE="$1"
    echo "Examinando archivo: $PDF_FILE"

    # Examinar alrededor de las ocurrencias de /JS
    xxd -s 673984 -l 64 "$PDF_FILE" | grep --color=always -i '/JS' || echo "No se encontró /JS en la primera posición esperada."
    xxd -s 830157 -l 64 "$PDF_FILE" | grep --color=always -i '/JS' || echo "No se encontró /JS en la segunda posición esperada."

    # Examinar alrededor de las ocurrencias de /AA
    xxd -s 114856 -l 64 "$PDF_FILE" | grep --color=always -i '/AA' || echo "No se encontró /AA en la primera posición esperada."
    xxd -s 1201475 -l 64 "$PDF_FILE" | grep --color=always -i '/AA' || echo "No se encontró /AA en la segunda posición esperada."

    echo "----------------------------------------"
}

# Verificar si se proporcionaron argumentos
if [ $# -eq 0 ]; then
    echo "Uso: $0 archivo1.pdf [archivo2.pdf ...]"
    exit 1
fi

# Iterar sobre todos los archivos proporcionados
for pdf in "$@"; do
    if [ -f "$pdf" ]; then
        examine_pdf "$pdf"
    else
        echo "El archivo $pdf no existe o no es accesible."
    fi
done

echo "Examen completado."