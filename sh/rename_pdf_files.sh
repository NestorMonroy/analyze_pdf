#!/bin/bash

# Definir los patrones a buscar y eliminar
patterns=(
    "_limpio"
    "_unlockedlimpio"
    "limpio"
)

rename_pdf_files() {
    local dir="$1"
    
    # Usa find para localizar todos los archivos PDF en el directorio y subdirectorios
    find "$dir" -type f -name "*.pdf" | while read -r file; do
        # Obtén el nombre del archivo sin la ruta
        filename=$(basename "$file")
        newname="$filename"
        
        # Verifica cada patrón
        for pattern in "${patterns[@]}"; do
            # Elimina el patrón si está al final del nombre (antes de .pdf)
            newname=$(echo "$newname" | sed "s/${pattern}\.pdf$/\.pdf/")
            # Elimina el patrón si está en cualquier otra parte del nombre
            newname=$(echo "$newname" | sed "s/${pattern}//g")
        done
        
        # Si el nombre ha cambiado, renombra el archivo
        if [ "$filename" != "$newname" ]; then
            # Obtén el directorio del archivo
            dirname=$(dirname "$file")
            
            # Construye la nueva ruta completa
            newpath="$dirname/$newname"
            
            # Renombra el archivo
            mv "$file" "$newpath"
            echo "Renombrado: $file -> $newpath"
        fi
    done
}

# Verifica si se proporcionó un argumento
if [ $# -eq 0 ]; then
    echo "Uso: $0 <directorio>"
    exit 1
fi

# Verifica si el directorio existe
if [ -d "$1" ]; then
    rename_pdf_files "$1"
else
    echo "El directorio $1 no existe."
    exit 1
fi