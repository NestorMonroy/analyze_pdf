#!/bin/bash
# Script de búsqueda hexadecimal en PDF
if [ $# -eq 0 ]; then
    echo "Uso: $0 archivo.pdf"
    exit 1
fi

PDF_FILE="$1"

if [ ! -f "$PDF_FILE" ]; then
    echo "El archivo $PDF_FILE no existe."
    exit 1
fi

SEARCH_STRINGS=(
    "/JavaScript"
    "/JS"
    "/Action"
    "/OpenAction"
    "/AA"
    "/Launch"
    "/URI"
    "/SubmitForm"
    "/GoTo"
    "/RichMedia"
    "/EmbeddedFile"
    "eval("
    "function("
)

echo "Buscando cadenas sospechosas en $PDF_FILE..."

for string in "${SEARCH_STRINGS[@]}"; do
    echo "Buscando: $string"
    xxd "$PDF_FILE" | grep -n "$string"
    echo "---"
done

echo "Búsqueda completada."