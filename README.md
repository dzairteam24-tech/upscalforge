# Upscalforge Games

مجموعة ألعاب للهاتف مصنوعة بـ **Godot 4.3**.

## الألعاب

| اللعبة | الوصف |
|--------|-------|
| Dodge | حرّك المربع بإصبعك وتجنّب المربعات اللي طايحة. السرعة تزيد مع الوقت. |

## التشغيل

1. ثبّت [Godot 4.3](https://godotengine.org/download).
2. افتح Godot ← **Import** ← اختار ملف `project.godot`.
3. اضغط **F5** باش تلعب. الماوس يخدم كيما اللمس.

## التصدير لأندرويد (APK)

1. في Godot: **Editor ← Manage Export Templates ← Download and Install**.
2. ثبّت Android SDK و JDK 17، وحدد المسارات في **Editor Settings ← Export ← Android**.
3. **Project ← Export ← Add… ← Android** ثم **Export Project**.

## إضافة لعبة جديدة

1. اصنع مجلد `scenes/games/<اسم_اللعبة>/` و `scripts/games/<اسم_اللعبة>/`.
2. زيد اللعبة في قائمة `GAMES` في `scripts/main_menu.gd`.
3. استعمل `SaveData.submit_score("<id>", score)` باش تحفظ أحسن نتيجة.

## هيكل المشروع

```
project.godot            إعدادات المشروع (شاشة عمودية 720x1280)
autoload/save_data.gd    حفظ أحسن النتائج
scenes/main_menu.tscn    القائمة الرئيسية
scenes/games/            مشاهد الألعاب
scripts/                 أكواد GDScript
```
