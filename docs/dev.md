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
1. **حفظ البيانات:** في Studio، **Game Settings ← Security ← Enable Studio Access to API Services**. بلا هذا، اللعبة تخدم لكن ما تحفظش، وتكتب تحذير في الـ Output. لوحات الترتيب تاني يحتاجو هذا.
2. **منتجات Robux:** صنعهم في Creator Dashboard وحط الأرقام في `roblox/shared/Config/Products.luau`. كل منتج رقمو 0 يبان "Soon" ولا ما يبانش، و `price` لازم يكون نفس الثمن اللي في Dashboard.
   - **Game Passes:** VIP، Auto Tap، +2 Team Slots، Big Storage، Teleport، Extra Trip
   - **Developer Products:** Coins x2، Power x2، Server Boost، TripSkip، TripDouble، QuestSwap، Supporter Title، Battle Pass Premium، 6 Auras (`Aura_*`) و 4 Hatch effects (`Hatch_*`)
   - **Developer Products للإعلانات:** AdCoins، AdLuck، AdPower، AdEggs، AdElixir، AdTripSkip، AdTripDouble، AdStreak، AdReroll، AdSpin. هذو ما يتباعوش، Roblox يستعملهم باش يعطي مكافأة الفيديو.
3. **الإعلانات:** الفيديو ولوحات الإعلانات (Immersive Ads) يحتاجو اللعبة تكون مؤهلة عند Roblox (صاحبها 13 سنة وأكثر، هوية موثقة، و 2,000 زائر في الشهر)، ويبانو غير للاعبين 13+. لوحات الإعلانات راهم في المدينة (`Workspace.AdBoards`) ويخدمو وحدهم كي تكون مؤهل.
4. **الأصوات:** في `roblox/shared/Config/Sounds.luau`. دركا فيها أصوات Roblox الأساسية، بدّلهم بأصوات من Creator Store، وحط id تاع موسيقى في `MUSIC`.
5. **Codes:** في `roblox/shared/Config/Codes.luau`. زيد كود، والمكافأة، وتاريخ النهاية إذا حبيت. كل لاعب يستعمل الكود مرة وحدة، ويكتبو في Settings. انشر الأكواد في صفحة اللعبة والـ Discord.
6. **المخلوقات 3D:** اللعبة ترسم المخلوقات بالمكعبات حتى تدخل الموديلات 3D مرة وحدة:
   1. افتح اللعبة في Studio ← **Home ← Import 3D** ← اختار `art/models/Cubelings_Roblox.glb` ← Import (فيه الـ 50 مخلوق: 40 + 10 أسطوريين، كل مخلوق مقسوم لقطع `Kitty__body`، `Kitty__eye`...)
   2. **تجربة سريعة:** بدّل اسم الموديل اللي دخل لـ `CreatureModels` وجرّو لـ **ReplicatedStorage**، ومن بعد Play
   3. **باش يبقاو ديما:** كليك يمين على الموديل ← **Save to Roblox** ← انسخ الـ ID وحطو في `roblox/shared/Config/Art.luau` (`CREATURE_MODELS_ASSET_ID`). السيرفر يحمّلهم وحدو في كل مرة، حتى مع ملفات `.rbxlx` جداد
   - إذا بدّلنا التصاميم: `python art/blender/cubelings.py roblox` يعاود يخرج الملف و `Config/CreatureLooks.luau` (لازم يتبدلو مع بعض)، وعاود الـ import. التفاصيل في [art/README.md](../art/README.md)
7. **التجربة مع لاعبين:** باش تجرب التبادل، في Studio اختار **Test ← Clients and Servers** بـ 2 لاعبين.

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
    Config/                الأرقام كاملة: العالم 1، الدرجات، الأحجام، المصادر، التطويرات، الأدوات، Robux، الأحداث...
    Logic/                 منطق بلا Roblox، يتجرب بـ Lune: القوة، الفقس، المخزن، التبادل، الغنائم، الكلان...
    PetModel.luau          يبني المخلوق 3D (من CreatureModels، ولا بالمكعبات)
    Net.luau               أسامي الـ Remotes
  server/                  ServerScriptService.Server
    Main.server.luau       يشغل كلش بالترتيب
    Services/              كل ملف = نظام (شوف تحت)
  client/                  StarterPlayerScripts.Client
    Controllers/           حركة المخلوقات، العالم (البوابات، الألوان، المؤثرات)، الأصوات، الشرح
    UI/                    الواجهة: HUD والنوافذ (المخلوقات، البيض، الحقيبة، المتجر، التبادل، الرحلات، Quests، Clan...)
tests/                     اختبارات Lune
```

**`server/Services/`** (كل ملف يبدا بتعليق يشرح واش يدير):

| المجموعة | الـ Services |
|----------|--------------|
| الأساس | `DataService` (الحفظ بقفل الجلسة)، `State` (حالة اللاعب اللي ما تتحفظش)، `WorldBuilder` (الخريطة والمدينة)، `ArtService` (موديلات المخلوقات 3D) |
| اللعب | `GameService` (حلقة اللعب: الجمع، Combo، Jackpot، المهارات، أرباح الغياب)، `BreakableService` (مصادر العملات)، `PetService` (الفقس، الفريق، القفل، الحذف، الدمج)، `HuntService` (Big والحراس)، `BossService` (World Boss) |
| الأدوات والتقدم | `ItemService` (الإكسيرات، البطاقات، المفاتيح، الملصقات، الأدوات)، `ExpeditionService` (الرحلات)، `ReloadService`، `ProgressionService` (المكافأة اليومية، المهام، Battle Pass، الأشكال، Pixel Rift)، `AchievementService` (Achievements، Rank، Index)، `JourneyService`، `BountyService`، `TutorialService` |
| الأنشطة | `SpinService` (Lucky Spin)، `MinigameService` (Cube Stack)، `FishingService`، `EventService` (الأحداث)، `LiveEventService` (`/live`) |
| الجماعي | `TradeService` (التبادل)، `PlazaService` (Trading Plaza)، `ClanService`، `GiftService` (هدايا الأصحاب)، `LeaderboardService` |
| الربح | `ShopService` (متجر العملات والجواهر، Developer Products)، `MembershipService` (Game Passes و Premium)، `AdsService` (الفيديو بمكافأة)، `RewardService` (المكافآت المشتركة بين الفيديو والـ Robux) |

## واش مبرمج

فهرس الأنظمة اللي راهم في اللعبة. **الأرقام في `roblox/shared/Config/`**، والتصميم في [game-design.md](game-design.md) و [items.md](items.md). هنا غير واش كاين، وتفاصيل البرمجة اللي ماهيش في الوثائق الأخرى.

### العالم واللعب
- **العالم الأول:** 10 مناطق + المدينة (Hub)، جسور وبوابات تتفتح بالعملات، وخريطة بطريقين. حيطان حواف المناطق فيها فتحة في بلاصة كل جسر (اختبار الخريطة يتأكد)
- **رجوع الألوان:** كل منطقة رمادية، وترجعلها الألوان مع الجمع، والنسبة تبان فوق
- **مصادر العملات:** كومة، صندوق، خزنة، خزنة عملاقة. الفريق يضرب، الضغطة تضرب تاني، Combo حتى ×5 (ما يخدمش في Auto)، Jackpot ×10، جواهر، ووضع تلقائي
- **المغناطيس:** مهارات Magnet تخلي الفريق يروح وحدو للمصدر الجاي حتى في الوضع اليدوي (و Combo يبقى)
- **الأنظمة تتفتح بالتدريج** مع المناطق (`Config/Unlocks.luau`، الجدول في [items.md](items.md#0-وقتاش-يتفتح-كل-نظام))، مع إعلان "✨ New!"
- **Pixel Rift:** كل يوم منطقة (نفسها في كل السيرفرات) بعلامة بنفسجية

### المخلوقات والبيض
- **50 نوع** (40 + 10 أسطوريين)، 6 درجات، 3 أحجام. موديلات 3D مقسومة لقطع (ولا مكعبات بلاهم)، يتبعو اللاعب، ينقزو، يرمّشو، يميلو كي يمشيو
- **البيض:** الفرص تبان، فقس ×1/×3/×8 وتلقائي، أول Golden مضمون في الفقسة الخامسة. الحظ في `Logic/EggRoll.luau`
- **★ Legendary Egg** في Pixel Zone بـ 10 أسطوريين، الحظ ما يمسهمش (شوف [game-design.md](game-design.md#الأسطوريين-و-الـ-legendary-egg))
- **مهارات Big و Titan:** المضاعفات الدائمة، والقدرات اللي تخدم وحدها (صاعقة، موجة، Smash، Stomp، مطر عملات، Boost، بيض مجاني، Clone Army...)
- **الفريق:** 6 أماكن (حتى 12)، Equip Best، قفل، حذف بالجملة، Auto-Delete، دمج (5 ← Golden ← Crystal)
- **Big في العالم و حراس المناطق:** الأرقام في `Config/Hunt.luau`. **Pity:** Big مضمون في المحاولة 10، Titan من الحارس مضمون في 500. المخزن العامر ما يتحسبش خسارة
- **إعلانات السيرفر قلال:** غير Titan، Pixel، أسطوري، Jackpot و Server Boost

### الأدوات والتقدم
- **Boosts محفوظة:** تتجمع حتى 4 ساعات وتنقص غير وانت تلعب. الأقوى يتحسب، والأضعف يستنى
- **الإكسيرات، Boost Cards (مع Sets و 3 Loadouts)، المفاتيح (فتح بالجملة)، الملصقات، الأدوات:** [items.md](items.md)
- **الرحلات:** "Auto pick"، تكمل وانت خارج اللعبة، والمخلوقات المسافرين ما يتبادلوش وما يتحذفوش
- **Reload:** تأكيد بضغطتين
- **المكافأة اليومية، المهام (نفس اللاعب ونفس اليوم = نفس المهام)، Battle Pass، هدايا وقت اللعب، Luck ×2 بلاش كل نهار:** `Config/Progression.luau`
- **Achievements:** 18 إنجاز بدرجات، تتعطى وحدها مع إشعار. **Index:** كل نوع × درجة تملكو يتسجل (300 في العالم 1)، حتى اللي جاو بالتبادل. **Rank:** يبان فوق الراس. النافذة: Quests ← Awards
- **🎯 Daily Bounty، 📖 Journey (Professor Cubo حدا الـ spawn)، ⭐ First clears:** في Quests
- **الشرح للاعبين الجداد:** كسّر مصدر، فقّس بيضة، افتح منطقة. شعاع ذهبي للهدف وزر Skip، وفي الأخير 💎 25 وإكسير. اللاعبين القدام ما يشوفوهش
- **الشكل:** ألقاب، Trails، مركبات (كلهم نفس السرعة)، Auras و Hatch effects. في Quests ← Style

### الأنشطة
- **🎰 Lucky Spin:** كشك في المدينة، وزر 🎰 فوق مع نقطة حمراء كي تكون الدورة المجانية جاهزة. الجائزة تتقرر في السيرفر
- **🧊 Cube Stack:** السيرفر يحسب الوقت باش ما يغشوش
- **🎣 Fishing Pond:** في الركن الشمالي الغربي تاع المدينة. Perfect = حظ الحوت النادر ×2. 10 حوتات، Fish Index ولقب Angler. **Auto Fish** بلاش بصح أبطأ وبلا Perfect ولا تذاكر. السيرفر يتحقق من الوقت (`Config/Fishing.luau`)
- **👹 World Boss:** كل ساعة في :30 (UTC) في المدينة، وفي Studio بعد 45 ثانية. السيرفر يتنبّه قبل دقيقة، وزر فوق يوريك الوقت ويديك للـ boss. الصحة = قوة كل اللاعبين × 60 ثانية، و 3 دقايق قبل ما يهرب. **المكافأة على قد ما ضربت أنت مقارنة بقوتك، ماشي على الترتيب** (`Config/Boss.luau`). يعطي نقاط الكلان، توكنز الأحداث، مهمة أسبوعية وإنجاز
- **الأحداث:** تتزاد من `Config/Events.luau` (إسم، تاريخ UTC، التوكن، الـ bonus، المتجر). زر فوق يورّي التوكنز والوقت الباقي. حدثين جاهزين: Spooky Fest (24 أكتوبر حتى 7 نوفمبر 2026) و Snow Fest (19 ديسمبر حتى 2 جانفي). **باش تجرب في Studio:** حط إسمو في `TEST_EVENT`
- **🔴 Live Event (كيما Admin Abuse):** `/live luck 3 30` في الشات (Luck ×3 لمدة 30 دقيقة) وكل السيرفرات ياخذوه، مع شريط فوق. `/live stop` يحبسو. الأنواع والحدود في `Config/LiveEvent.luau`. يبداه غير مول اللعبة (ولا مول الـ group)، Studio، ولا الـ IDs في `ADMINS`

### الجماعي
- **التبادل** (هنا برك تفاصيل الأمان):
  - طلب وقبول، وتقدر تسكّر الطلبات من الإعدادات
  - Ready يتقفل 3 ثواني بعد أي تبديل، وشاشة تأكيد أخيرة تبين واش تاخذ وواش تعطي
  - **قيمة التبادل:** كل جهة تبان بعدد المخلوقات و 👑 Titans و ⭐ Bigs و 💎 النادرين، وتحذير أحمر إذا راك تعطي أندر بـ 3 مرات
  - السيرفر يعاود يتأكد قبل التبادل (الملكية، القفل، المخزن)، والمخلوقات المقفولة ما تتبادلش
  - سجل التبادلات
- **Trading Plaza:** 8 أكشاك شرق المدينة، حتى 6 مخلوقات للبيع بالجواهر. **حماية:** المشتري يبعث الثمن اللي شافو، والمخلوق لازم يكون هو بالضبط اللي تحط. 5% ضريبة. الكشك يتفرغ كي يخرج صاحبو
- **Clans:** الإنشاء بـ 💎 500 (الإسم والحروف يمرو على فلتر Roblox)، دخول بكود من 6 حروف، حتى 20 عضو بين كل السيرفرات. نقاط أسبوعية من اللعب (Break و Hatch: 300 في النهار للعضو برك)، و Top 10 ياخذو جواهر ولقب. الحروف تبان فوق الراس (مثلاً "⭐ 5 [CK]"). كي يخرج الرئيس، صاحب أكثر نقاط يولي رئيس. الرئيس يطرد عضو واحد في النهار (`Config/Clans.luau`)
- **🎁 هدايا الأصحاب:** زر Gift في نافذة Trade
- **لوحات الترتيب:** 4 في المدينة، عالمية، تتحدث كل دقيقتين، والأرقام الكبار بـ log10. **لوحة Coins عادلة:** ما تحسبش Boosts ولا Premium

### الربح والإعدادات
- **Robux:** المنتجات في "قبل النشر" فوق، والقواعد في [game-design.md](game-design.md#12-الربح-roblox). اختبار يتأكد أن حتى منتج ما يبيع بيض، حظ، ولا جوائز عشوائية
- **قواعد الإنصاف:** VIP و +2 Team Slots يعطيو الأماكن بكري والحد 12 للكل. رحلة بالـ Robux ولا في slot تاع الـ pass ترجع عملات وجواهر برك. حفظ السلسلة بالإعلان برك. أنصاص Titan Key ما يتباعوش بالجواهر
- **إعلانات الفيديو:** الأزرار في المتجر (▶ Free) وجنب البيض، وتتخبى كي ما يكونش فيديو. إذا المكافأة ما بقاتش صالحة (مثلا الرحلة تستلمت)، اللاعب ياخذ Coins ×2 لمدة 30 دقيقة بلاصتها. الحدود في `Config/Products.luau`
- **Teleport:** نافذة 🌀 لأي منطقة مفتوحة (Game Pass)
- **الإعدادات:** Low-end mode (يخبي مخلوقات الآخرين ومؤثرات العملات)، طلبات التبادل، Equip Best تلقائي، Auto-Delete، Codes، Sound effects و Music
- **Auto farm و Auto hatch يتفكرو:** كي ترجع للعبة (AFK ولا سيرفر جديد) يرجعو ON
- **الحفظ:** DataStore بقفل جلسة، حفظ كل دقيقة وكي يخرج اللاعب، وحماية المشتريات. **هدية البداية:** 3 مخلوقات + 100 عملة
- **📱 الهاتف:** أزرار القائمة ورا زر "☰ Menu" فوق على اليسار باش ما يغطيوش الـ joystick. زر Auto يبقى ظاهر

## واش باقي

- **Arcade:** ألعاب صغيرة أخرى (Claw Machine، Coin Pusher)
- **العوالم 2 حتى 15:** مؤجلين. نكملو العالم 1 وكل الأنظمة الأول، ومن بعد نزيدو العوالم. التصميم في [worlds.md](worlds.md)
- **أصوات خاصة باللعبة:** نبدلو الأصوات الأساسية بأصوات من Creator Store، ونزيدو موسيقى
- **مفاتيح أخرى:** Pixel Key (Rift Key راهي كاينة)
- **أفكار مؤجلة** مكتوبة في [game-design.md](game-design.md) و [items.md](items.md) (كلمة "مؤجل")
- **Live Event من الشات:** إذا `/live` ما خدمش في Studio، نديرو زر خاص للأدمين

## ملاحظة على التجربة

الكود ما تجربش في Roblox Studio لأن Studio ما يخدمش في البيئة اللي تكتب فيها. اللي تفحص:
- **أنواع Luau:** مقابل Roblox API
- **أكثر من 100 اختبار للمنطق** (`tests/run.luau`): الفقس، القوة، الدمج، التبادل، البطاقات، المفاتيح، الرحلات، Reload، حدود الإعلانات، الهدايا، Achievements و Rank، متجر الجواهر...
- **اختبار الخريطة:** يبني العالم، و Big والحراس
- **بناء المخلوقات والخريطة:** بأجزاء Roblox حقيقية

أول تجربة في Studio ممكن تبين أخطاء صغار.
