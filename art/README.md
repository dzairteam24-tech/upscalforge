# Art: 3D models

- `concepts/`: الرسومات 2D (من ChatGPT)
- `blender/cubelings.py`: سكريبت Blender يبني المخلوقات من spec، يخرج render و ملفات 3D. مخلوقات المنطقة 1 مكتوبين فيه
- `blender/species_zoo.py`: التصاميم تاع المناطق 2 حتى 10 والأسطوريين (`ZONES`، `LEGENDARIES`)
- `renders/`: صورة لكل مخلوق (4 زوايا) باش نقارنو مع الرسومات، و `all_creatures.jpg` و `legendaries.jpg`
- `models/`: **`Cubelings_Roblox.glb` هو اللي تستعملو اللعبة.** والباقي: `.glb` لكل مخلوق (للمعاينة) معاه palette صغيرة (`_palette.png` و `_palette.json`)
- `viewer/`: صفحة معاينة 3D للتيليفون

## الأوامر

يحتاج Python فيه `bpy` (Blender 4.2) و `pillow`.

| الأمر | واش يدير |
|-------|----------|
| `python art/blender/cubelings.py Kitty "Ice Fox"` | مخلوقات بالاسم: render + `.glb` + palette لكل واحد |
| `python art/blender/cubelings.py zone 3` | الـ 4 مخلوقات تاع منطقة، و `renders/zone3_lineup.png` (الزاوية 3/4 جنب لجنب) |
| `python art/blender/cubelings.py legendary` | الـ 10 أسطوريين، و `renders/legendaries_lineup.png` |
| `python art/blender/cubelings.py roblox` | الملف تاع اللعبة: `models/Cubelings_Roblox.glb` و `roblox/shared/Config/CreatureLooks.luau` (شوف تحت) |
| `FAST=1 python art/blender/cubelings.py ...` | الزاوية 3/4 برك (معاينة سريعة) |

- **مخلوق جديد:** زيد spec في `SPECIES` (المنطقة 1 في `cubelings.py`، والباقي في `species_zoo.py`)، والقطع (ذنين، قرون، جوانح، ذيول، كلاليب...) في `cubelings.py`
- **ملفات مؤقتة ما تتحطش في git:** الـ `.fbx`، الـ lineups، وصفحات المعاينة HTML (راهم في `.gitignore`). السكريبت مازال يخرجهم، استعملهم وخليهم عندك

## الموديلات

- **الحجم:** الجسم 2 × 2 × 1.9 studs، والوجه يشوف لـ -Z (القدام تاع Roblox)
- **مخلوق وحدو** (`models/Kitty.glb`): mesh واحد و texture وحدة صغيرة (palette). بين 2.3K و 13K مثلث على حسب القطع، تقريباً 5K في المتوسط (Kitty: 4,864)
- **`Cubelings_Roblox.glb`:** الـ 50 مخلوق (40 + 10 أسطوريين)، كل مخلوق مقسوم لقطع على حسب الدور: `Kitty__body`، `Kitty__eye`... (حوالي 500 قطعة، و ~250K مثلث في المجموع)

## في اللعبة

1. `python art/blender/cubelings.py roblox` يخرج `models/Cubelings_Roblox.glb` و `roblox/shared/Config/CreatureLooks.luau` (اللون العادي تاع كل قطعة)
2. في Studio: **Home ← Import 3D** واختار `models/Cubelings_Roblox.glb`
3. **تجربة سريعة:** سمّي الموديل `CreatureModels` وحطو في **ReplicatedStorage**
4. **باش يبقاو ديما:** **Save to Roblox** وحط الـ ID في `roblox/shared/Config/Art.luau` (`CREATURE_MODELS_ASSET_ID`). `ArtService` يحمّلهم وحدو في `ReplicatedStorage.CreatureModels`

الكود (`roblox/shared/PetModel.luau`) يستنسخ قطع كل مخلوق، يكبّرهم على قد الحجم (Normal/Big/Titan)، ويبدّل الألوان والمواد على حسب الـ variant (مثلاً الأجزاء `glow` تولي Neon). بلا الموديلات، اللعبة ترسم المخلوقات بالمكعبات. التفاصيل في [docs/dev.md](../docs/dev.md#قبل-النشر) (المرحلة 6).

**مهم:** كي تبدّل التصاميم، عاود `roblox` باش `CreatureLooks.luau` يبقى نفس القطع اللي في الـ `.glb`، وعاود الـ import في Studio.

## صفحة المعاينة 3D (للتيليفون)

`python art/viewer/build.py Kitty Kitty-3d.html 4,864` يصنع صفحة HTML فيها الموديل يدور، يرمّش ويقفز،
والـ variants حيين: Golden (ذهب يلمع)، Crystal (جليد)، Lava (حجرة فيها شقوق تشعل)، Neon (يضوي)، Pixel (مربعات تبدّل اللون).
تحتاج `models/<Name>.glb` و `_palette.json` و `concepts/<Name>_small.jpg` (دركا كاينة غير لـ Kitty).
هذا معاينة برك، والصفحة ما تتحطش في git.
