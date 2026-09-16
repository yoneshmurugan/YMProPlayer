from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os

base_img_path = "/Users/yonesh/.gemini/antigravity-ide/brain/37cc0142-3557-4ee9-930e-729601915c0f/.user_uploaded/media_1789442867285.jpg"
output_path = "/Users/yonesh/.gemini/antigravity-ide/brain/37cc0142-3557-4ee9-930e-729601915c0f/linkedin_promo.jpg"

img = Image.open(base_img_path).convert("RGBA")
draw = ImageDraw.Draw(img)

# 1. Erase "89" in "Top 89 Music App"
# Draw a dark rectangle to completely cover the old text.
# The background is very dark here, so a dark space color will blend okay.
draw.rectangle([40, 260, 480, 380], fill=(15, 18, 30, 255))


# 2. Draw "Top 21 Music App"
try:
    font = ImageFont.truetype("/System/Library/Fonts/HelveticaNeue.ttc", 50)
except:
    font = ImageFont.load_default()

text = "Top 21 Music App"
# Draw text with glow
def draw_glow_text(draw_obj, pos, text, font, fill, glow_color, blur_radius=5):
    # Create a separate image for the glow
    glow_img = Image.new('RGBA', img.size, (0,0,0,0))
    glow_draw = ImageDraw.Draw(glow_img)
    
    # Draw thick text for glow
    for offset in range(1, 4):
        glow_draw.text((pos[0]-offset, pos[1]), text, font=font, fill=glow_color)
        glow_draw.text((pos[0]+offset, pos[1]), text, font=font, fill=glow_color)
        glow_draw.text((pos[0], pos[1]-offset), text, font=font, fill=glow_color)
        glow_draw.text((pos[0], pos[1]+offset), text, font=font, fill=glow_color)
        
    glow_img = glow_img.filter(ImageFilter.GaussianBlur(blur_radius))
    img.alpha_composite(glow_img)
    
    # Draw main text
    draw_obj.text(pos, text, font=font, fill=fill)

draw_glow_text(draw, (50, 280), "Top 21 Music App", font, (200, 255, 200, 255), (50, 255, 50, 150))

# 3. Erase "89" in "CHART No. 89 Music"
# Load the new app store screenshot
new_img_path = "/Users/yonesh/.gemini/antigravity-ide/brain/37cc0142-3557-4ee9-930e-729601915c0f/.user_uploaded/media_1789442935369.png"
new_img = Image.open(new_img_path).convert("RGBA")

# In the new image (1024x654), the "CHART No. 21 Music" is around x=480, y=280
# The row has: 5.0 RATING, 4+ AGE RATING, CHART No. 21 Music, DEVELOPER
# Let's crop the box carefully. Assuming 6 columns of ~170px.
# "CHART No. 21" should be around x=420 to 580, y=280 to 360
chart_crop = new_img.crop((480, 275, 590, 350))

# We paste it over the old "CHART No. 89" box in the base image (1024x571)
# The old box is around x=415, y=410
# First, draw a dark box over the old text to be safe
draw.rectangle([415, 410, 520, 480], fill=(50, 55, 65, 255))
img.paste(chart_crop, (420, 415), chart_crop)

img.convert("RGB").save(output_path)
print(f"Saved to {output_path}")

