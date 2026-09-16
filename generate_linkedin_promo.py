import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

def create_linkedin_promo():
    # Paths
    base_dir = "/Users/yonesh/.gemini/antigravity-ide/brain/37cc0142-3557-4ee9-930e-729601915c0f"
    app_store_path = os.path.join(base_dir, ".user_uploaded/media_1788324833364.png")
    app_ui_path = os.path.join(base_dir, ".user_uploaded/media_1788325680191.png")
    output_path = "/Users/yonesh/Projects/Player/linkedin_promo.png"

    # LinkedIn post size (1200x628 or 1080x1080). We'll use 1200x628.
    width, height = 1200, 628
    
    # Create background (dark gradient)
    img = Image.new('RGBA', (width, height), color=(20, 10, 30, 255))
    draw = ImageDraw.Draw(img)
    
    # Simple linear gradient
    for y in range(height):
        r = int(20 + (30 * y / height))
        g = int(10 + (10 * y / height))
        b = int(30 + (50 * y / height))
        draw.line([(0, y), (width, y)], fill=(r, g, b, 255))

    # Add some glow/accent circles
    draw.ellipse((-200, -200, 400, 400), fill=(80, 20, 100))
    draw.ellipse((width-300, height-200, width+100, height+200), fill=(40, 10, 60))
    img = img.filter(ImageFilter.GaussianBlur(100))
    draw = ImageDraw.Draw(img)

    try:
        # Load screenshots
        app_store_img = Image.open(app_store_path).convert("RGBA")
        app_ui_img = Image.open(app_ui_path).convert("RGBA")
        
        # Resize screenshots
        # App store screenshot
        as_ratio = app_store_img.width / app_store_img.height
        as_new_height = 400
        as_new_width = int(as_new_height * as_ratio)
        app_store_img = app_store_img.resize((as_new_width, as_new_height), Image.Resampling.LANCZOS)
        
        # UI screenshot
        ui_ratio = app_ui_img.width / app_ui_img.height
        ui_new_height = 450
        ui_new_width = int(ui_new_height * ui_ratio)
        app_ui_img = app_ui_img.resize((ui_new_width, ui_new_height), Image.Resampling.LANCZOS)
        
        # Function to add drop shadow
        def add_shadow(image, offset=(0, 20), radius=20, border=50):
            shadow = Image.new('RGBA', (image.width + border*2, image.height + border*2), (0, 0, 0, 0))
            shadow_draw = ImageDraw.Draw(shadow)
            shadow_draw.rectangle([border, border, image.width+border, image.height+border], fill=(0, 0, 0, 150))
            shadow = shadow.filter(ImageFilter.GaussianBlur(radius))
            
            # Composite original image over shadow
            result = Image.new('RGBA', shadow.size)
            result.alpha_composite(shadow, (offset[0], offset[1]))
            result.alpha_composite(image, (border, border))
            return result, border

        app_store_with_shadow, as_border = add_shadow(app_store_img)
        app_ui_with_shadow, ui_border = add_shadow(app_ui_img)
        
        # Paste them
        # App store on the left
        as_x = 50 - as_border
        as_y = height // 2 - app_store_with_shadow.height // 2 + 50
        img.alpha_composite(app_store_with_shadow, (as_x, as_y))
        
        # UI on the right, slightly overlapping
        ui_x = width - ui_new_width - 50 - ui_border
        ui_y = height // 2 - app_ui_with_shadow.height // 2 + 50
        img.alpha_composite(app_ui_with_shadow, (ui_x, ui_y))
        
    except Exception as e:
        print(f"Error loading/processing images: {e}")

    # Add text
    try:
        font_large = ImageFont.truetype("/System/Library/Fonts/HelveticaNeue.ttc", 60)
        font_medium = ImageFont.truetype("/System/Library/Fonts/HelveticaNeue.ttc", 30)
    except:
        font_large = ImageFont.load_default()
        font_medium = ImageFont.load_default()

    title = "Top 25 on the Mac App Store! 🚀"
    subtitle = "YM Pro: The Bit-Perfect FLAC Player for macOS"
    
    # Text positioning
    draw.text((width//2, 60), title, font=font_large, fill=(255, 255, 255), anchor="mt")
    draw.text((width//2, 140), subtitle, font=font_medium, fill=(200, 200, 200), anchor="mt")
    
    # Save
    img.save(output_path)
    print(f"Saved LinkedIn promo image to {output_path}")

if __name__ == "__main__":
    create_linkedin_promo()
