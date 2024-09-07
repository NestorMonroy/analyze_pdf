#!/usr/bin/env python3

import os
import sys
import subprocess
import logging
from PyPDF2 import PdfReader, PdfWriter

logging.basicConfig(level=logging.INFO, format='[%(asctime)s] %(message)s', datefmt='%Y-%m-%d %H:%M:%S')

def remove_js_and_aa(input_file, output_file):
    logging.info(f"Procesando {input_file}")
    
    reader = PdfReader(input_file)
    writer = PdfWriter()

    for page in reader.pages:
        writer.add_page(page)

    # Eliminar JavaScript y Acciones Automáticas
    writer.remove_links()
    for page in writer.pages:
        if "/AA" in page:
            del page["/AA"]
        if "/Annots" in page:
            annotations = page["/Annots"]
            for annotation in annotations:
                if "/A" in annotation:
                    del annotation["/A"]

    # Eliminar JavaScript y Acciones del catálogo del documento
    if "/Names" in writer._root_object:
        del writer._root_object["/Names"]
    if "/OpenAction" in writer._root_object:
        del writer._root_object["/OpenAction"]
    if "/AA" in writer._root_object:
        del writer._root_object["/AA"]

    with open(output_file, 'wb') as f:
        writer.write(f)

    logging.info(f"PDF limpio guardado como {output_file}")

def sanitize_with_qpdf(input_file, output_file):
    logging.info(f"Sanitizando {input_file} con qpdf")
    try:
        subprocess.run([
            "qpdf", "--linearize", "--object-streams=disable",
            "--remove-unreferenced-resources=yes",
            "--qdf", "--reformat-objects", "--compress-streams=n",
            input_file, output_file
        ], check=True, capture_output=True, text=True)
        logging.info("Sanitización con qpdf completada")
    except subprocess.CalledProcessError as e:
        logging.error(f"Error al sanitizar con qpdf: {e.stderr}")
        return False
    return True

def clean_pdf(input_file):
    base_name = os.path.splitext(input_file)[0]
    temp_file = f"{base_name}_temp.pdf"
    output_file = f"{base_name}_limpio.pdf"

    # Paso 1: Remover JS y AA con PyPDF2
    remove_js_and_aa(input_file, temp_file)

    # Paso 2: Sanitizar con qpdf
    if sanitize_with_qpdf(temp_file, output_file):
        os.remove(temp_file)
    else:
        logging.warning("Usando el resultado de PyPDF2 como salida final")
        os.rename(temp_file, output_file)

    logging.info("Proceso de limpieza completado")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Uso: {sys.argv[0]} archivo1.pdf [archivo2.pdf ...]")
        sys.exit(1)

    for file in sys.argv[1:]:
        if os.path.isfile(file) and file.lower().endswith('.pdf'):
            clean_pdf(file)
        elif not os.path.isfile(file):
            logging.error(f"Error: El archivo {file} no existe.")
        else:
            logging.error(f"Error: {file} no es un archivo PDF.")