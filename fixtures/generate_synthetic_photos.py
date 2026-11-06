#!/usr/bin/env python3
"""Generate deterministic, original CC0-like fixtures from primitives (no real people).
Run: python3 fixtures/generate_synthetic_photos.py --out /tmp/cleanslate-fixtures --scenes 20
Requires Pillow. These are *mock* image cases, NOT representative human accuracy data.
"""
import argparse
import csv
import hashlib
from pathlib import Path
from PIL import Image, ImageDraw, ImageEnhance

CANVAS = (320, 224)

def scene_image(index: int, *, sign_shift: int=0, expression: str="smile", omit_right: bool=False) -> Image.Image:
    bg = (218 - (index % 5) * 9, 231 - (index % 7) * 6, 241 - (index % 3) * 10)
    img = Image.new("RGB", CANVAS, bg)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 174, 320, 224), fill=(98, 162, 114))
    d.rectangle((14, 12, 130, 52), fill=(255, 252, 235), outline=(34, 38, 47), width=2)
    d.text((21, 22), f"EVENT {index:02d}-{123 + index + sign_shift}", fill=(21, 31, 42))
    def character(x, color, face):
        d.ellipse((x, 61, x+59, 121), fill=(239, 192, 146), outline=(60, 55, 50), width=3)
        d.ellipse((x+13, 83, x+17, 87), fill=(44, 44, 44))
        d.ellipse((x+40, 83, x+44, 87), fill=(44, 44, 44))
        if face == 'smile': d.arc((x+17, 89, x+44, 112), 12, 166, fill=(91, 43, 38), width=3)
        elif face == 'neutral': d.line((x+20, 105, x+40, 105), fill=(91, 43, 38), width=3)
        else: d.arc((x+17, 100, x+44, 120), 190, 349, fill=(91, 43, 38), width=3)
        d.rectangle((x+8, 121, x+53, 172), fill=color, outline=(50, 50, 50), width=2)
    character(98, (40, 98 + index % 80, 180), 'smile')
    if not omit_right: character(177, (194, 64 + index % 50, 88), expression)
    d.ellipse((261, 139, 295, 173), fill=(245, 194, 39), outline=(32, 32, 32), width=3)
    return img

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def generate(out: Path, scenes: int=20):
    out.mkdir(parents=True, exist_ok=True)
    rows=[]
    for i in range(scenes):
        group = f"scene_{i:03d}"
        folder = out/group
        folder.mkdir(parents=True, exist_ok=True)
        base = scene_image(i)
        variants = [
            ('base', 'png', 'reference', base),
            ('exact_copy', 'png', 'exact_file', base),
            ('recompressed', 'jpg', 'visually_redundant_review', base),
            ('brightness', 'png', 'visually_redundant_review', ImageEnhance.Brightness(base).enhance(1.08)),
            ('small_crop', 'png', 'unknown_review', base.crop((8, 4, 304, 219)).resize(CANVAS)),
            ('sign_changed', 'png', 'unique_text', scene_image(i, sign_shift=1)),
            ('expression_changed', 'png', 'unique_expression', scene_image(i, expression='neutral')),
            ('subject_missing', 'png', 'unique_subject', scene_image(i, omit_right=True)),
        ]
        for j,(name,ext,label,image) in enumerate(variants):
            path=folder/f'{name}.{ext}'
            if name == 'exact_copy':
                # byte-identical, not re-encoded
                path.write_bytes((folder/'base.png').read_bytes())
            elif ext=='jpg':
                image.save(path, 'JPEG', quality=88, subsampling=0, optimize=False)
            else:
                image.save(path, 'PNG', optimize=False)
            rows.append({'asset_id': f'{group}/{path.name}', 'scene_id': group,
                         'variant': name, 'relation_to_base': label,
                         'is_native_burst_simulation': 'true', 'timestamp_offset_ms': str(j*180),
                         'protected': 'false', 'sha256': sha(path)})
    with (out/'manifest.csv').open('w', newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]))
        w.writeheader(); w.writerows(rows)
    (out/'README.txt').write_text('Deterministic synthetic photo test fixtures from Pillow primitives. No real faces or copyrighted photographs. Semantic ground truth is authored. NOT an ML evaluation result.\n')
    return rows

if __name__=='__main__':
    ap=argparse.ArgumentParser()
    ap.add_argument('--out',type=Path,required=True)
    ap.add_argument('--scenes',type=int,default=20)
    args=ap.parse_args()
    rows=generate(args.out, args.scenes)
    print(f'Generated {len(rows)} synthetic image fixtures in {args.out}.')
