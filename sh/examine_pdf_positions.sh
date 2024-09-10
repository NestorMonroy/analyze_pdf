#!/bin/bash

examine_pdf() {
    local PDF_FILE="$1"
    echo "Examinando archivo: $PDF_FILE"

    echo "Examinando alrededor de la primera ocurrencia de /JS (posición 674016):"
    xxd -s 673984 -l 64 "$PDF_FILE"

    echo -e "\nExaminando alrededor de la segunda ocurrencia de /JS (posición 830189):"
    xxd -s 830157 -l 64 "$PDF_FILE"

    echo -e "\nExaminando alrededor de la primera ocurrencia de /AA (posición 114888):"
    xxd -s 114856 -l 64 "$PDF_FILE"

    echo -e "\nExaminando alrededor de la segunda ocurrencia de /AA (posición 1201507):"
    xxd -s 1201475 -l 64 "$PDF_FILE"

    echo "----------------------------------------"
}

if [ $# -eq 0 ]; then
    echo "Uso: $0 archivo.pdf [archivo2.pdf ...]"
    exit 1
fi

for pdf in "$@"; do
    if [ -f "$pdf" ]; then
        examine_pdf "$pdf"
    else
        echo "El archivo $pdf no existe o no es accesible."
    fi
done

echo "Examen completado."