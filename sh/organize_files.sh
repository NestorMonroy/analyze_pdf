#!/bin/bash

# Configuración de categorías y patrones
declare -A categories
categories=(
    ["BigData"]="big.*data"
    ["IA_MachineLearning"]="inteligencia.*artificial|machine.*learning"
    ["IngenieriaSoftware"]="ingenieria.*software|desarrollo"
    ["ArquitecturaSoftware"]="arquitectura.*software"
    ["SeguridadInformatica"]="seguridad|ciberseguridad"
    ["Metodologias/Scrum"]="scrum"
    ["Metodologias/PRINCE2"]="prince2"
    ["Metodologias/RUP"]="rup"
    ["Metodologias/Agiles"]="agil"
    ["Estadistica"]="estadistica|probabilidad"
    ["Programacion"]="programacion"
    ["Redes"]="redes|sistemas.*distribuidos"
    ["UML_Modelado"]="uml|modelado"
    ["GestionProyectos"]="gestion.*proyectos"
    ["InformaticaGeneral"]="informatica"
    ["Psicologia_Neurociencia"]="psicologia|neurociencia"
    ["Idiomas"]="ingles|idiomas"
    ["ISO_Normativas"]="iso|normativas"
    ["CasosEstudio"]="caso.*estudio"
    ["Tesis_TrabajosAcademicos"]="tesis|tfg"
)

# Función para crear directorios
create_directories() {
    local base_dir="$1"
    for dir in "${!categories[@]}"; do
        mkdir -p "$base_dir/$dir"
    done
}

# Función para mover o copiar archivos
process_files() {
    local base_dir="$1"
    local mode="$2"
    local log_file="$base_dir/organize_files.log"
    
    echo "Iniciando organización de archivos en $base_dir" > "$log_file"
    
    find "$base_dir" -type f | while read -r file; do
        filename=$(basename "$file")
        moved=false
        
        for dir in "${!categories[@]}"; do
            if [[ $filename =~ ${categories[$dir]} ]]; then
                target="$base_dir/$dir/$filename"
                if [ -f "$target" ]; then
                    echo "CONFLICTO: $filename ya existe en $dir" >> "$log_file"
                else
                    if [ "$mode" = "copy" ]; then
                        cp "$file" "$target"
                        echo "COPIADO: $filename a $dir" >> "$log_file"
                    else
                        mv "$file" "$target"
                        echo "MOVIDO: $filename a $dir" >> "$log_file"
                    fi
                    moved=true
                    break
                fi
            fi
        done
        
        if ! $moved; then
            echo "NO CLASIFICADO: $filename" >> "$log_file"
        fi
    done
    
    echo "Organización completada. Revisa $log_file para detalles."
}

# Función principal
main() {
    local OPTIND opt
    local target_dir=""
    local mode="move"
    local simulate=false

    while getopts ":d:csm" opt; do
        case $opt in
            d) target_dir="$OPTARG" ;;
            c) mode="copy" ;;
            s) simulate=true ;;
            m) mode="move" ;;
            \?) echo "Opción inválida: -$OPTARG" >&2; return 1 ;;
        esac
    done

    if [ -z "$target_dir" ]; then
        echo "Uso: $0 -d <directorio> [-c para copiar] [-m para mover] [-s para simular]"
        return 1
    fi

    if [ ! -d "$target_dir" ]; then
        echo "El directorio $target_dir no existe."
        return 1
    fi

    if $simulate; then
        echo "Modo de simulación. No se realizarán cambios reales."
        process_files "$target_dir" "simulate"
    else
        create_directories "$target_dir"
        process_files "$target_dir" "$mode"
    fi
}

# Llamar a la función principal con todos los argumentos pasados al script
main "$@"
