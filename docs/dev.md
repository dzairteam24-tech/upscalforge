# البرمجة

اللعبة مكتوبة بـ **Luau**. الملفات تتبنى لـ Roblox بـ **[Rojo](https://rojo.space)**.

## كيفاش تشغل اللعبة

### الطريقة 1: ملف واحد
1. ثبّت [Rojo 7.4](https://github.com/rojo-rbx/rojo/releases).
2. في مجلد المشروع:
   ```
   rojo build default.project.json -o build/Cubelings.rbxlx
   ```
3. افتح `build/Cubelings.rbxlx` في **Roblox Studio** واضغط **Play**.

### الطريقة 2: تعديل مباشر (للمبرمجين)
1. ثبّت plugin تاع Rojo في Studio.
2. شغّل `rojo serve` واضغط **Connect** في Studio.
3. كل تعديل في الملفات يبان في Studio دركا.

### قبل النشر
1. **حفظ البيانات:** في Studio، **Game Settings ← Security ← Enable Studio Access to API Services**. بلا هذا، اللعبة تخدم لكن ما تحفظش، وتكتب تحذير في الـ Output.
2. **منتجات Robux:** صنع الـ Game Pass (VIP) والـ Developer Product (Supporter Title) في Creator Dashboard، وحط الأرقام في `roblox/shared/Config/Products.luau`. كل منتج رقمو 0 يبان "Soon" في المتجر.
3. **التجربة مع لاعبين:** باش تجرب التبادل، في Studio اختار **Test ← Clients and Servers** بـ 2 لاعبين.

## الاختبارات

بـ [Lune](https://github.com/lune-org/lune) 0.8:
```
lune run tests/run.luau           # منطق اللعبة: الفقس، القوة، الدمج، التبادل، بناء المخلوقات
lune run tests/smoke_world.luau   # يبني الخريطة ومصادر العملات بأجزاء Roblox حقيقية
```

فحص الأنواع بـ [luau-lsp](https://github.com/JohnnyMorganz/luau-lsp) 1.50:
```
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau --platform=roblox roblox/
```

## هيكل الكود

```
roblox/
  shared/                  ReplicatedStorage.Shared (السيرفر واللاعب)
    Config/                الأرقام كاملة: الدرجات، الأحجام، العالم 1، المصادر، التطويرات، Robux
    Logic/                 منطق بلا Roblox، يتجرب بـ Lune: القوة، الفقس، المخزن، التبادل
    PetModel.luau          يبني المخلوق المكعب 3D
    Net.luau               أسامي الـ Remotes
  server/                  ServerScriptService.Server
    Main.server.luau       يشغل كلش بالترتيب
    Services/
      DataService          الحفظ مع قفل الجلسة (session lock)
      WorldBuilder         يبني الخريطة: المناطق، الجسور، البوابات، البيض، المدينة
      BreakableService     مصادر العملات
      GameService          حلقة اللعب: الجمع، Combo، Jackpot، المهارات، أرباح الغياب
      PetService           الفقس، الفريق، القفل، الحذف، الدمج
      ShopService          تطويرات بالعملات، فتح المناطق، Robux
      TradeService         التبادل
  client/                  StarterPlayerScripts.Client
    Controllers/           حركة المخلوقات، البوابات، الألوان، المؤثرات
    UI/                    الواجهة: HUD، المخلوقات، المتجر، التبادل، البيض
tests/                     اختبارات Lune
```

## واش مبرمج (النسخة الأولى)

- **العالم الأول:** 10 مناطق + المدينة (Hub)، جسور وبوابات تتفتح بالعملات، وخريطة بطريقين
- **رجوع الألوان:** كل منطقة رمادية، وترجعلها الألوان مع الجمع، والنسبة تبان فوق
- **مصادر العملات:** كومة، صندوق، خزنة، وخزنة عملاقة، تتكسر وترجع
- **الجمع:**
  - الفريق يضرب مرة في الثانية، والضغطة تضرب تاني
  - Combo حتى ×5 (ما يخدمش في الوضع التلقائي)
  - Jackpot ×10، وجواهر
  - وضع تلقائي
- **المخلوقات:**
  - 40 نوع، 6 درجات، 3 أحجام، كلهم مكعبات 3D تتبع اللاعب وتنقز حول المصدر
  - العناصر: Lava ×2 في الثلج، وهكذا
- **البيض:**
  - الفرص تبان
  - فقس ×1، ×3، ×8، وتلقائي
  - أول Golden مضمون في الفقسة الخامسة
  - إعلان لكل السيرفر كي يخرج مخلوق نادر
- **مهارات Big و Titan:**
  - المضاعفات الدائمة
  - المهارات اللي تخدم وحدها: صاعقة، موجة، Smash، Stomp، مطر عملات، Boost، بيض مجاني، Clone Army...
- **الفريق:** 6 أماكن، Equip Best، قفل، حذف بالجملة، دمج (5 ← Golden ← Crystal)
- **متجر العملات:** أماكن الفريق، مضاعف العملات، قوة الضغطة، السرعة، المخزن، أرباح الغياب، فقس ×3 و ×8، فقس تلقائي
- **متجر Robux:** VIP (Game Pass) ولقب Supporter (Developer Product)، وما يبيعش لا بيض لا حظ لا عملات
- **التبادل:**
  - طلب وقبول
  - Ready يتقفل 3 ثواني بعد أي تبديل، وشاشة تأكيد
  - السيرفر يعاود يتأكد قبل التبادل
  - المخلوقات المقفولة ما تتبادلش
  - سجل التبادلات
  - تقدر تسكّر الطلبات
- **الحفظ:** DataStore بقفل جلسة، حفظ كل دقيقة وكي يخرج اللاعب، وحماية المشتريات
- **أرباح الغياب**، و **هدية البداية** (3 مخلوقات + 100 عملة)، و **ألقاب** فوق الراس

## واش باقي

- **Big اللي يظهر في العالم وحراس المناطق (Titan):** مهارات "Big يظهر أكثر" ما تخدمش حتى يتبرمجو
- **المغناطيس:** العملات تدخل مباشرة، ولهذا مهارات Magnet ما تخدمش دركا
- **Pixel Rift اليومي**
- **Battle Pass، المهام، مكافأة الدخول**
- **الأدوات:** Cartridges، Elixirs، Keys، Stickers، Gadgets، Rides، Expeditions، Arcade، Reload
- **العوالم 2 حتى 15**
- **إعلانات الفيديو بمكافأة:** متاحة في Roblox بشروط (2,000 زائر في الشهر)
- **Low-end mode**، الأصوات، الموسيقى
- **تصميم الشخصية**

## ملاحظة على التجربة

الكود ما تجربش في Roblox Studio لأن Studio ما يخدمش في البيئة اللي تكتب فيها. اللي تفحص:
- **أنواع Luau:** مقابل Roblox API
- **33 اختبار:** للمنطق
- **بناء المخلوقات والخريطة:** بأجزاء Roblox حقيقية

أول تجربة في Studio ممكن تبين أخطاء صغار.
