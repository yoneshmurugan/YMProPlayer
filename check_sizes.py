from PIL import Image

base_img_path = "/Users/yonesh/.gemini/antigravity-ide/brain/37cc0142-3557-4ee9-930e-729601915c0f/.user_uploaded/media_1789442867285.jpg"
new_img_path = "/Users/yonesh/.gemini/antigravity-ide/brain/37cc0142-3557-4ee9-930e-729601915c0f/.user_uploaded/media_1789442935369.png"

try:
    base_img = Image.open(base_img_path)
    print(f"Base Image Size: {base_img.width}x{base_img.height}")
    
    new_img = Image.open(new_img_path)
    print(f"New Image Size: {new_img.width}x{new_img.height}")
except Exception as e:
    print(e)
