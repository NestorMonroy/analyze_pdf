#!/bin/bash

# Configuración de categorías y patrones con regex mejoradas
declare -A categories
categories=(
    ["BigData"]="(?i)(big.*data|datos.*masivos|analytics|anal[ií]tica|nosql)"
    ["IA_MachineLearning"]="(?i)(inteligencia.*artificial|machine.*learning|ai|llm|deep.*learning|aprendizaje.*autom[áa]tico)"
    ["IngenieriaSoftware"]="(?i)(ingenier[ií]a.*(?:de.*)?software|desarrollo.*(?:de.*)?software|software.*engineering|requerimientos|requirements|dise[ñn]o.*de.*software|programaci[óo]n|coding|developer)"
    ["ArquitecturaSoftware"]="(?i)(arquitectura.*(?:de.*)?software|software.*architecture|dise[ñn]o.*de.*software|patrones.*de.*dise[ñn]o)"
    ["ArquitecturaEmpresarial"]="(?i)(arquitectura.*empresarial|enterprise.*architecture)"
    ["SeguridadInformatica"]="(?i)(seguridad|ciberseguridad|cyber.*security|privacy|privacidad|hacking)"
    ["Metodologias"]="(?i)(scrum|prince2|rup|agil|metodolog[ií]a|method|kanban|extreme.*programming|xp|m[ée]todo|t[ée]cnica)"
    ["MetodologiasAgiles"]="(?i)(scrum|kanban|agile|xp|extreme.*programming|lean|sprint)"
    ["MetodosTecnicasInvestigacion"]="(?i)(m[ée]todo.*experimental|t[ée]cnicas.*de.*investigaci[óo]n|metodolog[ií]a.*de.*investigaci[óo]n|investigaci[óo]n.*cient[ií]fica)"
    ["Estadistica"]="(?i)(estad[ií]stica|probabilidad|probability|data.*science|ciencia.*de.*datos)"
    ["Programacion"]="(?i)(programaci[óo]n|javascript|python|concurrent|parallel|java|c\+\+|ruby|php|coding)"
    ["DesarrolloWeb"]="(?i)(desarrollo.*web|web.*development|html|css|javascript|php|web3)"
    ["Redes"]="(?i)(redes|sistemas.*distribuidos|networking|network|cloud|nube|virtualizaci[óo]n|rfc)"
    ["UML_Modelado"]="(?i)(uml|modelado|model(?:ling)?|design|dise[ñn]o|diagram)"
    ["SysML"]="(?i)(sysml|systems.*modeling)"
    ["GestionProyectos"]="(?i)(gesti[óo]n.*(?:de.*)?proyectos|project.*management|administraci[óo]n.*de.*proyectos|pmbok)"
    ["PlanificacionEstrategia"]="(?i)(planificaci[óo]n.*estrat[ée]gica|plan.*de.*negocios|estrategia.*empresarial|business.*plan)"
    ["InformaticaGeneral"]="(?i)(inform[áa]tica|computaci[óo]n|computing|ciencias.*de.*la.*computaci[óo]n)"
    ["Psicologia_Neurociencia"]="(?i)(psicolog[ií]a|neurociencia|brain|cognitive|cerebro|mente)"
    ["Idiomas"]="(?i)(ingl[ée]s|idiomas|language|lengua|idioma)"
    ["ISO_Normativas"]="(?i)(iso|normativas?|standards?|est[áa]ndares)"
    ["CasosEstudio"]="(?i)(caso(?:s)?.*(?:de.*)?estudio|case.*stud(?:y|ies))"
    ["Tesis_TrabajosAcademicos"]="(?i)(tesis|tfg|trabajo.*(?:fin.*de.*)?grado|investigaci[óo]n|proyecto|documento|informe)"
    ["AWS"]="(?i)(aws|amazon.*web.*services)"
    ["Empresarial"]="(?i)(business|negocio|empresa|management|administraci[óo]n|corporativo)"
    ["IngenieriaIndustrial"]="(?i)(ingenier[ií]a.*industrial|industrial.*engineering)"
    ["IoT"]="(?i)(iot|internet.*of.*things|internet.*de.*las.*cosas)"
    ["TecnologiasEmergentes"]="(?i)(tecnolog[ií]as.*emergentes|emerging.*technologies|digital.*twin)"
    ["AprendizajeAutomatico_PLN"]="(?i)(aprendizaje.*autom[áa]tico|machine.*learning|procesamiento.*de.*lenguaje.*natural|nlp|natural.*language.*processing)"
    ["GestionConocimiento"]="(?i)(gesti[óo]n.*del.*conocimiento|knowledge.*management|business.*intelligence)"
    ["FisicaCosmologia"]="(?i)(f[ií]sica|cosmolog[ií]a|big.*bang|agujeros.*negros|stephen.*hawking)"
    ["SistemasEmbebidos"]="(?i)(sistemas?.*embebidos?|embedded.*systems?|real.*time.*systems?|tiempo.*real)"
    ["AnalisisDatos"]="(?i)(an[áa]lisis.*(?:de.*)?datos|data.*mining|data.*analytics|miner[ií]a.*de.*datos|data.*science)"
    ["SistemasInformacion"]="(?i)(sistemas?.*(?:de.*)?informaci[óo]n|information.*systems?)"
    ["Computacion"]="(?i)(computaci[óo]n|computing|computer|ordenador)"
    ["MetodologiasDesarrollo"]="(?i)(metodolog[ií]a.*de.*desarrollo|software.*development.*methodology|sdlc)"
    ["CalidadSoftware"]="(?i)(calidad.*de.*software|software.*quality|testing|pruebas.*de.*software|evaluaci[óo]n|report)"
    ["BaseDatos"]="(?i)(base.*de.*datos|database|sql|nosql)"
    ["IntegracionSistemas"]="(?i)(integraci[óo]n.*de.*sistemas|systems.*integration|middleware)"
    ["DesarrolloAgil"]="(?i)(desarrollo.*[áa]gil|agile.*development|scrum|kanban|extreme.*programming)"
    ["GestionConfiguracion"]="(?i)(gesti[óo]n.*de.*configuraci[óo]n|configuration.*management|version.*control)"
    ["MejoraProcesos"]="(?i)(mejora.*de.*procesos|process.*improvement|six.*sigma|lean)"
    ["DocumentosTecnicos"]="(?i)(proyecto.*para.*la.*atenci[óo]n|ejecuci[óo]n.*de.*acciones|declaratoria|violencia.*de.*g[ée]nero)"
    ["RecursosEducativos"]="(?i)(pf_l1is|curso|clase|lecci[óo]n|material.*educativo)"
    ["HistoriaComputacion"]="(?i)(historia.*computaci[óo]n|dijkstra|pioneros.*inform[áa]tica)"
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
        original_filename="$filename"
        moved=false
        
        for dir in "${!categories[@]}"; do
            if echo "$filename" | grep -Piq "${categories[$dir]}"; then
                # Añadir identificador si el archivo ya existe en la categoría
                counter=1
                while [ -f "$base_dir/$dir/$filename" ]; do
                    name="${filename%.*}"
                    ext="${filename##*.}"
                    filename="${name}_${counter}.${ext}"
                    ((counter++))
                done
                
                mv "$file" "$base_dir/$dir/$filename"
                echo "MOVIDO: $original_filename a $dir como $filename" >> "$log_file"
                moved=true
                break
            fi
        done
        
        if ! $moved; then
            # Si no se ha movido, moverlo a la categoría que más se ajuste
            best_match=""
            max_score=0
            for dir in "${!categories[@]}"; do
                score=$(echo "$filename" | grep -oP "${categories[$dir]}" | wc -l)
                if (( score > max_score )); then
                    max_score=$score
                    best_match=$dir
                fi
            done
            
            if [ -n "$best_match" ]; then
                # Añadir identificador si el archivo ya existe en la mejor categoría
                counter=1
                while [ -f "$base_dir/$best_match/$filename" ]; do
                    name="${filename%.*}"
                    ext="${filename##*.}"
                    filename="${name}_${counter}.${ext}"
                    ((counter++))
                done
                
                mv "$file" "$base_dir/$best_match/$filename"
                echo "MOVIDO (mejor coincidencia): $original_filename a $best_match como $filename" >> "$log_file"
            else
                echo "ERROR: No se pudo clasificar $filename" >> "$log_file"
            fi
        fi
    done
    
    echo "Organización completada. Revisa $log_file para detalles."
}

# Función principal
main() {
    local target_dir="$1"

    if [ -z "$target_dir" ]; then
        echo "Uso: $0 <directorio>"
        return 1
    fi

    if [ ! -d "$target_dir" ]; then
        echo "El directorio $target_dir no existe."
        return 1
    fi

    create_directories "$target_dir"
    move_files "$target_dir"
}

# Llamar a la función principal con el argumento pasado al script
main "$1"