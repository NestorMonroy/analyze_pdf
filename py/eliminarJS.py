import io
from pdfminer.pdfinterp import PDFResourceManager, PDFPageInterpreter
from pdfminer.converter import TextConverter
from pdfminer.layout import LAParams
from pdfminer.pdfpage import PDFPage
from PyPDF2 import PdfReader, PdfWriter

def extract_text(pdf_path):
    resource_manager = PDFResourceManager()
    fake_file_handle = io.StringIO()
    converter = TextConverter(resource_manager, fake_file_handle, laparams=LAParams())
    page_interpreter = PDFPageInterpreter(resource_manager, converter)
    
    with open(pdf_path, 'rb') as fh:
        for page in PDFPage.get_pages(fh, caching=True, check_extractable=True):
            page_interpreter.process_page(page)
        
    text = fake_file_handle.getvalue()
    converter.close()
    fake_file_handle.close()
    
    return text

def remove_javascript(input_pdf, output_pdf):
    reader = PdfReader(input_pdf)
    writer = PdfWriter()
    
    for page in reader.pages:
        if "/JS" in page or "/JavaScript" in page:
            page.pop('/JS', None)
            page.pop('/JavaScript', None)
        writer.add_page(page)
    
    with open(output_pdf, "wb") as f:
        writer.write(f)

def analyze_and_remove_js(input_pdf, output_pdf):
    # Extraer y analizar el contenido
    content = extract_text(input_pdf)
    if "JavaScript" in content or "js" in content.lower():
        print(f"JavaScript detectado en {input_pdf}")
        print("Procediendo a eliminar JavaScript...")
        remove_javascript(input_pdf, output_pdf)
        print(f"PDF sin JavaScript guardado como {output_pdf}")
    else:
        print(f"No se detectó JavaScript en {input_pdf}")

# Uso
input_pdf = "/home/kali/Documents/pdf/procesos-bpmn-1.pdf"
output_pdf = "/home/kali/Documents/pdf/procesos-bpmn-2.pdf"
analyze_and_remove_js(input_pdf, output_pdf)
