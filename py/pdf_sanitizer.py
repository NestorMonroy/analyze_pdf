import os
import tempfile
import argparse
from pdf2image import convert_from_path
from reportlab.pdfgen import canvas
from reportlab.lib.units import inch
import sys
import time

def print_progress_bar(iteration, total, prefix='', suffix='', decimals=1, length=50, fill='█', print_end="\r"):
    """
    Call in a loop to create terminal progress bar
    """
    percent = ("{0:." + str(decimals) + "f}").format(100 * (iteration / float(total)))
    filled_length = int(length * iteration // total)
    bar = fill * filled_length + '-' * (length - filled_length)
    print(f'\r{prefix} |{bar}| {percent}% {suffix}', end=print_end)
    if iteration == total: 
        print()

def print_message(message):
    """
    Print formatted messages
    """
    print(f"\n[INFO] {message}")

def print_error(message):
    """
    Print formatted error messages
    """
    print(f"\n[ERROR] {message}", file=sys.stderr)

def sanitize_pdf(input_pdf, output_pdf):
    try:
        with tempfile.TemporaryDirectory() as temp_dir:
            print_message(f"Convirtiendo PDF a imágenes: {input_pdf}")
            images = convert_from_path(input_pdf, dpi=300, output_folder=temp_dir)
            
            print_message(f"Creando nuevo PDF 'limpio': {output_pdf}")
            c = canvas.Canvas(output_pdf, pagesize=(8.5*inch, 11*inch))
            
            for i, image in enumerate(images):
                img_path = os.path.join(temp_dir, f'page_{i}.jpg')
                image.save(img_path, 'JPEG')
                
                c.setPageSize((image.width, image.height))
                c.drawImage(img_path, 0, 0, width=image.width, height=image.height)
                c.showPage()
                
                print_progress_bar(i + 1, len(images), prefix='Progreso:', suffix='Completado', length=50)
            
            c.save()
        
        print_message(f"PDF 'limpio' creado: {output_pdf}")
        return True
    except Exception as e:
        print_error(f"Error al procesar {input_pdf}: {str(e)}")
        return False

def main():
    parser = argparse.ArgumentParser(description='Sanitize multiple PDF files.')
    parser.add_argument('pdfs', nargs='+', help='PDF files to sanitize')
    parser.add_argument('-o', '--output_dir', default='sanitized', help='Output directory for sanitized PDFs')
    args = parser.parse_args()

    if not os.path.exists(args.output_dir):
        os.makedirs(args.output_dir)

    total_pdfs = len(args.pdfs)
    successful = 0

    for i, pdf in enumerate(args.pdfs):
        print_message(f"Procesando PDF {i+1} de {total_pdfs}: {pdf}")
        output_pdf = os.path.join(args.output_dir, f"sanitized_{os.path.basename(pdf)}")
        
        if sanitize_pdf(pdf, output_pdf):
            successful += 1
        
        print_progress_bar(i + 1, total_pdfs, prefix='Progreso total:', suffix='Completado', length=50)

    print_message(f"Proceso completado. {successful} de {total_pdfs} PDFs sanitizados exitosamente.")

if __name__ == "__main__":
    main()