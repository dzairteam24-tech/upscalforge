# Art: 3D models

- `concepts/`: الرسومات 2D (من ChatGPT)
- `blender/cubelings.py`: سكريبت Blender يبني المخلوقات من spec، يخرج render و ملفات 3D
- `renders/`: صور render باش نقارنو مع الرسومات
- `models/`: ملفات `.fbx` و `.glb` لـ Roblox، وكل موديل معاه palette صغيرة (الألوان)

## كيفاش تبني موديل

```
python art/blender/cubelings.py Kitty
```
يحتاج Python فيه `bpy` (Blender 4.2) و `pillow`. مخلوق جديد: زيد spec في `SPECIES`.

## كيفاش تدخلو لـ Roblox Studio

1. **Home ← Import 3D** (ولا File ← Import 3D) واختار `models/Kitty.glb` (ولا `.fbx`)
2. في نافذة الـ import خلي **Import only as a model** و الـ texture تتدخل وحدها (هي داخل الملف)
3. يخرج Model فيه MeshPart واحد. حجمو: الجسم 2 × 2 × 1.9 studs. إذا حبيت أكبر بدّل الـ Scale في الـ import
4. الوجه يشوف لـ -Z (القدام تاع Roblox)

كل الموديل mesh واحد (~3300 مثلث) و texture وحدة صغيرة، يعني خفيف على الموبايل.

## صفحة المعاينة 3D (للتيليفون)

`python art/viewer/build.py Kitty Kitty-3d.html 4,864` يصنع صفحة HTML فيها الموديل يدور، يرمّش ويقفز،
والـ variants حيين: Golden (ذهب يلمع)، Crystal (جليد)، Lava (حجرة فيها شقوق تشعل)، Neon (يضوي)، Pixel (مربعات تبدّل اللون).
هذا معاينة برك: في اللعبة لازم نديرو نفس الستيل بـ SurfaceAppearance و particles تاع Roblox.

## كل المخلوقات (40)

`renders/all_creatures.jpg`: كل المناطق في صورة وحدة. التصاميم في `blender/species_zoo.py`، والقطع (ذنين، قرون، جوانح، ذيول، كلاليب...) في `blender/cubelings.py`.

- منطقة كاملة: `python art/blender/cubelings.py zone 3`
- معاينة سريعة (الزاوية 3/4 برك): `FAST=1 python art/blender/cubelings.py zone 3`
- مخلوقات بالاسم: `python art/blender/cubelings.py Bee "Ice Fox"`
