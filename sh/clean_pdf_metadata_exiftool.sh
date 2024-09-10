#!/bin/bash

# Función para imprimir mensajes con formato
print_message() {
    echo -e "\n[INFO] $1"
}

# Función para imprimir errores
print_error() {
    echo -e "\n[ERROR] $1" >&2
}

# Función para verificar si un comando fue exitoso
check_success() {
    if [ $? -ne 0 ]; then
        print_error "$1"
        return 1
    fi
    return 0
}

# Verificar si exiftool está instalado
if ! command -v exiftool &> /dev/null; then
    print_message "exiftool no está instalado. Intentando instalar..."
    sudo apt update
    sudo apt install -y exiftool
    check_success "No se pudo instalar exiftool. Por favor, instálelo manualmente." || exit 1
else
    print_message "exiftool ya está instalado."
fi

# Verificar si se proporcionaron argumentos
if [ $# -eq 0 ]; then
    print_error "No se proporcionaron archivos PDF. Uso: $0 archivo1.pdf archivo2.pdf ..."
    exit 1
fi

# Procesar cada archivo PDF proporcionado como argumento
for pdf_path in "$@"; do
    # Verificar si el archivo existe y es un PDF
    if [ ! -f "$pdf_path" ] || [[ "$(file -b --mime-type "$pdf_path")" != "application/pdf" ]]; then
        print_error "El archivo $pdf_path no existe o no es un PDF válido. Saltando..."
        continue
    fi

    print_message "Procesando archivo: $pdf_path"

    # Crear una copia de seguridad si no existe
    backup_path="${pdf_path%.*}_backup.pdf"
    if [ ! -f "$backup_path" ]; then
        cp "$pdf_path" "$backup_path"
        if ! check_success "No se pudo crear la copia de seguridad para $pdf_path."; then
            continue
        fi
        print_message "Copia de seguridad creada: $backup_path"
    else
        print_message "La copia de seguridad ya existe: $backup_path"
    fi

    # Mostrar metadatos originales
    print_message "Metadatos originales del PDF $pdf_path:"
    exiftool "$pdf_path"

    # Eliminar todos los metadatos
    print_message "Eliminando metadatos de $pdf_path..."
    if exiftool -all:all= "$pdf_path"; then
        print_message "Metadatos eliminados con éxito de $pdf_path"
    else
        print_error "No se pudieron eliminar los metadatos de $pdf_path"
        continue
    fi

    # Verificar los cambios
    print_message "Metadatos después de la limpieza de $pdf_path:"
    exiftool "$pdf_path"

    print_message "Proceso completado para $pdf_path"
done

print_message "Todos los archivos han sido procesados."