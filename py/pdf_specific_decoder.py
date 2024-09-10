import re
import zlib
import base64
from PyPDF2 import PdfReader

def decode_base64(data):
    try:
        return base64.b64decode(data).decode('utf-8', errors='ignore')
    except:
        return None

def decode_hex(data):
    try:
        return bytes.fromhex(data).decode('utf-8', errors='ignore')
    except:
        return None

def decompress_flate(data):
    try:
        return zlib.decompress(data).decode('utf-8', errors='ignore')
    except:
        return None

def search_and_decode_specific(pdf_path):
    with open(pdf_path, 'rb') as file:
        content = file.read()

    # Buscar patrones específicos
    patterns = [b'/JS>O', b'/jS"', b"g'/jS"]
    for pattern in patterns:
        indexes = [m.start() for m in re.finditer(re.escape(pattern), content)]
        for index in indexes:
            print(f"Found pattern {pattern} at position {index}")
            context = content[max(0, index-50):min(len(content), index+50)]
            print(f"Context: {context}")
            
            # Intentar decodificar el contexto
            decoded = decode_base64(context) or decode_hex(context) or decompress_flate(context)
            if decoded:
                print(f"Decoded context: {decoded}")
            else:
                print("Unable to decode context")
            print()

    # Buscar en objetos del PDF
    reader = PdfReader(pdf_path)
    for obj in reader.resolved_objects.values():
        if isinstance(obj, dict):
            for key, value in obj.items():
                if isinstance(value, bytes) and any(pattern in value for pattern in patterns):
                    print(f"Found suspicious content in object {key}:")
                    print(f"Raw: {value[:100]}...")  # Print first 100 bytes
                    decoded = decode_base64(value) or decode_hex(value) or decompress_flate(value)
                    if decoded:
                        print(f"Decoded: {decoded[:100]}...")  # Print first 100 chars
                    else:
                        print("Unable to decode content")
                    print()

print("Searching for and attempting to decode specific patterns...")
search_and_decode_specific("/home/kali/Documents/pdf/AC-1.pdf")
