# العوالم الـ 15

> **ملاحظة:** العوالم 2 حتى 15 **مؤجلين** للبرمجة. دركا نكملو العالم 1 وكل الأنظمة (الأدوات، الإعلانات، Achievements...)، ومن بعد نرجعو للعوالم. التصميم هنا يبقى هو المرجع.

تفاصيل العالم الأول الكاملة (الأنواع والمهارات) في [world-1.md](world-1.md). العوالم الأخرى مكتوبة هنا: الموضوع، الميكانيكية الخاصة، شكل الخريطة، المناطق، وحارس كل منطقة. كل الأرقام مقترحة.

## القواعد العامة

- **كل عالم فيه 10 مناطق**، وكل منطقة عندها بيضة فيها 4 أنواع (60% / 30% / 9% / 1%)
- **حارس المنطقة (Titan)** هو النوع 1% في بيضتها
- **كل عالم عندو ميكانيكية خاصة** تبدل طريقة اللعب، باش ما يكونش تكرار
- **كل عالم يفتح نظام جديد،** باش اللاعب ما يتلفش من البداية
- **باش تدخل عالم جديد:**
  - تكمّل آخر منطقة في العالم اللي قبلو
  - عندك عدد Reload كافي: العالم N يحتاج N−1 Reload
- **الأثمان:**
  - داخل العالم، البيض يغلى تقريباً ×10,000 من المنطقة 1 حتى 10
  - بين العوالم، ×10
  - في الواجهة نستعملو اختصارات: K، M، B، T، ومن بعد aa، ab، ac...

### العناصر
| العنصر | الرمز | الدرجة اللي قوية فيه ×2 |
|--------|-------|-------------------------|
| عادي | — | — |
| نار | 🔥 | Crystal |
| ثلج | ❄️ | Lava |
| ظلام | 🌑 | Neon |
| Pixel | 🟪 | Pixel |
| **كنز** (جديد) | 💰 | **Golden** |

**عنصر الكنز جديد:** يعطي فايدة لمخلوقات Golden حتى في العوالم المتقدمة.

---

## نظرة عامة

| # | العالم | الميكانيكية الخاصة | شكل الخريطة | يفتح | ثمن البيض |
|---|--------|---------------------|-------------|------|-----------|
| 1 | 🌿 Green Valley | رجوع الألوان (الأساس) | طريقين يتلاقاو | الأساسيات | 100 ← 1M |
| 2 | 🍭 Candy Kingdom | **Sugar Rush** | 3 طرق | Elixir Mixer | 10M ← 100B |
| 3 | 🌊 Ocean Depths | **العمق والضوء** | للتحت | الرحلات الطويلة | 1T ← e16 |
| 4 | 🧸 Toy Box | **Play Time** | شبكة حرة | ألعاب Arcade جديدة | e17 ← e21 |
| 5 | ☁️ Sky Islands | **بناء الجسور** | للفوق | Rides | e22 ← e26 |
| 6 | 👻 Haunted Town | **الليل والنهار** | دائرة | Stickers Holo | e27 ← e31 |
| 7 | 🏜️ Desert Pyramids | **قبور مخبية** | متاهة | مفاتيح ممتازة | e32 ← e36 |
| 8 | 🌴 Jungle Ruins | **صيد Big** | طرق متشابكة | Egg Radar | e37 ← e41 |
| 9 | ❄️ Arctic Base | **العواصف** | خط ودورات | أحداث الطقس | e42 ← e46 |
| 10 | 🤖 Robot Factory | **أحزمة النقل** | مصنع بطوابق | Auto-Expeditions | e47 ← e51 |
| 11 | 🌋 Volcano Island | **الانفجارات** | جزيرة دائرية | مكان Sticker ثاني | e52 ← e56 |
| 12 | 💎 Crystal Caves | **المرايا** | كهوف للتحت | Gem Shop | e57 ← e61 |
| 13 | 🌙 Dream World | **أحلام عشوائية** | تتبدل كل ساعة | Dream Modifiers | e62 ← e66 |
| 14 | 🕹️ Retro Arcade | **مراحل أركاد** | مستويات لعبة | High Score | e67 ← e71 |
| 15 | 💾 The Core | **النهاية والمنطقة اللانهائية** | للمركز | Infinite Zone | e72 ← e76 |

---

## 1. 🌿 Green Valley
**التفاصيل الكاملة في [world-1.md](world-1.md).** العالم الأول: مرج، غابة، شاطئ، صحراء، ثلج، بركان، و Pixel Zone.

---

## 2. 🍭 Candy Kingdom
**الموضوع:** مملكة حلويات. المصادر كيك، حلوى، وشوكولا.

**الميكانيكية: Sugar Rush 🍬**
- كل مصدر تكسّرو يعمّر **عداد السكر**
- كي يتعمّر، تبدا **Sugar Rush:** 30 ثانية كلش ×3، والفريق يجري ×2
- العداد يتعمّر أسرع إذا لعبت بنشاط (ضد الـ AFK)

**الخريطة:** 3 طرق (شوكولا، ثلج، فواكه) يتلاقاو في القصر.
**يفتح:** آلة خلط الإكسيرات (Elixir Mixer).

| # | المنطقة | العنصر | الحارس (Titan) |
|---|---------|--------|----------------|
| 1 | Lollipop Lane | — | Gummy Bear |
| 2 | Cupcake Hills | — | Cupcake Knight |
| 3 | Cookie Forest | — | Cookie Golem |
| 4 | Chocolate River | — | Choco Croc |
| 5 | Ice Cream Glacier | ❄️ | Sundae Yeti |
| 6 | Marshmallow Clouds | — | Marshmallow Sheep |
| 7 | Candy Cane Peaks | ❄️ | Peppermint Penguin |
| 8 | Hot Cocoa Springs | 🔥 | Cocoa Dragon |
| 9 | Gumdrop Caves | 🌑 | Licorice Bat |
| 10 | Sugar Palace | 💰 | Candy Queen |

---

## 3. 🌊 Ocean Depths
**الموضوع:** تهبط من الشاطئ حتى أعمق خندق في البحر.

**الميكانيكية: العمق والضوء 🔦**
- كل ما تهبط، الدنيا **تظلام** والمصادر يتخباو
- **مخلوقات Neon يضوّيو** حولهم ويبينو المصادر المخبية
- المصادر في الظلام فيهم **عملات ×2**

**الخريطة:** للتحت، بطبقات.
**يفتح:** الرحلات الطويلة (12 ساعة).

| # | المنطقة | العنصر | الحارس (Titan) |
|---|---------|--------|----------------|
| 1 | Sunny Shore | — | Sea Turtle |
| 2 | Coral Reef | — | Clownfish |
| 3 | Kelp Forest | — | Sea Otter |
| 4 | Shipwreck | 💰 | Pirate Parrot |
| 5 | Jellyfish Bay | 🌑 | Jelly Queen |
| 6 | Iceberg Sea | ❄️ | Orca |
| 7 | Hydrothermal Vents | 🔥 | Vent Crab |
| 8 | Midnight Zone | 🌑 | Anglerfish |
| 9 | Sunken City | 💰 | Merking |
| 10 | Abyss Trench | 🌑 | Kraken |

---

## 4. 🧸 Toy Box
**الموضوع:** غرفة ألعاب ضخمة، والمخلوقات صغار وسطها.

**الميكانيكية: Play Time 🎲**
- كل 15 دقيقة، **Play Time:** كل المصادر يتحولو لألعاب فيها هدايا لمدة دقيقة
- المصادر المكسورة **يعاودو يتركبو** وحدهم أسرع (كيما الليغو)

**الخريطة:** شبكة حرة، تفتح المناطق بالترتيب اللي تحب.
**يفتح:** ألعاب Arcade جديدة (Whack-a-Block، Coin Pusher).

| # | المنطقة | العنصر | الحارس (Titan) |
|---|---------|--------|----------------|
| 1 | Block Town | — | Toy Soldier |
| 2 | Teddy Hills | — | Teddy Bear |
| 3 | Race Track | — | Race Car |
| 4 | Dollhouse | — | Ballerina |
| 5 | Train Set | — | Steam Train |
| 6 | Puzzle Plains | 🟪 | Puzzle Cube |
| 7 | Robot Shelf | 🟪 | Wind-up Robot |
| 8 | Arcade Corner | 🟪 | Joystick |
| 9 | Under the Bed | 🌑 | Dust Bunny |
| 10 | Toy Chest | 💰 | Jack-in-the-Box |

---

## 5. ☁️ Sky Islands
**الموضوع:** جزر طايرة فوق السحاب.

**الميكانيكية: بناء الجسور 🌉**
- البوابات هنا **جسور** تبنيها بالعملات، وتشوفها تتبنى قدامك
- كل ما تطلع، تحس بلي راك تعلى في السما (الإحساس اللي يحبوه في BGSI)
- **الريح:** مرات تجي ريح تجيب العملات من جزر بعيدة

**الخريطة:** للفوق، جزيرة فوق جزيرة.
**يفتح:** Rides.

| # | المنطقة | العنصر | الحارس (Titan) |
|---|---------|--------|----------------|
| 1 | Cloud Dock | — | Pigeon |
| 2 | Windmill Isle | — | Kite Fox |
| 3 | Balloon Fair | — | Balloon Pup |
| 4 | Rainbow Bridge | 💰 | Rainbow Pegasus |
| 5 | Thunder Peak | 🌑 | Storm Eagle |
| 6 | Frost Cloud | ❄️ | Hail Golem |
| 7 | Sun Temple | 🔥 | Sun Lion |
| 8 | Floating Ruins | 💰 | Sky Guardian |
| 9 | Storm Eye | 🌑 | Thunderbird |
| 10 | Sky Castle | 💰 | Sky Emperor |

---

## 6. 👻 Haunted Town
**الموضوع:** مدينة أشباح لطيفة، ماشي مخيفة بزاف للصغار.

**الميكانيكية: الليل والنهار 🌗**
- كل 10 دقايق يتبدل الوقت
- **في الليل:** Neon ×3، ومصادر أشباح فيهم عملات ×2
- **في النهار:** الأشباح يتخباو، والمصادر العادية ×1.5

**الخريطة:** دائرة حول برج القمر.
**يفتح:** درجة Holo للملصقات.

| # | المنطقة | العنصر | الحارس (Titan) |
|---|---------|--------|----------------|
| 1 | Pumpkin Patch | 🌑 | Pumpkin Head |
| 2 | Spooky Woods | 🌑 | Night Wolf |
| 3 | Graveyard | 🌑 | Skeleton |
| 4 | Witch Hut | 🔥 | Witch Cat |
| 5 | Ghost Manor | 🌑 | Ghost |
| 6 | Frozen Crypt | ❄️ | Ice Wraith |
| 7 | Bat Cave | 🌑 | Vampire Bat |
| 8 | Mad Lab | 🟪 | Frank-Cube |
| 9 | Haunted Carnival | 💰 | Ghost Ringmaster |
| 10 | Moon Tower | 🌑 | Nightmare |

---

## 7. 🏜️ Desert Pyramids
**الموضوع:** صحراء، أهرامات، وكنوز مخبية.

**الميكانيكية: قبور مخبية 🗝️**
- كل منطقة فيها **قبور سرية** تتفتح بـ Zone Keys
- القبور فيها كنوز كبيرة، و Egg Radar يورّيك وين كاينين
- **عالم الكنز:** بزاف مناطق 💰، يعني Golden ×2

**الخريطة:** متاهة.
**يفتح:** المفاتيح الممتازة.

| # | المنطقة | العنصر | الحارس (Titan) |
|---|---------|--------|----------------|
| 1 | Oasis | — | Fennec Fox |
| 2 | Dune Sea | 🔥 | Sand Worm |
| 3 | Bazaar | 💰 | Genie Lamp |
| 4 | Scorpion Canyon | 🔥 | Scorpion King |
| 5 | Pharaoh Tombs | 🌑 | Mummy |
| 6 | Sphinx Plaza | 💰 | Anubis |
| 7 | Sandstorm Flats | 🔥 | Dust Djinn |
| 8 | Hidden Temple | 💰 | Scarab |
| 9 | Cold Desert Night | ❄️ | Moon Jackal |
| 10 | Golden Pyramid | 💰 | Pharaoh |

---

## 8. 🌴 Jungle Ruins
**الموضوع:** غابة استوائية وآثار قديمة.

**الميكانيكية: صيد Big 🎯**
- Big يظهر **×3 أكثر** في هذا العالم
- **الأعشاب** تعاود تنبت المصادر وحدها
- **Big نادرين خاصين بالغابة،** ما يظهروش في حتى عالم آخر

**الخريطة:** طرق متشابكة.
**يفتح:** Egg Radar.

| # | المنطقة | العنصر | الحارس (Titan) |
|---|---------|--------|----------------|
| 1 | Jungle Edge | — | Monkey |
| 2 | Waterfall | — | Tree Frog |
| 3 | Vine Bridge | — | Sloth |
| 4 | Totem Ruins | 💰 | Totem Toucan |
| 5 | Swamp | 🌑 | Swamp Croc |
| 6 | Volcano Rim | 🔥 | Magma Gecko |
| 7 | Lost Temple | 💰 | Jade Panther |
| 8 | Dino Valley | — | T-Rex |
| 9 | Spider Nest | 🌑 | Jungle Spider |
| 10 | Sun Altar | 🔥 | Quetzal |

---

## 9. ❄️ Arctic Base
**الموضوع:** القطب الشمالي وقاعدة بحث.

**الميكانيكية: العواصف 🌨️**
- مرات تجي **عاصفة ثلج** تجمّد المصادر
- المصادر المجمدة ما يكسرهمش غير مخلوقات **Lava** ولا Elixir نار
- كي يتكسرو، يعطيو **عملات ×3**
- **عالم Lava:** بزاف مناطق ❄️

**الخريطة:** خط فيه دورات.
**يفتح:** أحداث الطقس في كل العوالم.

| # | المنطقة | العنصر | الحارس (Titan) |
|---|---------|--------|----------------|
| 1 | Snowfield | ❄️ | Arctic Fox |
| 2 | Snow Village | ❄️ | Snow Bunny |
| 3 | Ice Rink | ❄️ | Skating Penguin |
| 4 | Aurora Lake | 🌑 | Aurora Spirit |
| 5 | Research Base | 🟪 | Snow Bot |
| 6 | Ice Cave | ❄️ | Mammoth |
| 7 | Glacier Wall | ❄️ | Walrus |
| 8 | Hot Springs | 🔥 | Snow Monkey |
| 9 | Polar Night | 🌑 | Polar Bear |
| 10 | Frozen Throne | ❄️ | Frost Giant |

---

## 10. 🤖 Robot Factory
**الموضوع:** مصنع روبوتات ضخم.

**الميكانيكية: أحزمة النقل ⚙️**
- **أحزمة** تجيب المصادر للاعب وحدها
- اللاعب يطوّر الأحزمة: أسرع، ومصادر أكبر
- **Overclock:** مرات المصنع يخدم ×5 لمدة 30 ثانية

**الخريطة:** مصنع بطوابق.
**يفتح:** Auto-Expeditions (الرحلات تعاود تنبعث وحدها).

| # | المنطقة | العنصر | الحارس (Titan) |
|---|---------|--------|----------------|
| 1 | Loading Dock | 🟪 | Forklift |
| 2 | Assembly Line | 🟪 | Robot Arm |
| 3 | Scrap Yard | — | Scrap Dog |
| 4 | Power Plant | 🔥 | Battery Bot |
| 5 | Server Room | 🟪 | Data Drone |
| 6 | Cooling Tower | ❄️ | Fan Bot |
| 7 | Laser Lab | 🌑 | Laser Cat |
| 8 | Gold Mint | 💰 | Mint Bot |
| 9 | Control Room | 🟪 | AI Core |
| 10 | Mega Factory | 🟪 | Mega Mech |

---

## 11. 🌋 Volcano Island
**الموضوع:** جزيرة بركانية وتنانين.

**الميكانيكية: الانفجارات 🌋**
- كل بضع دقايق البركان **ينفجر** ويطيّح **مصادر منصهرة** في كل المنطقة
- المصادر المنصهرة فيهم عملات ×5، ومخلوقات **Crystal** يكسروهم أسرع
- **عالم Crystal:** بزاف مناطق 🔥

**الخريطة:** جزيرة دائرية حول البركان.
**يفتح:** مكان Sticker ثاني لكل مخلوق.

| # | المنطقة | العنصر | الحارس (Titan) |
|---|---------|--------|----------------|
| 1 | Black Sand Beach | 🔥 | Lava Turtle |
| 2 | Ash Forest | 🔥 | Ember Fox |
| 3 | Obsidian Cliffs | 🔥 | Obsidian Golem |
| 4 | Magma Lake | 🔥 | Magma Whale |
| 5 | Smoke Caves | 🌑 | Smoke Bat |
| 6 | Steam Vents | — | Steam Owl |
| 7 | Dragon Nest | 🔥 | Baby Dragon |
| 8 | Fire Temple | 💰 | Flame Spirit |
| 9 | Lava Falls | 🔥 | Salamander King |
| 10 | Volcano Core | 🔥 | Elder Dragon |

---

## 12. 💎 Crystal Caves
**الموضوع:** كهوف تحت الأرض مليانة جواهر.

**الميكانيكية: المرايا 🪞**
- **مرايا كريستال** في المنطقة: كي تكسّر مصدر قريب منها، المراية **تنسخ** العملات تاعو
- **عالم الجواهر:** الجواهر تطيح ×5

**الخريطة:** كهوف للتحت.
**يفتح:** Gem Shop: تشري بالجواهر Elixirs و Cartridges و Gadgets.

| # | المنطقة | العنصر | الحارس (Titan) |
|---|---------|--------|----------------|
| 1 | Cave Mouth | 🌑 | Mole |
| 2 | Glow Tunnels | 🌑 | Glow Snail |
| 3 | Amethyst Hall | 💰 | Amethyst Bat |
| 4 | Underground Lake | ❄️ | Cave Axolotl |
| 5 | Mushroom Grotto | 🌑 | Truffle Pig |
| 6 | Ruby Mines | 🔥 | Ruby Beetle |
| 7 | Sapphire Falls | ❄️ | Sapphire Serpent |
| 8 | Emerald Garden | 💰 | Emerald Deer |
| 9 | Diamond Depths | 💰 | Diamond Golem |
| 10 | Prism Core | 🟪 | Prism Dragon |

---

## 13. 🌙 Dream World
**الموضوع:** عالم الأحلام، كلش فيه غريب.

**الميكانيكية: أحلام عشوائية 💭**
- **كل ساعة** يتبدل "الحلم"، وكل حلم يبدل القواعد:

| الحلم | واش يبدل |
|-------|----------|
| 🪶 Low Gravity | العملات يطيرو، والمغناطيس ×3 |
| 🟨 Golden Dream | كل المصادر ذهب |
| 🥚 Egg Dream | كل بيضة تعطي 2 |
| 🔄 Upside Down | الخريطة تنقلب، والمصادر النادرة ×3 |
| 🐢 Slow Motion | الوقت يبطا، والـ Combo ما يطيحش |

**الخريطة:** تتبدل مع الحلم.
**يفتح:** Dream Modifiers (تقدر تختار حلم واحد بـ Rift Key).

| # | المنطقة | العنصر | الحارس (Titan) |
|---|---------|--------|----------------|
| 1 | Pillow Fields | — | Sleepy Sheep |
| 2 | Lullaby Lake | — | Dream Fish |
| 3 | Night Light Meadow | 🌑 | Firefly |
| 4 | Upside Down City | 🟪 | Upside Cat |
| 5 | Nightmare Woods | 🌑 | Shadow Wolf |
| 6 | Cotton Candy Sky | — | Cloud Whale |
| 7 | Clockwork Dream | 🟪 | Clock Owl |
| 8 | Mirror Maze | 💰 | Mirror Fox |
| 9 | Endless Stairs | 🌑 | Dream Eater |
| 10 | Dream Palace | 💰 | Sandman |

---

## 14. 🕹️ Retro Arcade
**الموضوع:** داخل لعبة أركاد قديمة. كلش بكسلات.

**الميكانيكية: مراحل أركاد 👾**
- **كل منطقة** عندها مصادر تتحرك كيما لعبة أركاد: ثعبان عملات يجري، حيطان طوب تتكسر...
- **Pixel ×2 في كل المناطق** تقريباً: الحلم تاع لاعبين Pixel

**الخريطة:** مستويات لعبة (Level 1 ← Level 10).
**يفتح:** لوحة High Score لكل لعبة Arcade.

| # | المنطقة | العنصر | الحارس (Titan) |
|---|---------|--------|----------------|
| 1 | Pixel Plaza | 🟪 | 8-bit Pup |
| 2 | Snake Garden | 🟪 | Snake |
| 3 | Brick Breaker | 🟪 | Paddle Bot |
| 4 | Alien Alley | 🟪 | Pixel Alien |
| 5 | Kart Track | 🟪 | Kart Cube |
| 6 | Maze Runner | 🌑 | Maze Ghost |
| 7 | Block Drop Tower | 🟪 | Block Stack |
| 8 | Boss Rush | 🔥 | 8-bit Dragon |
| 9 | High Score Hall | 💰 | Trophy |
| 10 | Final Level | 🟪 | Game Master |

---

## 15. 💾 The Core
**الموضوع:** قلب العالم، المكان اللي يتحمّل منو كلش. هذي نهاية القصة.

**الميكانيكية: النهاية والمنطقة اللانهائية ♾️**
- **الحارس الأخير: The Loader**
  - كي تغلبو، العالم كامل يولي **"Fully Loaded"**: حركة نهاية، وكل العوالم تبان بأحسن ألوان
- **بعد النهاية: Infinite Zone**
  - مناطق تتولد وحدها بلا نهاية، وكل وحدة أصعب ومكافأتها أكبر
  - لوحة ترتيب: شكون وصل أبعد
- **هكذا** اللاعبين الكبار عندهم دايماً هدف

**الخريطة:** دوائر للمركز.
**يفتح:** Infinite Zone.

| # | المنطقة | العنصر | الحارس (Titan) |
|---|---------|--------|----------------|
| 1 | Boot Screen | 🟪 | Loading Cube |
| 2 | Memory Lane | 🟪 | Memory Chip |
| 3 | Firewall | 🔥 | Firewall Hound |
| 4 | Cache Cave | 🌑 | Cache Bat |
| 5 | Frozen Frame | ❄️ | Lag Yeti |
| 6 | Data Stream | 🟪 | Data Dolphin |
| 7 | Treasure Bytes | 💰 | Golden Bit |
| 8 | Null Sector | 🌑 | Null Cat |
| 9 | Render Engine | 🔥 | Render Phoenix |
| 10 | The Core | 🟪 | **The Loader** |

---

## الحساب

- **15 عالم × 10 مناطق = 150 منطقة**
- **150 × 4 أنواع = 600 نوع**
- **600 × 6 درجات = 3,600 مخلوق** في الكتاب، بلا ما نحسبو Big و Titan
- **150 حارس Titan**

**ملاحظة:** نصممو الأنواع ومهاراتهم بالتفصيل عالم بعالم، كيما درنا في [world-1.md](world-1.md). في الإطلاق نبداو بالعالم 1 و 2، ونزيدو عالم جديد في كل تحديث كبير، باش اللاعبين يلقاو دايماً جديد.
