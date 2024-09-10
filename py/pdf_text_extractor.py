import io
from pdfminer.high_level import extract_text
import re

def extract_and_analyze_pdf(pdf_path):
    print(f"Analizando: {pdf_path}")
    
    # Extraer todo el texto del PDF
    text = extract_text(pdf_path)
    
    # Buscar patrones de JavaScript
    js_patterns = [
        r'function\s*\w*\s*\(',
        r'var\s+\w+\s*=',
        r'\.indexOf\(',
        r'\.substring\(',
        r'eval\(',
        r'unescape\(',
        r'/JavaScript',
        r'/JS',
    ]
    
    print("Contenido potencialmente relacionado con JavaScript:")
    for pattern in js_patterns:
        matches = re.finditer(pattern, text, re.IGNORECASE | re.MULTILINE)
        for match in matches:
            start = max(0, match.start() - 50)
            end = min(len(text), match.end() + 50)
            print(f"- ...{text[start:end]}...")
    
    print("\nPrimeros 500 caracteres del contenido extraído:")
    print(text[:500])

# Uso
pdf_path = "/home/kali/Documents/pdf/AC-1.pdf"
extract_and_analyze_pdf(pdf_path)
