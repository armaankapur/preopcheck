#!/usr/bin/env python3
"""
Builds PreOpCheck/DrugNames.txt from the FDA National Drug Code directory.

The app uses this list for exactly one thing: deciding whether a word on a
scanned page is a drug at all, so it can mark drugs the PARC guideline does
not cover in red. It carries no clinical instruction.

Each line is:   name<TAB>ingredient
"ingredient" is the generic name the product is sold under, so brand names and
generic names of the same drug share a key (tylenol -> acetaminophen,
vitamin d3 -> cholecalciferol). The scanner uses the key to avoid marking the
same drug twice when a page prints both.

Usage:
    1. Download https://download.open.fda.gov/drug/ndc/drug-ndc-0001-of-0001.json.zip
       and unzip it (public domain, ~250 MB unzipped).
    2. python3 tools/build_drug_lexicon.py /path/to/drug-ndc-0001-of-0001.json
    3. Check the printed probes, then commit PreOpCheck/DrugNames.txt.
"""

import collections
import json
import random
import re
import sys
from pathlib import Path

if len(sys.argv) != 2:
    sys.exit("usage: build_drug_lexicon.py <drug-ndc-0001-of-0001.json>")

OUT = Path(__file__).resolve().parent.parent / "PreOpCheck" / "DrugNames.txt"
data = json.load(open(sys.argv[1]))["results"]


def normalize(s):
    s = s.lower().replace("’", "'")
    s = re.sub(r"[^a-z0-9 ]+", " ", s)
    return " ".join(s.split())


english = set(w.strip().lower() for w in open("/usr/share/dict/words"))

# Words that mark a marketing or product-type name rather than a drug name.
NOISE = set("""relief allergy daily hand hands soap sanitizer sanitizing sunscreen spf
moisturizer moisturizing lotion cream wash shampoo conditioner antibacterial mouthwash toothpaste
extra strength maximum childrens children child infant infants nighttime daytime severe sinus
cough chest congestion formula original plus care body face skin eye eyes drop drops gel foam
spray wipes wipe kit pack pads pad patch tablets tablet capsules capsule liquid oral solution
first aid medicated nasal multi symptom all day night hour hr fast acting junior adult men women
baby kids kid ultra advanced complete total clear fresh mint cherry grape orange lemon honey vapor
rub rinse scrub cleanser cleansing bar antiseptic alcohol antiperspirant deodorant sun protection
broad spectrum tinted lip balm acne treatment itch anti fever reducer reliever sleep aid stomach
heartburn gas laxative stool softener fiber antacid headache migraine muscle joint back arthritis
cold sore wart remover corn callus foot powder diaper rash ointment petroleum jelly hydrating
repair moisture defense use ready prefilled syringe injection vial bag concentrate premix
compounded compounding convenience value size count ct oz fl ml mg mcg pain prep swab swabs
towelette towelettes serum growth hair whole leaf root flower flowering bark seed pollen
nosode mold fungi""".split())

# Supplements and umbrella names the FDA does not track as drugs but which
# appear on medication lists constantly. name -> ingredient key.
EXTRAS = {
    "melatonin": "melatonin", "fish oil": "fish oil", "omega 3": "fish oil",
    "probiotic": "probiotic", "probiotics": "probiotic",
    "coenzyme q10": "coenzyme q10", "coq10": "coenzyme q10",
    "turmeric": "turmeric", "curcumin": "turmeric", "elderberry": "elderberry",
    "echinacea": "echinacea", "magnesium": "magnesium", "calcium": "calcium",
    "potassium": "potassium", "iron": "iron", "zinc": "zinc", "selenium": "selenium",
    "chromium": "chromium",
    "vitamin a": "vitamin a", "vitamin b": "vitamin b complex",
    "vitamin b1": "thiamine", "thiamine": "thiamine",
    "vitamin b2": "riboflavin", "riboflavin": "riboflavin",
    "vitamin b6": "pyridoxine", "pyridoxine": "pyridoxine",
    "vitamin b12": "cyanocobalamin", "cyanocobalamin": "cyanocobalamin",
    "vitamin c": "ascorbic acid", "ascorbic acid": "ascorbic acid",
    "vitamin d": "cholecalciferol", "vitamin d3": "cholecalciferol", "cholecalciferol": "cholecalciferol",
    "vitamin d2": "ergocalciferol", "ergocalciferol": "ergocalciferol",
    "vitamin e": "tocopherol", "tocopherol": "tocopherol",
    "vitamin k": "phytonadione", "phytonadione": "phytonadione",
    "folic acid": "folic acid", "folate": "folic acid",
    "biotin": "biotin", "niacin": "niacin", "multivitamin": "multivitamin",
    "prenatal vitamin": "multivitamin", "glucosamine": "glucosamine",
    "chondroitin": "chondroitin", "creatine": "creatine", "l theanine": "l theanine",
    "ashwagandha": "ashwagandha", "ginkgo": "ginkgo", "ginseng": "ginseng",
    "garlic": "garlic", "kava": "kava", "valerian": "valerian",
    "st johns wort": "st johns wort", "saw palmetto": "saw palmetto",
    "cranberry": "cranberry", "flaxseed": "flaxseed", "insulin": "insulin",
    "collagen": "collagen", "protein powder": "protein powder",
    "electrolytes": "electrolytes", "pedialyte": "electrolytes", "miralax": "polyethylene glycol 3350",
}


def clean(key, max_words):
    words = [t for t in key.split() if not t.isdigit()]
    # Strengths and pack sizes baked into a name ("81mg", "spf40") disqualify
    # it, but short vitamin-style tags (d3, b12, q10) are fine.
    if any(re.search(r"\d", t) and not re.fullmatch(r"[a-z]\d{1,2}|q10|b\d{1,2}", t) for t in words):
        return None
    key = " ".join(words)
    if len(key) < 4 or len(words) > max_words:
        return None
    if any(w in NOISE for w in words):
        return None
    return key


def generic_parts(name):
    for part in re.split(r",|\band\b|/|;", name):
        if k := clean(normalize(part), 4):
            yield k


# Salt / ester suffixes that do not change which drug it is. Same idea as the
# matcher's list, so "atorvastatin calcium" and "atorvastatin" share a key.
SALTS = set("""hcl hydrochloride sodium potassium calcium succinate tartrate besylate maleate
mesylate fumarate citrate sulfate acetate phosphate bitartrate napsylate propionate furoate
dipropionate valerate hydrobromide bromide chloride nitrate mononitrate magnesium trihydrate
monohydrate dihydrate anhydrous disodium tromethamine pamoate decanoate enanthate""".split())


def ingredient_key(generic):
    words = generic.split()
    while len(words) > 1 and words[-1] in SALTS:
        words.pop()
    return " ".join(words)


names = {}                                   # name -> ingredient key
brand_votes = collections.defaultdict(collections.Counter)

for p in data:
    if "HUMAN" not in (p.get("product_type") or ""):
        continue                              # veterinary, bulk, etc.
    if "HOMEOPATHIC" in (p.get("marketing_category") or "").upper():
        continue
    if any("[hp_" in (i.get("strength") or "") for i in p.get("active_ingredients", [])):
        continue                              # homeopathic potency units

    parts = list(generic_parts(p.get("generic_name") or ""))
    for i in p.get("active_ingredients", []):
        parts += list(generic_parts(i.get("name") or ""))
    for g in parts:
        names.setdefault(g, ingredient_key(g))

    # The product's own ingredient key: its full generic name if clean,
    # otherwise its first ingredient. Single-ingredient products are far
    # more trustworthy for naming a brand than combination products
    # ("Flonase Headache and Allergy" must not make Flonase mean
    # acetaminophen), so they get a much heavier vote.
    full = clean(normalize(p.get("generic_name") or ""), 4)
    product_key = ingredient_key(full) if full else (parts[0] if parts else None)
    if not product_key:
        continue
    unique_parts = {ingredient_key(x) for x in parts}
    weight = 10 if len(unique_parts) <= 1 else 1

    for field in ("brand_name", "brand_name_base"):
        b = p.get(field)
        if not b:
            continue
        k = clean(normalize(b), 3)
        if not k:
            continue
        words = k.split()
        if len(words) == 1 and k in english and k not in names:
            continue                          # "Degree", "Dove": ordinary words
        brand_votes[k][product_key] += weight

for brand, votes in brand_votes.items():
    names.setdefault(brand, votes.most_common(1)[0][0])

for name, key in EXTRAS.items():
    names[name] = key

with open(OUT, "w") as f:
    for name in sorted(names):
        f.write(f"{name}\t{names[name]}\n")

print(f"wrote {len(names)} names to {OUT} ({OUT.stat().st_size // 1024} KB)")
random.seed(7)
print("sample:", random.sample(sorted(names), 25))
print("brand -> ingredient checks:")
for b in ["tylenol", "lipitor", "flonase", "fluticasone", "norvasc", "zoloft", "vitamin d3",
          "cholecalciferol", "atorvastatin", "ozempic", "advil", "claritin", "glucophage", "proair hfa"]:
    print(f"  {b:16} -> {names.get(b, '--')}")
expect = {"flonase": "fluticasone", "tylenol": "acetaminophen", "lipitor": "atorvastatin",
          "norvasc": "amlodipine", "zoloft": "sertraline", "vitamin d3": "cholecalciferol",
          "advil": "ibuprofen", "claritin": "loratadine", "ozempic": "semaglutide"}
wrong = {b: names.get(b) for b, k in expect.items() if names.get(b) != k}
print("PAIRING CHECK:", wrong or "all correct")
bad = ["discontinue", "route", "oral", "inhalation", "nostril", "describe", "renew", "results", "dose",
       "every", "once", "twice", "daily", "tablet", "medications", "active", "home", "summary",
       "chart", "review", "plan", "orders", "name", "doe", "john", "aconitum napellus",
       "pain relief patch", "lidocaine 4"]
print("MUST BE OUT:", [b for b in bad if b in names] or "all absent")
