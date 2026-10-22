"""The maps after Meadow, as they get designed (Cave and on are still Coming Soon in the game). Meadow's
eight live in cubelings.py (SPECIES, built by blocky.py). Add each new map here as a ZONES row when its
animals are made, in Steal an Egg's style: real animals of blocks with Lego studs (blocky.py), eight a map,
two of each rarity.
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
}

ZONES = [
    ["Dog", "Chicken", "Cat", "Pig", "Bunny", "Sheep", "Bear", "Horse"],
    ["Bee", "Ladybug", "Butterfly", "Snail", "Frog", "Duckling", "Fox", "Deer"],
    ["Squirrel", "Hedgehog", "Owl", "Raccoon", "Wolf", "Moose", "Lynx", "Stag"],
    ["Crab", "Starfish", "Turtle", "Seagull", "Octopus", "Dolphin", "Shark", "Whale"],
]

LEGENDARIES = []
MYTHICS = []
