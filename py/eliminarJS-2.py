import io
import re
from pdfminer.high_level import extract_text
from PyPDF2 import PdfReader, PdfWriter

def extract_text_with_pdfminer(pdf_path):
    return extract_text(pdf_path)

def check_for_javascript(content):
    # Patrones para detectar JavaScript
    js_patterns = [
        r'/JS\s',
        r'/JavaScript\s',
        r'function\s*\(',
        r'var\s+\w+\s*=',
        r'\.indexOf\(',
        r'\.substring\(',
        r'eval\(',
        r'unescape\('
    ]
    
    for pattern in js_patterns:
        if re.search(pattern, content, re.IGNORECASE):
            return True
    return False

def remove_javascript(input_pdf, output_pdf):
    reader = PdfReader(input_pdf)
    writer = PdfWriter()
    
    js_removed = False
    for page in reader.pages:
        if "/JS" in page or "/JavaScript" in page:
            page.pop('/JS', None)
            page.pop('/JavaScript', None)
            js_removed = True
        writer.add_page(page)
    
    if js_removed:
        with open(output_pdf, "wb") as f:
            writer.write(f)
        print(f"JavaScript removido. PDF guardado como {output_pdf}")
    else:
        print("No se encontraron objetos JavaScript para remover.")

def analyze_and_remove_js(input_pdf, output_pdf):
    print(f"Analizando {input_pdf}...")
    
    # Extraer y analizar el contenido
    content = extract_text_with_pdfminer(input_pdf)
    
    if check_for_javascript(content):
        print("JavaScript detectado. Detalles:")
        # Mostrar las primeras apariciones de JavaScript
        js_lines = [line for line in content.split('\n') if 'javascript' in line.lower() or 'js' in line.lower()]
        for line in js_lines[:5]:  # Mostrar hasta 5 líneas con JavaScript
            print(f"  - {line.strip()}")
        
        print("\nProcediendo a eliminar JavaScript...")
        remove_javascript(input_pdf, output_pdf)
    else:
        print(f"No se detectó JavaScript en {input_pdf}")
        print("Contenido extraído para referencia:")
        print(content[:500] + "...")  # Mostrar los primeros 500 caracteres

# Uso
input_pdf = "input.pdf"
output_pdf = "output_sin_js.pdf"
analyze_and_remove_js(input_pdf, output_pdf)
