"""The maps after Meadow. Meadow's eight live in cubelings.py (SPECIES, built by blocky.py); every other
egg's animals are here, in Steal an Egg's style: real animals of blocks with Lego studs (blocky.py), eight
an egg, two of each rarity. Each egg is a ZONES row, in egg order: the Wild's biomes (Flower to Volcano)
and the Egg Shop's own last eggs (Ice, Pixel, Legendary), which have no biome. All eleven eggs are now
designed and open in the game (Config/Island OPEN_TIER = 11).
"""

SPECIES = {
    # Zone 2 (Flower): the garden's small things, and the fox and the deer that watch over them
    "Bee": {
        "style": "blocky",
        "animal": "bee",
        "colors": {"body": "#F5C542", "belly": "#FFE9A8", "stripe": "#2A2018", "wing": "#EAF6FF", "legs": "#4A3410", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Ladybug": {
        "style": "blocky",
        "animal": "ladybug",
        "colors": {"body": "#DC3C32", "belly": "#F0715C", "wing": "#B02820", "spot": "#2A1A12", "legs": "#2A1A12", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Butterfly": {
        "style": "blocky",
        "animal": "butterfly",
        "colors": {"body": "#966EDC", "belly": "#C0A2EE", "wing": "#C86DD7", "spot": "#FFE066", "legs": "#5A3A8A", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Snail": {
        "style": "blocky",
        "animal": "snail",
        "colors": {"body": "#82C86E", "belly": "#C8EAB8", "shell": "#B56545", "spot": "#E8A87C", "legs": "#6FB85E", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Frog": {
        "style": "blocky",
        "animal": "frog",
        "colors": {"body": "#5ABE5A", "belly": "#E8FFD0", "spot": "#3E9E4F", "legs": "#3E9E4F", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Duckling": {
        "style": "blocky",
        "animal": "duckling",
        "colors": {"body": "#FAD246", "belly": "#FFF3B0", "wing": "#F0BE3C", "beak": "#F58A2E", "legs": "#F58A2E", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Fox": {
        "style": "blocky",
        "animal": "fox",
        "colors": {"body": "#EB7832", "belly": "#FFF2E0", "ear": "#3A2418", "tail": "#FFF6EC", "legs": "#8A4A26", "nose": "#2A1A12", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Deer": {
        "style": "blocky",
        "animal": "deer",
        "colors": {"body": "#BE8C5A", "belly": "#F2DFC4", "antler": "#8A6A42", "ear": "#A87C4C", "tail": "#F2DFC4", "legs": "#A87C4C", "nose": "#2A1A12", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    # Zone 3 (Forest): climbers and prowlers of the deep woods, the stag above them all
    "Squirrel": {
        "style": "blocky",
        "animal": "squirrel",
        "colors": {"body": "#C8783C", "belly": "#FFE3B8", "tail": "#A85F28", "ear": "#A85F28", "legs": "#A85F28", "nose": "#2A1A12", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Hedgehog": {
        "style": "blocky",
        "animal": "hedgehog",
        "colors": {"body": "#8C6446", "spike": "#5A4030", "belly": "#E8CCA8", "face": "#E8CCA8", "legs": "#5A4030", "nose": "#2A1A12", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Owl": {
        "style": "blocky",
        "animal": "owl",
        "colors": {"body": "#785537", "belly": "#D9B48A", "face": "#E8DCC4", "wing": "#5F422A", "beak": "#F5B82E", "legs": "#F5B82E", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Raccoon": {
        "style": "blocky",
        "animal": "raccoon",
        "colors": {"body": "#96969B", "belly": "#D8D8DC", "mask": "#55504A", "stripe": "#2E2A26", "ear": "#6E6E73", "legs": "#6E6E73", "nose": "#1A1410", "eye": "#14100E", "shine": "#FFFFFF"},
    },
    "Wolf": {
        "style": "blocky",
        "animal": "wolf",
        "colors": {"body": "#828791", "belly": "#D8DCE2", "ear": "#6E747E", "tail": "#6E747E", "legs": "#6E747E", "nose": "#1A1410", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Moose": {
        "style": "blocky",
        "animal": "moose",
        "colors": {"body": "#78553C", "belly": "#A87C50", "snout": "#A87C50", "antler": "#D9B48A", "legs": "#654628", "nose": "#24150D", "eye": "#140C08", "shine": "#FFFFFF"},
    },
    "Lynx": {
        "style": "blocky",
        "animal": "lynx",
        "colors": {"body": "#D2AA78", "belly": "#F7ECD8", "spot": "#A87C4C", "ear": "#8A6A42", "legs": "#BE965F", "nose": "#B5536B", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Stag": {
        "style": "blocky",
        "animal": "stag",
        "colors": {"body": "#966441", "belly": "#E8CCA8", "antler": "#6E4E2E", "ear": "#7A5133", "tail": "#E8CCA8", "legs": "#7A5133", "nose": "#24150D", "eye": "#140C08", "shine": "#FFFFFF"},
    },
    # Zone 4 (Beach): shore things first, then the deep's giants, the great whale last
    "Crab": {
        "style": "blocky",
        "animal": "crab",
        "colors": {"body": "#E6503C", "belly": "#FFB59A", "claw": "#F0715C", "legs": "#C93A28", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Starfish": {
        "style": "blocky",
        "animal": "starfish",
        "colors": {"body": "#F59650", "belly": "#FFC890", "spot": "#FFE0A8", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Turtle": {
        "style": "blocky",
        "animal": "turtle",
        "colors": {"body": "#5AAA6E", "belly": "#E8E4B8", "shell": "#3E7D4F", "spot": "#2E5F3B", "legs": "#4E9A5F", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Seagull": {
        "style": "blocky",
        "animal": "seagull",
        "colors": {"body": "#F0F0F5", "belly": "#FFFFFF", "wing": "#C9CED6", "tail": "#C9CED6", "beak": "#F5A623", "legs": "#F5A623", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Octopus": {
        "style": "blocky",
        "animal": "octopus",
        "colors": {"body": "#C86EB4", "belly": "#E8A8D8", "spot": "#A84E96", "legs": "#B45EA4", "eye": "#241020", "shine": "#FFFFFF"},
    },
    "Dolphin": {
        "style": "blocky",
        "animal": "dolphin",
        "colors": {"body": "#6EAADC", "belly": "#EAF6FF", "fin": "#4E8AC2", "eye": "#10222E", "shine": "#FFFFFF"},
    },
    "Shark": {
        "style": "blocky",
        "animal": "shark",
        "colors": {"body": "#7896B4", "belly": "#EDF4FA", "fin": "#5F7E9C", "teeth": "#FFFFFF", "eye": "#0C141C", "shine": "#FFFFFF"},
    },
    "Whale": {
        "style": "blocky",
        "animal": "whale",
        "colors": {"body": "#5078C8", "belly": "#BFD9F2", "fin": "#3A5FA8", "spout": "#DFF2FF", "eye": "#0C1826", "shine": "#FFFFFF"},
    },
    # Zone 5 (Cave): things that live in the dark, and the dragon that rules it
    "Bat": {
        "style": "blocky",
        "animal": "bat",
        "colors": {"body": "#69558C", "belly": "#9A86B8", "wing": "#4A3A66", "ear_inner": "#D89AB0", "teeth": "#FFFFFF", "legs": "#57456E", "nose": "#2A1A12", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Mole": {
        "style": "blocky",
        "animal": "mole",
        "colors": {"body": "#785A46", "belly": "#A8886A", "claw": "#E8D8C8", "snout": "#D89A9A", "legs": "#654A38", "nose": "#B55A6E", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Spider": {
        "style": "blocky",
        "animal": "spider",
        "colors": {"body": "#3C3746", "belly": "#55505F", "spot": "#7A4A6E", "legs": "#2E2A38", "teeth": "#FFFFFF", "eye": "#FF5A4A", "shine": "#FFFFFF"},
    },
    "Newt": {
        "style": "blocky",
        "animal": "newt",
        "colors": {"body": "#E6823C", "belly": "#FFD9A8", "spot": "#5A3A28", "legs": "#CE7434", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Scorpion": {
        "style": "blocky",
        "animal": "scorpion",
        "colors": {"body": "#B45A32", "belly": "#CE7434", "claw": "#963F22", "sting": "#3A2418", "legs": "#8A4526", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Panther": {
        "style": "blocky",
        "animal": "panther",
        "colors": {"body": "#2D2D37", "belly": "#4A4A55", "legs": "#23232B", "nose": "#14100E", "eye": "#A8D85A", "shine": "#FFFFFF"},
    },
    "Golem": {
        "style": "blocky",
        "animal": "golem",
        "colors": {"body": "#827D78", "rock": "#6E6862", "moss": "#6CCB5F", "glow": "#7AE0FF", "legs": "#6E6862", "eye": "#FFB84D", "shine": "#FFFFFF"},
    },
    "Dragon": {
        "style": "blocky",
        "animal": "dragon",
        "colors": {"body": "#5AA050", "belly": "#D8EDB0", "spike": "#3E7D3B", "horn": "#F3E6C8", "wing": "#8FC97E", "teeth": "#FFFFFF", "legs": "#4E8A44", "nose": "#2A4A22", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    # Zone 6 (Desert): sand dwellers, and Anubis standing over them all
    "Camel": {
        "style": "blocky",
        "animal": "camel",
        "colors": {"body": "#D2AA69", "belly": "#E8CCA0", "snout": "#BE965F", "hair": "#8A6A42", "legs": "#BE965F", "nose": "#4A3220", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Meerkat": {
        "style": "blocky",
        "animal": "meerkat",
        "colors": {"body": "#C3A06E", "belly": "#EDDCB8", "patch": "#5A4632", "legs": "#A8875A", "nose": "#2A1A12", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Fennec": {
        "style": "blocky",
        "animal": "fennec",
        "colors": {"body": "#F0D7A0", "belly": "#FFF6E0", "ear_inner": "#F5B8C4", "tail": "#5A4632", "legs": "#E0C28A", "nose": "#2A1A12", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Vulture": {
        "style": "blocky",
        "animal": "vulture",
        "colors": {"body": "#5A5055", "belly": "#6E6268", "wing": "#463E44", "ruff": "#D8CFC4", "head": "#D88A94", "beak": "#E8B84B", "legs": "#8A7A6A", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Cobra": {
        "style": "blocky",
        "animal": "cobra",
        "colors": {"body": "#BEA050", "belly": "#E8DCA8", "hood": "#A8873C", "spot": "#6E5626", "tongue": "#E5534B", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Hyena": {
        "style": "blocky",
        "animal": "hyena",
        "colors": {"body": "#AA916E", "belly": "#D8C4A0", "spot": "#6E5A40", "mane": "#6E5A40", "teeth": "#FFFFFF", "legs": "#967C58", "nose": "#3A2818", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Lion": {
        "style": "blocky",
        "animal": "lion",
        "colors": {"body": "#D7A046", "belly": "#F5E3B8", "mane": "#A85F28", "legs": "#C08C38", "nose": "#7A3A22", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Anubis": {
        "style": "blocky",
        "animal": "anubis",
        "colors": {"body": "#322D3C", "belly": "#453E54", "gold": "#F5C542", "legs": "#28242F", "nose": "#14100E", "eye": "#FFD84D", "shine": "#FFFFFF"},
    },
    # Zone 7 (Snow): the small and the round, and the yeti over them all
    "Lemming": {
        "style": "blocky",
        "animal": "lemming",
        "colors": {"body": "#B48255", "belly": "#EDD9B8", "stripe": "#6E4E30", "legs": "#96704A", "nose": "#B5536B", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Penguin": {
        "style": "blocky",
        "animal": "penguin",
        "colors": {"body": "#3C4150", "belly": "#FFFFFF", "beak": "#F58A2E", "feet": "#F58A2E", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Seal": {
        "style": "blocky",
        "animal": "seal",
        "colors": {"body": "#A0AAB4", "belly": "#E4EAF0", "whisker": "#FFFFFF", "nose": "#3A3F46", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Hare": {
        "style": "blocky",
        "animal": "hare",
        "colors": {"body": "#EBEEF2", "belly": "#FFFFFF", "ear_tip": "#3A3F46", "ear_inner": "#F5B8C4", "tail": "#FFFFFF", "legs": "#D8DCE2", "nose": "#F58AA0", "eye": "#2A1E28", "shine": "#FFFFFF"},
    },
    "Yak": {
        "style": "blocky",
        "animal": "yak",
        "colors": {"body": "#6E5040", "belly": "#86644E", "fur": "#573E30", "horn": "#D9C8A8", "legs": "#4E382A", "nose": "#2A1A12", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Walrus": {
        "style": "blocky",
        "animal": "walrus",
        "colors": {"body": "#A5785A", "belly": "#C49A76", "muzzle": "#BE8F66", "whisker": "#EDE4D4", "tusk": "#F5EFDF", "nose": "#4A3226", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Narwhal": {
        "style": "blocky",
        "animal": "narwhal",
        "colors": {"body": "#AAB9C8", "belly": "#E8F0F6", "spot": "#8A9AAE", "fin": "#8FA6BC", "tusk": "#F5EFE0", "eye": "#10222E", "shine": "#FFFFFF"},
    },
    "Yeti": {
        "style": "blocky",
        "animal": "yeti",
        "colors": {"body": "#F0F2F5", "belly": "#DCE6EE", "face": "#8AA0B4", "teeth": "#FFFFFF", "legs": "#D8DEE6", "nose": "#5A7086", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    # Zone 8 (Volcano): lizards and crawlers of the hot stone, and the hydra over them all
    "Gecko": {
        "style": "blocky",
        "animal": "gecko",
        "colors": {"body": "#78C85A", "belly": "#D8F2B8", "spot": "#4E9E3E", "legs": "#66B84C", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Iguana": {
        "style": "blocky",
        "animal": "iguana",
        "colors": {"body": "#5FA05F", "belly": "#C8E6B0", "spike": "#3E7D4F", "dewlap": "#F0913C", "legs": "#4E8A4E", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Beetle": {
        "style": "blocky",
        "animal": "beetle",
        "colors": {"body": "#463C5A", "belly": "#5A4E73", "wing": "#372E48", "horn": "#2A2438", "glow": "#FF9A3C", "legs": "#2A2438", "eye": "#E8E4F0", "shine": "#FFFFFF"},
    },
    "Salamander": {
        "style": "blocky",
        "animal": "salamander",
        "colors": {"body": "#2E2A30", "belly": "#453F47", "glow": "#FF7A26", "legs": "#232027", "eye": "#FFB84D", "shine": "#FFFFFF"},
    },
    "Phoenix": {
        "style": "blocky",
        "animal": "phoenix",
        "colors": {"body": "#FA8C28", "belly": "#FFD98A", "wing": "#E86A1E", "flame": "#FFC93C", "beak": "#F5B82E", "legs": "#E86A1E", "eye": "#3A1408", "shine": "#FFFFFF"},
    },
    "Cerberus": {
        "style": "blocky",
        "animal": "cerberus",
        "colors": {"body": "#964632", "belly": "#D89A78", "flame": "#FF9A3C", "teeth": "#FFFFFF", "legs": "#7E3A28", "nose": "#2A140E", "eye": "#FFC93C", "shine": "#FFFFFF"},
    },
    "Basilisk": {
        "style": "blocky",
        "animal": "basilisk",
        "colors": {"body": "#508C46", "belly": "#C8E6A0", "spike": "#2E5F3B", "horn": "#E8DCC4", "tongue": "#E5534B", "teeth": "#FFFFFF", "eye": "#FFD84D", "shine": "#FFFFFF"},
    },
    "Hydra": {
        "style": "blocky",
        "animal": "hydra",
        "colors": {"body": "#4682A0", "belly": "#BEE0EE", "spike": "#2E5F7A", "horn": "#E8DCC4", "teeth": "#FFFFFF", "legs": "#3A6E8A", "eye": "#FFD84D", "shine": "#FFFFFF"},
    },
    # Ice (tier 9): an Egg Shop egg with no biome of its own; the frozen north's beasts, the frost dragon last
    "Puffin": {
        "style": "blocky",
        "animal": "puffin",
        "colors": {"body": "#37373F", "belly": "#FFFFFF", "beak": "#F58A2E", "beak2": "#E5534B", "feet": "#F58A2E", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Otter": {
        "style": "blocky",
        "animal": "otter",
        "colors": {"body": "#825A3C", "belly": "#D8B88F", "whisker": "#FFFFFF", "legs": "#6E4A30", "nose": "#2A1A12", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "SnowLeopard": {
        "style": "blocky",
        "animal": "snowleopard",
        "colors": {"body": "#E1E4E6", "belly": "#FFFFFF", "spot": "#9AA2A8", "legs": "#C9CDD1", "nose": "#B5536B", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "PolarBear": {
        "style": "blocky",
        "animal": "polarbear",
        "colors": {"body": "#F5F5F0", "belly": "#FFFFFF", "ear_inner": "#E8D8D8", "mouth": "#1A1410", "legs": "#E4E4DC", "nose": "#1A1410", "eye": "#140C08", "shine": "#FFFFFF"},
    },
    "Sabertooth": {
        "style": "blocky",
        "animal": "sabertooth",
        "colors": {"body": "#D7AF6E", "belly": "#F5E8C8", "spot": "#B08D50", "fang": "#F8F4E8", "legs": "#C29E5C", "nose": "#7A3A22", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Mammoth": {
        "style": "blocky",
        "animal": "mammoth",
        "colors": {"body": "#8C694B", "belly": "#A87C58", "fur": "#75543A", "tusk": "#F5EFDF", "legs": "#654830", "eye": "#140C08", "shine": "#FFFFFF"},
    },
    "FrostWolf": {
        "style": "blocky",
        "animal": "frostwolf",
        "colors": {"body": "#B9D2E6", "belly": "#EFF7FF", "crystal": "#8FD8F5", "legs": "#A5C2DC", "nose": "#2A3A4A", "eye": "#4AB8E8", "shine": "#FFFFFF"},
    },
    "FrostDragon": {
        "style": "blocky",
        "animal": "frostdragon",
        "colors": {"body": "#96C8F0", "belly": "#EAF6FF", "crystal": "#BFF1FF", "wing": "#C4E4F7", "teeth": "#FFFFFF", "legs": "#84B4E2", "nose": "#2A4A66", "eye": "#1E4A6E", "shine": "#FFFFFF"},
    },
    # Pixel (tier 10): an Egg Shop egg with no biome of its own; things from inside the machine, the mainframe last
    "Mouse": {
        "style": "blocky",
        "animal": "mouse",
        "colors": {"body": "#9696A0", "belly": "#D8D8DE", "ear_inner": "#F5B8C4", "tail": "#F0A0B4", "glow": "#7AE0FF", "legs": "#84848E", "nose": "#E87A90", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Bot": {
        "style": "blocky",
        "animal": "bot",
        "colors": {"body": "#8CA0B4", "belly": "#A8BCCF", "metal": "#7D8794", "screen": "#1A2230", "glow": "#7AE0FF", "legs": "#6E7E90", "eye": "#7AE0FF", "shine": "#FFFFFF"},
    },
    "Drone": {
        "style": "blocky",
        "animal": "drone",
        "colors": {"body": "#6E7A87", "belly": "#87939F", "metal": "#59636E", "rotor": "#3A424A", "screen": "#1A2230", "glow": "#FF5A4A", "eye": "#FF5A4A", "shine": "#FFFFFF"},
    },
    "Sprite": {
        "style": "blocky",
        "animal": "sprite",
        "colors": {"body": "#78E6BE", "belly": "#A8F0D2", "wing": "#BFF5E2", "glow": "#FFF27A", "eye": "#10302A", "shine": "#FFFFFF"},
    },
    "Glitch": {
        "style": "blocky",
        "animal": "glitch",
        "colors": {"body": "#C85ADC", "belly": "#DA8AEB", "stripe": "#4AE0D8", "screen": "#2A1030", "glow": "#FFE066", "metal": "#8A5AC8", "legs": "#A84EC2", "eye": "#FFE066", "shine": "#FFFFFF"},
    },
    "Mecha": {
        "style": "blocky",
        "animal": "mecha",
        "colors": {"body": "#788296", "belly": "#96A0B4", "metal": "#5F6875", "screen": "#1A2230", "glow": "#FF9A3C", "horn": "#C8CFD8", "legs": "#525A66", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Quantum": {
        "style": "blocky",
        "animal": "quantum",
        "colors": {"body": "#826EF0", "belly": "#A08FF5", "glow": "#A8F0FF", "ring": "#FFD84D", "screen": "#241A40", "eye": "#A8F0FF", "shine": "#FFFFFF"},
    },
    "Mainframe": {
        "style": "blocky",
        "animal": "mainframe",
        "colors": {"body": "#505A78", "belly": "#68748F", "stripe": "#39415A", "screen": "#141C2E", "glow": "#5AF58A", "metal": "#788296", "cable": "#2A3040", "legs": "#39415A", "eye": "#5AF58A", "shine": "#FFFFFF"},
    },
    # Legendary (tier 11): an Egg Shop egg with no biome of its own; the myths themselves, the elder dragon last
    "Unicorn": {
        "style": "blocky",
        "animal": "unicorn",
        "colors": {"body": "#F8F6FA", "belly": "#FFFFFF", "mane": "#F5A8D8", "mane2": "#A8D8F5", "horn": "#F5C542", "hoof": "#D8C8E8", "legs": "#EDEAF2", "nose": "#E8A8BC", "eye": "#2A1E28", "shine": "#FFFFFF"},
    },
    "Pegasus": {
        "style": "blocky",
        "animal": "pegasus",
        "colors": {"body": "#EBF0FA", "belly": "#FFFFFF", "wing": "#FFFFFF", "mane": "#C8D8F0", "hoof": "#B8C4D8", "legs": "#DCE4F2", "nose": "#C89AA8", "eye": "#1E2A14", "shine": "#FFFFFF"},
    },
    "Griffin": {
        "style": "blocky",
        "animal": "griffin",
        "colors": {"body": "#BE8C46", "belly": "#F5EFE0", "wing": "#E8DCC4", "beak": "#F5B82E", "mane": "#8A5A28", "legs": "#A87C3C", "eye": "#2A1A0C", "shine": "#FFFFFF"},
    },
    "Kitsune": {
        "style": "blocky",
        "animal": "kitsune",
        "colors": {"body": "#FAF5EB", "belly": "#FFFFFF", "mark": "#E5534B", "legs": "#EDE6D6", "nose": "#B5536B", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Chimera": {
        "style": "blocky",
        "animal": "chimera",
        "colors": {"body": "#AA6E3C", "belly": "#F0DCB8", "mane": "#7A4A26", "goat": "#D8D2C4", "snake": "#5FA05F", "horn": "#E8DCC4", "tongue": "#E5534B", "teeth": "#FFFFFF", "legs": "#96622F", "nose": "#4A2A18", "eye": "#1A1410", "shine": "#FFFFFF"},
    },
    "Kraken": {
        "style": "blocky",
        "animal": "kraken",
        "colors": {"body": "#6E5096", "belly": "#B89AD8", "spot": "#4E3573", "legs": "#5F4484", "eye": "#FFD84D", "shine": "#FFFFFF"},
    },
    "Leviathan": {
        "style": "blocky",
        "animal": "leviathan",
        "colors": {"body": "#3C6EA8", "belly": "#A8CCE8", "fin": "#2E5A8C", "horn": "#E8DCC4", "teeth": "#FFFFFF", "eye": "#FFD84D", "shine": "#FFFFFF"},
    },
    "ElderDragon": {
        "style": "blocky",
        "animal": "elderdragon",
        "colors": {"body": "#7850B4", "belly": "#C8A8E8", "gold": "#F5C542", "spike": "#5A3A8C", "horn": "#E8DCC4", "beard": "#F0EBF5", "wing": "#9670CC", "teeth": "#FFFFFF", "legs": "#66449E", "nose": "#3A2456", "eye": "#FFD84D", "shine": "#FFFFFF"},
    },
}

ZONES = [
    ["Dog", "Chicken", "Cat", "Pig", "Bunny", "Sheep", "Bear", "Horse"],
    ["Bee", "Ladybug", "Butterfly", "Snail", "Frog", "Duckling", "Fox", "Deer"],
    ["Squirrel", "Hedgehog", "Owl", "Raccoon", "Wolf", "Moose", "Lynx", "Stag"],
    ["Crab", "Starfish", "Turtle", "Seagull", "Octopus", "Dolphin", "Shark", "Whale"],
    ["Bat", "Mole", "Spider", "Newt", "Scorpion", "Panther", "Golem", "Dragon"],
    ["Camel", "Meerkat", "Fennec", "Vulture", "Cobra", "Hyena", "Lion", "Anubis"],
    ["Lemming", "Penguin", "Seal", "Hare", "Yak", "Walrus", "Narwhal", "Yeti"],
    ["Gecko", "Iguana", "Beetle", "Salamander", "Phoenix", "Cerberus", "Basilisk", "Hydra"],
    ["Puffin", "Otter", "SnowLeopard", "PolarBear", "Sabertooth", "Mammoth", "FrostWolf", "FrostDragon"],
    ["Mouse", "Bot", "Drone", "Sprite", "Glitch", "Mecha", "Quantum", "Mainframe"],
    ["Unicorn", "Pegasus", "Griffin", "Kitsune", "Chimera", "Kraken", "Leviathan", "ElderDragon"],
]

LEGENDARIES = []
MYTHICS = []
