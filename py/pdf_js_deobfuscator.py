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

def unescape_js(data):
    def replace(match):
        return chr(int(match.group(1), 16))
    return re.sub(r'%([0-9a-fA-F]{2})', replace, data)

def search_obfuscated_js(pdf_path):
    with open(pdf_path, 'rb') as file:
        content = file.read()

    # Patrones de ofuscación comunes
    patterns = [
        rb'eval\(.*\)',
        rb'unescape\(.*\)',
        rb'String\.fromCharCode\(.*\)',
        rb'\\x[0-9a-fA-F]{2}',
        rb'%[0-9a-fA-F]{2}',
        rb'/JS',
        rb'/JavaScript'
    ]

    for pattern in patterns:
        matches = re.finditer(pattern, content)
        for match in matches:
            print(f"Found potential obfuscated JS at position {match.start()}:")
            context = content[max(0, match.start()-50):min(len(content), match.end()+50)]
            print(f"Context: {context}")
            
            # Intentar deobfuscar
            deobfuscated = unescape_js(context.decode('utf-8', errors='ignore'))
            if deobfuscated != context.decode('utf-8', errors='ignore'):
                print(f"Deobfuscated: {deobfuscated}")
            else:
                print("Unable to deobfuscate")
            print()

    # Buscar en objetos del PDF
    reader = PdfReader(pdf_path)
    for obj in reader.resolved_objects.values():
        if isinstance(obj, dict):
            for key, value in obj.items():
                if isinstance(value, str) and any(re.search(pattern, value.encode()) for pattern in patterns):
                    print(f"Found potential obfuscated JS in object {key}:")
                    print(f"Raw: {value[:100]}...")  # Print first 100 chars
                    deobfuscated = unescape_js(value)
                    if deobfuscated != value:
                        print(f"Deobfuscated: {deobfuscated[:100]}...")  # Print first 100 chars
                    else:
                        print("Unable to deobfuscate")
                    print()

print("Searching for and attempting to deobfuscate JavaScript...")
search_obfuscated_js("/home/kali/Documents/pdf/AC-1.pdf")
