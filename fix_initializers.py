import re

with open("ytsplayer/Database/AppDatabase.swift", "r") as f:
    content = f.read()

pattern = re.compile(r'(isFavorite:\s*([$a-z0-9_]+)\["isFavorite"\] \?\? false)')
replacement = r'\1,\n                    genre:            \2["genre"],\n                    composer:         \2["composer"],\n                    comment:          \2["comment"],\n                    publisher:        \2["publisher"],\n                    isrc:             \2["isrc"],\n                    bpm:              \2["bpm"]'

new_content = pattern.sub(replacement, content)

with open("ytsplayer/Database/AppDatabase.swift", "w") as f:
    f.write(new_content)

print("Done")
