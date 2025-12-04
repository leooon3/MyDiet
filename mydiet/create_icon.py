from PIL import Image, ImageDraw

def create_logo():
    # Crea uno sfondo Verde Foresta (1024x1024 per alta risoluzione)
    size = 1024
    background_color = '#2E7D32' # Verde dell'App
    accent_color = '#E65100'     # Arancione
    
    img = Image.new('RGB', (size, size), color=background_color)
    draw = ImageDraw.Draw(img)
    
    # Disegna un cerchio arancione al centro (stile "Scan Button")
    margin = 200
    draw.ellipse(
        [margin, margin, size-margin, size-margin], 
        fill=accent_color, 
        outline='white', 
        width=40
    )
    
    # Disegna una "spunta" bianca stilizzata al centro
    # Coordinate per la spunta
    check_points = [
        (350, 512), # Sinistra
        (480, 650), # Basso
        (700, 350)  # Destra (Alto)
    ]
    draw.line(check_points, fill="white", width=60, joint="curve")

    # Salva
    img.save('icon.png')
    print("✅ Icona 'icon.png' generata con successo!")

if __name__ == "__main__":
    create_logo()