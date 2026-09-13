import os
import re

def process_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # Replacements
    content = content.replace('.foregroundStyle(.white)', '.foregroundStyle(.primary)')
    content = content.replace('.foregroundColor(.white)', '.foregroundColor(.primary)')
    content = content.replace('.foregroundStyle(Color.white)', '.foregroundStyle(Color.primary)')
    content = content.replace('.foregroundColor(Color.white)', '.foregroundColor(Color.primary)')
    
    # Opacities
    content = content.replace('.white.opacity(', '.primary.opacity(')
    content = content.replace('Color.white.opacity(', 'Color.primary.opacity(')
    
    # Black opacities (usually for shadows or backgrounds)
    # Actually, .black.opacity for shadows should remain black in light mode.
    # But for backgrounds, Color.black.opacity(0.15) should become Color.primary.opacity(0.15)
    # Let's just do Color.black.opacity -> Color.primary.opacity for now, we can tweak shadows later.
    content = content.replace('Color.black.opacity(', 'Color.primary.opacity(')
    # Be careful with raw .black.opacity as it's often used in shadows: shadow(color: .black.opacity(0.3))
    # We should NOT replace .black.opacity in shadows.
    # So I will only replace Color.black.opacity
    
    with open(filepath, 'w') as f:
        f.write(content)

views_dir = '/Users/yonesh/Projects/Player/ytsplayer/Views'
for root, _, files in os.walk(views_dir):
    for file in files:
        if file.endswith('.swift'):
            process_file(os.path.join(root, file))

print("Done")
