#!/bin/bash

# Configuración de categorías y patrones con regex mejoradas
declare -A categories
categories=(
    ["BigData"]="(?i)(big[ _-]?data|datos[ _-]?masivos)"
    ["IA_MachineLearning"]="(?i)(inteligencia[ _-]?artificial|machine[ _-]?learning|ai[ _-]?for[ _-]?big[ _-]?data)"
    ["IngenieriaSoftware"]="(?i)(ingenieria[ _-]?(?:de[ _-]?)?software|desarrollo[ _-]?(?:de[ _-]?)?software)"
    ["ArquitecturaSoftware"]="(?i)(arquitectura[ _-]?(?:de[ _-]?)?software|software[ _-]?architecture)"
    ["SeguridadInformatica"]="(?i)(seguridad|ciberseguridad|cyber[ _-]?security)"
    ["Metodologias"]="(?i)(scrum|prince2|rup|agil|metodolog[ií]a)"
    ["Estadistica"]="(?i)(estad[ií]stica|probabilidad)"
    ["Programacion"]="(?i)(programaci[óo]n|javascript|python)"
    ["Redes"]="(?i)(redes|sistemas[ _-]?distribuidos|networking)"
    ["UML_Modelado"]="(?i)(uml|modelado|model(?:ling)?)"
    ["SysML"]="(?i)sysml"
    ["GestionProyectos"]="(?i)(gesti[óo]n[ _-]?(?:de[ _-]?)?proyectos|project[ _-]?management)"
    ["InformaticaGeneral"]="(?i)(inform[áa]tica|computaci[óo]n|computing)"
    ["Psicologia_Neurociencia"]="(?i)(psicolog[ií]a|neurociencia)"
    ["Idiomas"]="(?i)(ingl[ée]s|idiomas|language)"
    ["ISO_Normativas"]="(?i)(iso|normativas?|standards?)"
    ["CasosEstudio"]="(?i)(caso(?:s)?[ _-]?(?:de[ _-]?)?estudio|case[ _-]?stud(?:y|ies))"
    ["Tesis_TrabajosAcademicos"]="(?i)(tesis|tfg|trabajo[ _-]?(?:fin[ _-]?de[ _-]?)?grado)"
    ["AWS"]="(?i)aws"
    ["Empresarial"]="(?i)(business|negocio|empresa)"
)

# Función para crear directorios
create_directories() {
    local base_dir="$1"
    for dir in "${!categories[@]}"; do
        mkdir -p "$base_dir/$dir"
    done
}

# Función para mover archivos
move_files() {
    local base_dir="$1"
    local log_file="$base_dir/organize_files.log"
    
    echo "Iniciando organización de archivos en $base_dir" > "$log_file"
    
    find "$base_dir" -maxdepth 1 -type f | while read -r file; do
        filename=$(basename "$file")
        moved=false
        
        for dir in "${!categories[@]}"; do
            if [[ $filename =~ ${categories[$dir]} ]]; then
                target="$base_dir/$dir/$filename"
                if [ -f "$target" ]; then
                    echo "CONFLICTO: $filename ya existe en $dir" >> "$log_file"
                else
                    mv "$file" "$target"
                    echo "MOVIDO: $filename a $dir" >> "$log_file"
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
    local target_dir="$1"

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

# Llamar a la función principal con el argumento pasado al script
main "$1"
