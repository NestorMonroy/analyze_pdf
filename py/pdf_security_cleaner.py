#!/usr/bin/env python3

import os
import sys
import subprocess
import logging
from PyPDF2 import PdfReader, PdfWriter

logging.basicConfig(level=logging.INFO, format='[%(asctime)s] %(message)s', datefmt='%Y-%m-%d %H:%M:%S')

def deep_clean_pdf(input_file, output_file):
    logging.info(f"Limpieza profunda de {input_file}")
    
    reader = PdfReader(input_file)
    writer = PdfWriter()

    for page in reader.pages:
        clean_page = deep_clean_page(page)
        writer.add_page(clean_page)

    # Limpiar el catálogo del documento
    clean_document_catalog(writer)

    with open(output_file, 'wb') as f:
        writer.write(f)

    logging.info(f"PDF limpio guardado como {output_file}")

def deep_clean_page(page):
    # Eliminar todas las anotaciones
    if "/Annots" in page:
        del page["/Annots"]
    
    # Eliminar acciones automáticas de la página
    if "/AA" in page:
        del page["/AA"]
    
    # Eliminar JavaScript incrustado en la página
    if "/JS" in page:
        del page["/JS"]
    
    return page

def clean_document_catalog(writer):
    root = writer._root_object
    keys_to_remove = ["/Names", "/OpenAction", "/AA", "/AcroForm", "/Outlines", "/JavaScript"]
    for key in keys_to_remove:
        if key in root:
            del root[key]

def sanitize_with_qpdf(input_file, output_file):
    logging.info(f"Sanitizando {input_file} con qpdf")
    try:
        subprocess.run([
            "qpdf", "--linearize", "--object-streams=disable",
            "--remove-unreferenced-resources=yes",
            input_file, output_file
        ], check=True, capture_output=True, text=True)
        logging.info("Sanitización con qpdf completada")
    except subprocess.CalledProcessError as e:
        logging.error(f"Error al sanitizar con qpdf: {e.stderr}")
        return False
    return True

def clean_pdf(input_file):
    base_name = os.path.splitext(input_file)[0]
    temp_file1 = f"{base_name}_temp1.pdf"
    temp_file2 = f"{base_name}_temp2.pdf"
    output_file = f"{base_name}_limpio.pdf"

    # Paso 1: Limpieza profunda con PyPDF2
    deep_clean_pdf(input_file, temp_file1)

    # Paso 2: Sanitizar con qpdf
    if sanitize_with_qpdf(temp_file1, temp_file2):
        # Paso 3: Segunda pasada de limpieza profunda
        deep_clean_pdf(temp_file2, output_file)
        os.remove(temp_file1)
        os.remove(temp_file2)
    else:
        logging.warning("Usando el resultado de la primera limpieza como salida final")
        os.rename(temp_file1, output_file)
        if os.path.exists(temp_file2):
            os.remove(temp_file2)

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