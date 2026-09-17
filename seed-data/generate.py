#!/usr/bin/env python3
"""Generates taxonomy.json and recipes.json for Norse Mixology (Phase 1).

Deterministic UUIDs (uuid5) are derived from human-readable slugs so the
script is idempotent and recipes can reference ingredients by slug while
the emitted JSON uses real UUIDs, matching the Swift `UUID` model fields.
"""
import json
import sys
import uuid
from pathlib import Path

NS = uuid.NAMESPACE_URL


def uid(slug: str) -> str:
    return str(uuid.uuid5(NS, "norsemixology:" + slug))


DIMS = ["sweetness", "bitterness", "smokiness", "citrus", "floral", "spice", "herbal", "fruity", "oaky"]


def profile(**kwargs) -> dict:
    p = {d: 0.0 for d in DIMS}
    p.update(kwargs)
    for d in DIMS:
        assert 0.0 <= p[d] <= 1.0, f"{d} out of range: {p[d]}"
    return p


# ---------------------------------------------------------------------------
# Taxonomy: category -> family -> styles
# Each style: slug, name, brands, abv=(min,max), profile
# ---------------------------------------------------------------------------

TAXONOMY = [
    ("spirit", "Spirit", [
        ("gin", "Gin", [
            ("gin_london_dry", "London Dry Gin", ["Tanqueray", "Beefeater", "Gordon's"], (37.5, 47.0),
             profile(sweetness=.1, bitterness=.2, citrus=.3, floral=.2, spice=.1, herbal=.7, fruity=.1)),
            ("gin_contemporary", "Contemporary Gin", ["Hendrick's", "Roku", "The Botanist"], (40.0, 44.0),
             profile(sweetness=.2, bitterness=.1, citrus=.4, floral=.6, spice=.1, herbal=.5, fruity=.3)),
            ("gin_old_tom", "Old Tom Gin", ["Hayman's Old Tom", "Ransom Old Tom"], (40.0, 47.0),
             profile(sweetness=.5, bitterness=.1, citrus=.2, floral=.2, spice=.1, herbal=.5, fruity=.1, oaky=.1)),
            ("gin_navy_strength", "Navy Strength Gin", ["Plymouth Navy Strength", "Perry's Tot"], (57.0, 58.0),
             profile(sweetness=.1, bitterness=.2, citrus=.3, floral=.2, spice=.3, herbal=.7, fruity=.1)),
            ("gin_genever", "Genever", ["Bols Genever", "Boomsma"], (35.0, 40.0),
             profile(sweetness=.3, bitterness=.1, smokiness=.1, citrus=.1, floral=.1, spice=.2, herbal=.4, fruity=.2, oaky=.3)),
        ]),
        ("vodka", "Vodka", [
            ("vodka_neutral", "Neutral Vodka", ["Absolut", "Grey Goose", "Tito's"], (37.5, 40.0),
             profile(sweetness=.1, floral=.1)),
            ("vodka_citrus", "Citrus-Flavoured Vodka", ["Absolut Citron", "Ketel One Citroen"], (35.0, 40.0),
             profile(sweetness=.1, citrus=.6, floral=.1, fruity=.2)),
        ]),
        ("rum", "Rum", [
            ("rum_white", "White/Blanco Rum", ["Bacardi Superior", "Havana Club 3yr"], (37.5, 40.0),
             profile(sweetness=.3, citrus=.1, floral=.1, spice=.1, fruity=.3)),
            ("rum_gold", "Gold/Aged Rum", ["Mount Gay Eclipse", "Appleton Estate Signature"], (40.0, 40.0),
             profile(sweetness=.4, bitterness=.1, floral=.1, spice=.2, fruity=.3, oaky=.4)),
            ("rum_dark", "Dark/Molasses Rum", ["Gosling's Black Seal", "Myers's"], (40.0, 45.0),
             profile(sweetness=.5, bitterness=.1, smokiness=.1, spice=.2, fruity=.3, oaky=.5)),
            ("rum_spiced", "Spiced Rum", ["Captain Morgan", "Sailor Jerry"], (35.0, 40.0),
             profile(sweetness=.5, bitterness=.1, smokiness=.1, citrus=.1, floral=.1, spice=.5, herbal=.1, fruity=.3, oaky=.3)),
            ("rum_agricole", "Agricole Rum", ["Rhum Clément", "Neisson"], (40.0, 50.0),
             profile(sweetness=.2, citrus=.1, floral=.2, spice=.2, herbal=.3, fruity=.3, oaky=.1)),
        ]),
        ("whiskey", "Whiskey", [
            ("whiskey_bourbon", "Bourbon", ["Buffalo Trace", "Maker's Mark", "Woodford Reserve"], (40.0, 50.0),
             profile(sweetness=.6, bitterness=.1, smokiness=.1, floral=.1, spice=.3, herbal=.1, fruity=.2, oaky=.6)),
            ("whiskey_rye", "Rye Whiskey", ["Rittenhouse", "Bulleit Rye"], (40.0, 50.0),
             profile(sweetness=.3, bitterness=.2, smokiness=.1, spice=.7, herbal=.2, fruity=.1, oaky=.5)),
            ("whiskey_irish", "Irish Whiskey", ["Jameson", "Redbreast"], (40.0, 40.0),
             profile(sweetness=.3, bitterness=.1, floral=.1, spice=.1, herbal=.1, fruity=.2, oaky=.3)),
            ("whiskey_scotch_blended", "Scotch Blended Whisky", ["Johnnie Walker Black", "Famous Grouse"], (40.0, 40.0),
             profile(sweetness=.3, bitterness=.1, smokiness=.2, floral=.1, spice=.1, herbal=.1, fruity=.2, oaky=.4)),
            ("whiskey_scotch_islay", "Scotch Single Malt (Islay)", ["Laphroaig", "Lagavulin"], (43.0, 46.0),
             profile(sweetness=.1, bitterness=.2, smokiness=.9, spice=.2, herbal=.1, fruity=.1, oaky=.5)),
            ("whiskey_scotch_speyside", "Scotch Single Malt (Speyside)", ["Glenlivet", "Macallan"], (40.0, 43.0),
             profile(sweetness=.4, bitterness=.1, smokiness=.1, floral=.2, spice=.1, herbal=.1, fruity=.4, oaky=.5)),
            ("whiskey_japanese", "Japanese Whisky", ["Suntory Toki", "Nikka From The Barrel"], (40.0, 43.0),
             profile(sweetness=.3, bitterness=.1, smokiness=.1, citrus=.1, floral=.2, spice=.1, herbal=.1, fruity=.3, oaky=.4)),
            ("whiskey_tennessee", "Tennessee Whiskey", ["Jack Daniel's", "George Dickel"], (40.0, 45.0),
             profile(sweetness=.5, bitterness=.1, smokiness=.1, floral=.1, spice=.2, herbal=.1, fruity=.2, oaky=.5)),
        ]),
        ("tequila_mezcal", "Tequila & Mezcal", [
            ("tequila_blanco", "Blanco Tequila", ["Espolòn Blanco", "Patrón Silver"], (38.0, 40.0),
             profile(sweetness=.1, bitterness=.1, citrus=.2, floral=.3, spice=.2, herbal=.4, fruity=.2)),
            ("tequila_reposado", "Reposado Tequila", ["Don Julio Reposado", "Herradura Reposado"], (38.0, 40.0),
             profile(sweetness=.2, bitterness=.1, citrus=.1, floral=.2, spice=.2, herbal=.3, fruity=.2, oaky=.3)),
            ("tequila_anejo", "Añejo Tequila", ["Don Julio Añejo", "Herradura Añejo"], (38.0, 40.0),
             profile(sweetness=.3, bitterness=.1, smokiness=.1, floral=.1, spice=.2, herbal=.2, fruity=.2, oaky=.5)),
            ("mezcal", "Mezcal", ["Del Maguey Vida", "Montelobos"], (40.0, 45.0),
             profile(sweetness=.1, bitterness=.2, smokiness=.8, citrus=.1, floral=.2, spice=.2, herbal=.4, fruity=.1, oaky=.1)),
        ]),
        ("brandy_cognac", "Brandy & Cognac", [
            ("cognac_vs", "VS Cognac", ["Hennessy VS", "Martell VS"], (40.0, 40.0),
             profile(sweetness=.3, bitterness=.1, citrus=.1, floral=.2, spice=.1, fruity=.4, oaky=.3)),
            ("cognac_vsop", "VSOP Cognac", ["Hennessy VSOP", "Rémy Martin VSOP"], (40.0, 40.0),
             profile(sweetness=.3, bitterness=.1, floral=.2, spice=.1, fruity=.4, oaky=.5)),
            ("pisco", "Pisco", ["Pisco Porton", "BarSol"], (38.0, 48.0),
             profile(sweetness=.2, citrus=.2, floral=.4, spice=.1, herbal=.1, fruity=.3)),
            ("calvados", "Calvados", ["Boulard", "Christian Drouin"], (40.0, 40.0),
             profile(sweetness=.3, bitterness=.1, floral=.1, spice=.2, fruity=.6, oaky=.3)),
        ]),
        ("other_spirits", "Other Spirits", [
            ("absinthe", "Absinthe", ["Pernod Absinthe", "Lucid"], (55.0, 74.0),
             profile(sweetness=.2, bitterness=.3, floral=.2, spice=.2, herbal=.9)),
            ("aquavit", "Aquavit", ["Linie Aquavit", "Krogstad"], (40.0, 40.0),
             profile(sweetness=.1, bitterness=.1, citrus=.1, floral=.1, spice=.5, herbal=.6)),
            ("cachaca", "Cachaça", ["Leblon", "Sagatiba"], (38.0, 40.0),
             profile(sweetness=.2, citrus=.1, floral=.1, spice=.1, fruity=.4)),
        ]),
    ]),
    ("liqueur", "Liqueur", [
        ("orange_liqueur", "Orange", [
            ("triple_sec", "Orange Triple Sec", ["Cointreau", "Combier"], (30.0, 40.0),
             profile(sweetness=.8, citrus=.8, floral=.1, fruity=.3)),
            ("orange_curacao", "Orange Curaçao", ["Grand Marnier"], (40.0, 40.0),
             profile(sweetness=.7, bitterness=.1, citrus=.7, floral=.1, spice=.1, fruity=.3, oaky=.2)),
        ]),
        ("coffee_liqueur_family", "Coffee", [
            ("coffee_liqueur", "Coffee Liqueur", ["Kahlúa", "Mr. Black"], (20.0, 26.0),
             profile(sweetness=.7, bitterness=.3, spice=.1, oaky=.1)),
        ]),
        ("almond_liqueur_family", "Almond", [
            ("amaretto", "Amaretto", ["Disaronno", "Lazzaroni"], (24.0, 28.0),
             profile(sweetness=.8, bitterness=.1, floral=.1, spice=.1, fruity=.2)),
        ]),
        ("herbal_liqueur_family", "Herbal", [
            ("chartreuse_green", "Green Chartreuse", ["Chartreuse Verte"], (55.0, 55.0),
             profile(sweetness=.4, bitterness=.3, citrus=.1, floral=.3, spice=.2, herbal=.9)),
            ("benedictine", "Bénédictine", ["Bénédictine D.O.M."], (40.0, 40.0),
             profile(sweetness=.6, bitterness=.1, citrus=.1, floral=.3, spice=.3, herbal=.6, fruity=.1, oaky=.1)),
        ]),
        ("berry_liqueur_family", "Berry/Fruit", [
            ("chambord", "Raspberry Liqueur", ["Chambord"], (16.5, 16.5),
             profile(sweetness=.8, floral=.1, fruity=.8)),
            ("peach_schnapps", "Peach Schnapps", ["DeKuyper Peachtree"], (15.0, 20.0),
             profile(sweetness=.8, floral=.2, fruity=.7)),
        ]),
        ("cream_liqueur_family", "Cream", [
            ("irish_cream", "Irish Cream", ["Baileys"], (17.0, 17.0),
             profile(sweetness=.7, bitterness=.1, spice=.1, oaky=.1)),
        ]),
        ("nut_liqueur_family", "Nut", [
            ("hazelnut_liqueur", "Hazelnut Liqueur", ["Frangelico"], (20.0, 24.0),
             profile(sweetness=.8, bitterness=.1, floral=.1, fruity=.1, oaky=.1)),
        ]),
        ("anise_liqueur_family", "Anise", [
            ("sambuca", "Sambuca", ["Luxardo Sambuca"], (38.0, 42.0),
             profile(sweetness=.8, bitterness=.1, floral=.1, spice=.1, herbal=.5)),
        ]),
        ("amaro_aperitif_family", "Amaro/Aperitif", [
            ("campari_style", "Bitter Aperitif", ["Campari"], (20.0, 28.5),
             profile(sweetness=.3, bitterness=.9, citrus=.3, floral=.1, spice=.1, herbal=.4, fruity=.2)),
            ("aperol_style", "Bitter Aperitivo", ["Aperol"], (11.0, 11.0),
             profile(sweetness=.5, bitterness=.5, citrus=.5, floral=.2, spice=.1, herbal=.3, fruity=.3)),
        ]),
    ]),
    ("wine_fortified", "Wine & Fortified", [
        ("vermouth", "Vermouth", [
            ("vermouth_dry", "Dry Vermouth", ["Dolin Dry", "Noilly Prat"], (15.0, 18.0),
             profile(sweetness=.2, bitterness=.3, citrus=.1, floral=.3, spice=.1, herbal=.6, fruity=.1)),
            ("vermouth_sweet", "Sweet/Rosso Vermouth", ["Carpano Antica", "Cocchi Storico"], (15.0, 18.0),
             profile(sweetness=.6, bitterness=.3, citrus=.1, floral=.2, spice=.2, herbal=.5, fruity=.3, oaky=.1)),
            ("vermouth_blanc", "Blanc Vermouth", ["Dolin Blanc"], (16.0, 18.0),
             profile(sweetness=.5, bitterness=.2, citrus=.1, floral=.4, spice=.1, herbal=.4, fruity=.2)),
        ]),
        ("sparkling", "Sparkling", [
            ("champagne", "Champagne/Sparkling Wine", ["Veuve Clicquot", "Moët"], (12.0, 12.0),
             profile(sweetness=.2, bitterness=.1, citrus=.2, floral=.2, fruity=.3, oaky=.1)),
            ("prosecco", "Prosecco", ["La Marca", "Mionetto"], (11.0, 11.0),
             profile(sweetness=.3, citrus=.2, floral=.2, fruity=.4)),
        ]),
        ("fortified", "Fortified", [
            ("sherry_fino", "Fino Sherry", ["Tio Pepe"], (15.0, 15.0),
             profile(sweetness=.1, bitterness=.2, citrus=.2, floral=.1, herbal=.3, fruity=.1, oaky=.1)),
            ("sherry_oloroso", "Oloroso Sherry", ["Lustau Oloroso"], (18.0, 20.0),
             profile(sweetness=.4, bitterness=.1, floral=.1, spice=.2, herbal=.1, fruity=.4, oaky=.5)),
            ("port_ruby", "Ruby Port", ["Graham's Six Grapes"], (19.0, 20.0),
             profile(sweetness=.8, bitterness=.1, floral=.1, spice=.2, fruity=.7, oaky=.2)),
            ("port_tawny", "Tawny Port", ["Taylor's Tawny"], (19.0, 20.0),
             profile(sweetness=.7, bitterness=.1, floral=.1, spice=.2, fruity=.5, oaky=.5)),
        ]),
    ]),
    ("mixer", "Mixer", [
        ("carbonated", "Carbonated", [
            ("club_soda", "Club Soda", ["San Pellegrino", "Schweppes Soda"], (0.0, 0.0), profile()),
            ("tonic_water", "Tonic Water", ["Fever-Tree", "Schweppes Tonic"], (0.0, 0.0),
             profile(sweetness=.3, bitterness=.5, citrus=.2, herbal=.1)),
            ("ginger_beer", "Ginger Beer", ["Fever-Tree Ginger Beer", "Bundaberg"], (0.0, 0.0),
             profile(sweetness=.4, citrus=.1, spice=.7, fruity=.1)),
            ("ginger_ale", "Ginger Ale", ["Canada Dry", "Fever-Tree Ginger Ale"], (0.0, 0.0),
             profile(sweetness=.5, citrus=.1, spice=.4, fruity=.1)),
            ("cola", "Cola", ["Coca-Cola", "Pepsi"], (0.0, 0.0),
             profile(sweetness=.8, bitterness=.1, spice=.2, herbal=.1, fruity=.1)),
            ("lemon_lime_soda", "Lemon-Lime Soda", ["Sprite", "7UP"], (0.0, 0.0),
             profile(sweetness=.7, citrus=.5, fruity=.1)),
        ]),
        ("juice", "Juice", [
            ("lime_juice", "Lime Juice", ["Freshly squeezed"], (0.0, 0.0),
             profile(sweetness=.1, bitterness=.1, citrus=.9, fruity=.2)),
            ("lemon_juice", "Lemon Juice", ["Freshly squeezed"], (0.0, 0.0),
             profile(sweetness=.1, bitterness=.1, citrus=.9, fruity=.2)),
            ("orange_juice", "Orange Juice", ["Freshly squeezed"], (0.0, 0.0),
             profile(sweetness=.5, citrus=.7, floral=.1, fruity=.5)),
            ("grapefruit_juice", "Grapefruit Juice", ["Freshly squeezed"], (0.0, 0.0),
             profile(sweetness=.3, bitterness=.3, citrus=.8, fruity=.3)),
            ("pineapple_juice", "Pineapple Juice", ["Dole", "Freshly pressed"], (0.0, 0.0),
             profile(sweetness=.6, citrus=.2, floral=.1, fruity=.7)),
            ("cranberry_juice", "Cranberry Juice", ["Ocean Spray"], (0.0, 0.0),
             profile(sweetness=.3, bitterness=.2, citrus=.3, fruity=.5)),
            ("tomato_juice", "Tomato Juice", ["Campbell's"], (0.0, 0.0),
             profile(sweetness=.2, bitterness=.1, citrus=.1, spice=.1, herbal=.1, fruity=.2)),
        ]),
        ("dairy_cream", "Dairy & Cream", [
            ("heavy_cream", "Heavy Cream", ["Any"], (0.0, 0.0), profile(sweetness=.2)),
            ("egg_white", "Egg White", ["Fresh egg"], (0.0, 0.0), profile()),
            ("coconut_cream", "Coconut Cream", ["Coco Lopez", "Coco Reàl"], (0.0, 0.0),
             profile(sweetness=.6, fruity=.3)),
        ]),
        ("other_mixer", "Other", [
            ("cold_brew", "Cold Brew Coffee", ["Any"], (0.0, 0.0),
             profile(sweetness=.1, bitterness=.5, smokiness=.1)),
        ]),
    ]),
    ("syrup", "Syrup", [
        ("syrup", "Syrup", [
            ("simple_syrup", "Simple Syrup", ["House-made 1:1"], (0.0, 0.0), profile(sweetness=1.0)),
            ("grenadine", "Grenadine", ["Small Hand Foods", "House-made"], (0.0, 0.0),
             profile(sweetness=.9, floral=.2, fruity=.6)),
            ("orgeat", "Orgeat", ["BG Reynolds", "House-made"], (0.0, 0.0),
             profile(sweetness=.8, floral=.3, fruity=.1)),
            ("honey_syrup", "Honey Syrup", ["House-made 1:1"], (0.0, 0.0), profile(sweetness=.9, floral=.3)),
            ("demerara_syrup", "Demerara Syrup", ["House-made"], (0.0, 0.0),
             profile(sweetness=.9, spice=.1, oaky=.2)),
            ("falernum", "Falernum", ["John D. Taylor's", "House-made"], (0.0, 0.0),
             profile(sweetness=.8, citrus=.3, floral=.1, spice=.4, herbal=.1, fruity=.2)),
            ("passion_fruit_syrup", "Passion Fruit Syrup", ["House-made"], (0.0, 0.0),
             profile(sweetness=.8, citrus=.1, floral=.2, fruity=.8)),
            ("ginger_syrup", "Ginger Syrup", ["House-made"], (0.0, 0.0),
             profile(sweetness=.8, citrus=.1, spice=.7)),
        ]),
    ]),
    ("fruit", "Fruit", [
        ("citrus_fresh", "Citrus", [
            ("fresh_lime", "Fresh Lime", ["Any"], (0.0, 0.0), profile(sweetness=.1, bitterness=.1, citrus=.9, fruity=.2)),
            ("fresh_lemon", "Fresh Lemon", ["Any"], (0.0, 0.0), profile(sweetness=.1, bitterness=.1, citrus=.9, fruity=.2)),
            ("fresh_orange", "Fresh Orange", ["Any"], (0.0, 0.0), profile(sweetness=.5, citrus=.6, floral=.1, fruity=.5)),
            ("fresh_grapefruit", "Fresh Grapefruit", ["Any"], (0.0, 0.0), profile(sweetness=.3, bitterness=.3, citrus=.8, fruity=.3)),
        ]),
        ("tropical_fresh", "Tropical", [
            ("fresh_pineapple", "Fresh Pineapple", ["Any"], (0.0, 0.0), profile(sweetness=.6, citrus=.2, floral=.1, fruity=.7)),
            ("fresh_mango", "Fresh Mango", ["Any"], (0.0, 0.0), profile(sweetness=.7, floral=.2, fruity=.8)),
            ("fresh_passion_fruit", "Fresh Passion Fruit", ["Any"], (0.0, 0.0), profile(sweetness=.5, bitterness=.1, citrus=.2, floral=.3, fruity=.8)),
        ]),
        ("berry_fresh", "Berry", [
            ("fresh_strawberry", "Fresh Strawberry", ["Any"], (0.0, 0.0), profile(sweetness=.6, floral=.1, fruity=.7)),
            ("fresh_raspberry", "Fresh Raspberry", ["Any"], (0.0, 0.0), profile(sweetness=.4, bitterness=.1, floral=.1, fruity=.7)),
        ]),
        ("stone_fruit_fresh", "Stone Fruit", [
            ("fresh_peach", "Fresh Peach", ["Any"], (0.0, 0.0), profile(sweetness=.6, floral=.2, fruity=.7)),
            ("fresh_cherry", "Fresh Cherry", ["Any", "Luxardo Maraschino Cherry"], (0.0, 0.0), profile(sweetness=.5, bitterness=.1, floral=.1, fruity=.7)),
        ]),
        ("other_fresh", "Other", [
            ("cucumber", "Cucumber", ["Any"], (0.0, 0.0), profile(sweetness=.1, floral=.1, herbal=.3, fruity=.1)),
            ("fresh_apple", "Fresh Apple", ["Any"], (0.0, 0.0), profile(sweetness=.4, citrus=.1, floral=.1, fruity=.6)),
        ]),
        ("herbs_fresh", "Herbs", [
            ("fresh_mint", "Fresh Mint", ["Any"], (0.0, 0.0), profile(bitterness=.1, floral=.1, spice=.1, herbal=.9)),
            ("fresh_basil", "Fresh Basil", ["Any"], (0.0, 0.0), profile(bitterness=.1, floral=.2, spice=.1, herbal=.8)),
            ("fresh_rosemary", "Fresh Rosemary", ["Any"], (0.0, 0.0), profile(bitterness=.1, floral=.1, spice=.2, herbal=.9)),
        ]),
    ]),
    ("garnish", "Garnish", [
        ("citrus_garnish", "Citrus", [
            ("lime_wedge", "Lime Wedge", ["Any"], (0.0, 0.0), profile(bitterness=.1, citrus=.6, fruity=.1)),
            ("lemon_twist", "Lemon Twist", ["Any"], (0.0, 0.0), profile(bitterness=.1, citrus=.5, floral=.2)),
            ("orange_wheel", "Orange Wheel", ["Any"], (0.0, 0.0), profile(sweetness=.2, citrus=.4, floral=.1, fruity=.3)),
        ]),
        ("savory_garnish", "Savory", [
            ("olive", "Olive", ["Castelvetrano", "Cocktail Olive"], (0.0, 0.0), profile(bitterness=.3, herbal=.1)),
            ("cocktail_onion", "Cocktail Onion", ["Any"], (0.0, 0.0), profile(bitterness=.1, spice=.2, herbal=.1)),
        ]),
        ("spice_garnish", "Spice", [
            ("cinnamon_stick", "Cinnamon Stick", ["Any"], (0.0, 0.0), profile(sweetness=.2, spice=.8, herbal=.1)),
        ]),
        ("salt_sugar_garnish", "Salt & Sugar", [
            ("salt_rim", "Kosher Salt Rim", ["Any"], (0.0, 0.0), profile(spice=.1)),
            ("sugar_rim", "Sugar Rim", ["Any"], (0.0, 0.0), profile(sweetness=.9)),
        ]),
        ("bitters_garnish", "Bitters", [
            ("angostura_bitters", "Angostura Bitters", ["Angostura"], (44.7, 44.7),
             profile(sweetness=.1, bitterness=.8, spice=.4, herbal=.3, oaky=.1)),
            ("peychauds_bitters", "Peychaud's Bitters", ["Peychaud's"], (35.0, 35.0),
             profile(sweetness=.1, bitterness=.7, citrus=.1, floral=.3, spice=.3, herbal=.2, fruity=.1)),
            ("orange_bitters", "Orange Bitters", ["Regans' No. 6", "Angostura Orange"], (28.0, 28.0),
             profile(sweetness=.1, bitterness=.6, citrus=.6, floral=.2, spice=.1, herbal=.1, fruity=.1)),
        ]),
    ]),
]

# ---------------------------------------------------------------------------
# Recipes: (name, description, glass, method, difficulty, tags, steps, ingredients)
# ingredients: (slug, amount, prep, optional, substituteNotes)
# ---------------------------------------------------------------------------


def ing(slug, amount, prep=None, optional=False, sub=None):
    return (slug, amount, prep, optional, sub)


RECIPES = [
    # ---------------- Gin ----------------
    ("Martini", "The classic dry, spirit-forward stirred cocktail.", "martini", "stir", "medium",
     ["classic", "spirit-forward", "iba-official"],
     ["Stir gin and vermouth with ice until well-chilled.", "Strain into a chilled martini glass.", "Garnish with a lemon twist or olive."],
     [ing("gin_london_dry", "60ml"), ing("vermouth_dry", "10ml"), ing("lemon_twist", "1", optional=True), ing("olive", "1", optional=True)]),
    ("Vesper", "James Bond's gin-and-vodka martini variant.", "martini", "stir", "medium",
     ["classic", "spirit-forward"],
     ["Stir all spirits with ice until well-chilled.", "Strain into a chilled martini glass.", "Garnish with a lemon twist."],
     [ing("gin_london_dry", "45ml"), ing("vodka_neutral", "15ml"), ing("vermouth_blanc", "7.5ml"), ing("lemon_twist", "1")]),
    ("Negroni", "Equal parts gin, vermouth, and bitter aperitif.", "rocks", "build", "easy",
     ["classic", "bitter", "iba-official"],
     ["Build all ingredients over ice in a rocks glass.", "Stir briefly.", "Garnish with an orange wheel."],
     [ing("gin_london_dry", "30ml"), ing("vermouth_sweet", "30ml"), ing("campari_style", "30ml"), ing("orange_wheel", "1")]),
    ("Tom Collins", "A tall, refreshing gin and lemon fizz.", "collins", "shake", "easy",
     ["classic", "tall", "refreshing", "iba-official"],
     ["Shake gin, lemon juice, and simple syrup with ice.", "Strain into a collins glass over fresh ice.", "Top with club soda.", "Garnish with a lemon twist."],
     [ing("gin_london_dry", "45ml"), ing("lemon_juice", "22ml"), ing("simple_syrup", "15ml"), ing("club_soda", "top"), ing("lemon_twist", "1")]),
    ("Gimlet", "Gin and lime cordial, shaken sharp and cold.", "coupe", "shake", "easy",
     ["classic", "sour", "iba-official"],
     ["Shake gin, lime juice, and simple syrup hard with ice.", "Double strain into a chilled coupe."],
     [ing("gin_contemporary", "60ml"), ing("lime_juice", "22ml"), ing("simple_syrup", "15ml")]),
    ("Bee's Knees", "Prohibition-era gin sour sweetened with honey.", "coupe", "shake", "easy",
     ["classic", "sour", "prohibition"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe.", "Garnish with a lemon twist."],
     [ing("gin_london_dry", "60ml"), ing("lemon_juice", "22ml"), ing("honey_syrup", "20ml"), ing("lemon_twist", "1", optional=True)]),
    ("Aviation", "Gin, maraschino, and crème de violette with a floral lift.", "coupe", "shake", "medium",
     ["classic", "sour"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe.", "Garnish with a cherry."],
     [ing("gin_london_dry", "45ml"), ing("lemon_juice", "15ml"), ing("chambord", "7.5ml", sub="Traditionally maraschino + crème de violette; raspberry liqueur is a workable single-bottle substitute for flavour balance."), ing("fresh_cherry", "1")]),
    ("French 75", "Gin and lemon topped with Champagne.", "flute", "shake", "easy",
     ["classic", "sparkling", "iba-official"],
     ["Shake gin, lemon juice, and simple syrup with ice.", "Strain into a flute.", "Top with Champagne.", "Garnish with a lemon twist."],
     [ing("gin_london_dry", "30ml"), ing("lemon_juice", "15ml"), ing("simple_syrup", "10ml"), ing("champagne", "top"), ing("lemon_twist", "1", optional=True)]),
    ("Gin Fizz", "A frothy gin sour lengthened with soda.", "highball", "shake", "medium",
     ["classic", "tall", "refreshing"],
     ["Dry shake gin, lemon juice, simple syrup, and egg white without ice.", "Shake again with ice.", "Strain into a highball glass.", "Top with club soda."],
     [ing("gin_london_dry", "45ml"), ing("lemon_juice", "22ml"), ing("simple_syrup", "15ml"), ing("egg_white", "15ml"), ing("club_soda", "top")]),
    ("Last Word", "An even-parts Prohibition classic of gin, Chartreuse, maraschino, and lime.", "coupe", "shake", "medium",
     ["classic", "even-parts", "prohibition"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("gin_london_dry", "20ml"), ing("chartreuse_green", "20ml"), ing("chambord", "20ml", sub="Traditionally maraschino liqueur; raspberry liqueur substitutes for sweetness/fruit, though the flavour profile is less almond-cherry."), ing("lime_juice", "20ml")]),
    ("Clover Club", "A pre-Prohibition gin sour with raspberry and egg white.", "coupe", "shake", "medium",
     ["classic", "sour", "prohibition"],
     ["Dry shake all ingredients without ice.", "Shake again with ice.", "Double strain into a chilled coupe."],
     [ing("gin_london_dry", "45ml"), ing("lemon_juice", "15ml"), ing("chambord", "15ml"), ing("simple_syrup", "7.5ml"), ing("egg_white", "15ml")]),
    ("Bramble", "Modern gin classic drizzled with blackberry liqueur.", "rocks", "build", "easy",
     ["modern-classic", "sour"],
     ["Shake gin, lemon juice, and simple syrup with ice.", "Strain over crushed ice in a rocks glass.", "Drizzle raspberry liqueur over the top.", "Garnish with a lemon wedge."],
     [ing("gin_london_dry", "50ml"), ing("lemon_juice", "20ml"), ing("simple_syrup", "10ml"), ing("chambord", "15ml", sub="Traditionally crème de mûre (blackberry); raspberry liqueur is the nearest bottled substitute."), ing("fresh_lemon", "1", prep="wedge")]),
    ("White Lady", "A gin sidecar variant with orange liqueur and lemon.", "coupe", "shake", "medium",
     ["classic", "sour"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("gin_london_dry", "45ml"), ing("triple_sec", "22ml"), ing("lemon_juice", "22ml")]),
    ("Singapore Sling", "A tall, fruity gin cocktail from Raffles Hotel.", "hurricane", "shake", "medium",
     ["classic", "tropical", "iba-official"],
     ["Shake gin, cherry, orange liqueur, pineapple juice, lime juice, grenadine, and bitters with ice.", "Strain into a hurricane glass over ice.", "Top with club soda.", "Garnish with a pineapple wedge."],
     [ing("gin_london_dry", "30ml"), ing("chambord", "15ml", sub="Traditionally Cherry Heering; raspberry liqueur is a rough single-bottle substitute for colour and fruit sweetness."), ing("orange_curacao", "7.5ml"), ing("pineapple_juice", "120ml"), ing("lime_juice", "15ml"), ing("grenadine", "10ml"), ing("angostura_bitters", "1 dash"), ing("club_soda", "top")]),
    ("Corpse Reviver No. 2", "A bracing pre-Prohibition equal-parts sour.", "coupe", "shake", "medium",
     ["classic", "even-parts"],
     ["Shake all liquid ingredients with ice.", "Double strain into a chilled coupe rinsed with absinthe."],
     [ing("gin_london_dry", "22ml"), ing("triple_sec", "22ml"), ing("vermouth_dry", "22ml", sub="Traditionally Lillet Blanc; dry vermouth is the nearest fortified-wine substitute."), ing("lemon_juice", "22ml"), ing("absinthe", "1 dash", prep="rinse")]),
    ("Southside", "A minty gin sour, a Prohibition-era favourite.", "coupe", "shake", "easy",
     ["classic", "sour", "herbal"],
     ["Muddle mint gently in a shaker.", "Add remaining ingredients and shake with ice.", "Double strain into a chilled coupe.", "Garnish with a mint sprig."],
     [ing("gin_london_dry", "60ml"), ing("lime_juice", "22ml"), ing("simple_syrup", "15ml"), ing("fresh_mint", "8 leaves", prep="muddled")]),
    ("Gin Rickey", "A bone-dry gin and lime highball.", "highball", "build", "easy",
     ["classic", "tall", "refreshing"],
     ["Build gin and lime juice over ice in a highball glass.", "Top with club soda.", "Garnish with a lime wedge."],
     [ing("gin_london_dry", "45ml"), ing("lime_juice", "15ml"), ing("club_soda", "top"), ing("lime_wedge", "1")]),
    ("Martinez", "A sweeter, Old Tom-based precursor to the Martini.", "coupe", "stir", "medium",
     ["classic", "spirit-forward"],
     ["Stir all ingredients with ice.", "Strain into a chilled coupe.", "Garnish with a lemon twist."],
     [ing("gin_old_tom", "45ml"), ing("vermouth_sweet", "45ml"), ing("chambord", "5ml", optional=True, sub="Traditionally a dash of maraschino; raspberry liqueur is optional here and can be omitted."), ing("angostura_bitters", "2 dash"), ing("lemon_twist", "1")]),
    ("Alaska", "A Martini variant sweetened with Chartreuse.", "coupe", "stir", "medium",
     ["classic", "spirit-forward"],
     ["Stir gin and Chartreuse with ice.", "Strain into a chilled coupe.", "Garnish with a lemon twist."],
     [ing("gin_london_dry", "50ml"), ing("chartreuse_green", "20ml"), ing("orange_bitters", "1 dash", optional=True), ing("lemon_twist", "1")]),
    ("Pegu Club", "A Burmese-colonial gin sour with orange liqueur and bitters.", "coupe", "shake", "medium",
     ["classic", "sour"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("gin_london_dry", "45ml"), ing("triple_sec", "22ml"), ing("lime_juice", "15ml"), ing("angostura_bitters", "1 dash"), ing("orange_bitters", "1 dash")]),
    ("Gin Basil Smash", "A muddled, herbaceous modern gin classic.", "rocks", "shake", "easy",
     ["modern-classic", "herbal", "refreshing"],
     ["Muddle basil with simple syrup in a shaker.", "Add gin and lemon juice, shake with ice.", "Double strain over fresh ice in a rocks glass.", "Garnish with a basil sprig."],
     [ing("gin_contemporary", "60ml"), ing("lemon_juice", "30ml"), ing("simple_syrup", "20ml"), ing("fresh_basil", "15 leaves", prep="muddled")]),
    ("Tuxedo", "An elegant, dry Martini-adjacent classic with maraschino and absinthe.", "coupe", "stir", "medium",
     ["classic", "spirit-forward"],
     ["Stir all ingredients with ice.", "Strain into a chilled coupe.", "Garnish with a lemon twist."],
     [ing("gin_london_dry", "45ml"), ing("vermouth_dry", "45ml"), ing("chambord", "5ml", sub="Traditionally maraschino liqueur; raspberry liqueur is a rough substitute."), ing("absinthe", "1 dash"), ing("orange_bitters", "1 dash"), ing("lemon_twist", "1")]),

    # ---------------- Whiskey ----------------
    ("Old Fashioned", "The archetypal spirit-forward whiskey cocktail.", "rocks", "build", "easy",
     ["classic", "spirit-forward", "iba-official"],
     ["Muddle sugar cube with bitters and a splash of water in a rocks glass.", "Add bourbon and a large ice cube.", "Stir until chilled.", "Garnish with an orange twist."],
     [ing("whiskey_bourbon", "60ml"), ing("demerara_syrup", "7.5ml"), ing("angostura_bitters", "2 dash"), ing("orange_wheel", "1")]),
    ("Manhattan", "Whiskey and sweet vermouth, stirred with bitters.", "coupe", "stir", "easy",
     ["classic", "spirit-forward", "iba-official"],
     ["Stir all ingredients with ice.", "Strain into a chilled coupe.", "Garnish with a cherry."],
     [ing("whiskey_rye", "60ml"), ing("vermouth_sweet", "30ml"), ing("angostura_bitters", "2 dash"), ing("fresh_cherry", "1")]),
    ("Whiskey Sour", "Bourbon shaken with lemon and sugar.", "rocks", "shake", "easy",
     ["classic", "sour", "iba-official"],
     ["Shake bourbon, lemon juice, and simple syrup with ice.", "Strain over fresh ice in a rocks glass.", "Garnish with an orange wheel and cherry."],
     [ing("whiskey_bourbon", "60ml"), ing("lemon_juice", "22ml"), ing("simple_syrup", "15ml"), ing("orange_wheel", "1", optional=True), ing("fresh_cherry", "1", optional=True)]),
    ("Mint Julep", "Crushed-ice bourbon classic from the American South.", "rocks", "build", "easy",
     ["classic", "herbal", "iba-official"],
     ["Muddle mint with simple syrup in a julep tin or rocks glass.", "Add bourbon and pack with crushed ice.", "Stir until frosted.", "Garnish with a mint sprig."],
     [ing("whiskey_bourbon", "60ml"), ing("demerara_syrup", "10ml"), ing("fresh_mint", "10 leaves", prep="muddled")]),
    ("Paper Plane", "An even-parts modern classic balancing bourbon, Aperol, amaro, and lemon.", "coupe", "shake", "medium",
     ["modern-classic", "even-parts"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("whiskey_bourbon", "22ml"), ing("aperol_style", "22ml"), ing("campari_style", "22ml", sub="Traditionally Amaro Nonino; a bitter aperitif substitutes with a sharper, more bitter edge."), ing("lemon_juice", "22ml")]),
    ("Sazerac", "New Orleans' rye and absinthe classic.", "rocks", "stir", "medium",
     ["classic", "spirit-forward", "iba-official"],
     ["Rinse a chilled rocks glass with absinthe and discard excess.", "Stir rye, simple syrup, and bitters with ice in a separate glass.", "Strain into the prepared glass (no ice).", "Garnish with a lemon twist."],
     [ing("whiskey_rye", "60ml"), ing("simple_syrup", "5ml"), ing("peychauds_bitters", "3 dash"), ing("absinthe", "1 dash", prep="rinse"), ing("lemon_twist", "1")]),
    ("Boulevardier", "A whiskey Negroni variant.", "rocks", "stir", "easy",
     ["classic", "bitter", "spirit-forward"],
     ["Stir all ingredients with ice.", "Strain over fresh ice in a rocks glass.", "Garnish with an orange twist."],
     [ing("whiskey_bourbon", "30ml"), ing("vermouth_sweet", "30ml"), ing("campari_style", "30ml"), ing("orange_wheel", "1")]),
    ("Whiskey Smash", "A muddled bourbon and lemon refresher.", "rocks", "shake", "easy",
     ["modern-classic", "refreshing", "herbal"],
     ["Muddle lemon and mint with simple syrup in a shaker.", "Add bourbon, shake with ice.", "Double strain over fresh ice in a rocks glass.", "Garnish with a mint sprig."],
     [ing("whiskey_bourbon", "60ml"), ing("fresh_lemon", "3", prep="wedges, muddled"), ing("simple_syrup", "15ml"), ing("fresh_mint", "8 leaves", prep="muddled")]),
    ("Irish Coffee", "Hot coffee, whiskey, and cream.", "mug", "build", "easy",
     ["warm", "classic"],
     ["Stir Irish whiskey and demerara syrup into hot coffee in a warmed mug.", "Gently float lightly whipped cream on top."],
     [ing("whiskey_irish", "45ml"), ing("cold_brew", "150ml", sub="Recipe calls for hot brewed coffee; cold brew is the nearest catalogued coffee ingredient — heat before using."), ing("demerara_syrup", "10ml"), ing("heavy_cream", "30ml", prep="lightly whipped")]),
    ("Hot Toddy", "A warming whiskey, honey, and lemon drink.", "mug", "build", "easy",
     ["warm", "classic"],
     ["Combine whiskey, honey syrup, and lemon juice in a warmed mug.", "Top with hot water.", "Garnish with a lemon wheel and cinnamon stick."],
     [ing("whiskey_bourbon", "45ml"), ing("honey_syrup", "15ml"), ing("lemon_juice", "15ml"), ing("cinnamon_stick", "1", optional=True)]),
    ("Rob Roy", "A Scotch-based Manhattan.", "coupe", "stir", "easy",
     ["classic", "spirit-forward"],
     ["Stir all ingredients with ice.", "Strain into a chilled coupe.", "Garnish with a cherry."],
     [ing("whiskey_scotch_blended", "60ml"), ing("vermouth_sweet", "30ml"), ing("angostura_bitters", "2 dash"), ing("fresh_cherry", "1")]),
    ("Blood and Sand", "An equal-parts Scotch cocktail with cherry, vermouth, and orange.", "coupe", "shake", "medium",
     ["classic", "even-parts"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("whiskey_scotch_blended", "20ml"), ing("chambord", "20ml", sub="Traditionally Cherry Heering; raspberry liqueur substitutes for colour and fruit."), ing("vermouth_sweet", "20ml"), ing("orange_juice", "20ml")]),
    ("Penicillin", "A modern classic layering smoky Scotch over honey-ginger whiskey.", "rocks", "shake", "medium",
     ["modern-classic", "smoky"],
     ["Shake blended Scotch, lemon juice, honey syrup, and ginger syrup with ice.", "Strain over fresh ice in a rocks glass.", "Float Islay Scotch on top.", "Garnish with a candied ginger piece."],
     [ing("whiskey_scotch_blended", "45ml"), ing("lemon_juice", "22ml"), ing("honey_syrup", "15ml"), ing("ginger_syrup", "10ml"), ing("whiskey_scotch_islay", "7.5ml", prep="float")]),
    ("Whiskey Highball", "Whiskey lengthened simply with soda over ice.", "highball", "build", "easy",
     ["classic", "tall", "refreshing"],
     ["Build whiskey over ice in a highball glass.", "Top with club soda and stir gently."],
     [ing("whiskey_scotch_blended", "45ml"), ing("club_soda", "top")]),
    ("Gold Rush", "A bourbon sour sweetened with honey.", "rocks", "shake", "easy",
     ["modern-classic", "sour"],
     ["Shake all ingredients with ice.", "Strain over fresh ice in a rocks glass."],
     [ing("whiskey_bourbon", "60ml"), ing("lemon_juice", "22ml"), ing("honey_syrup", "22ml")]),
    ("Vieux Carré", "A New Orleans stirred classic blending rye, cognac, and vermouth.", "rocks", "stir", "medium",
     ["classic", "spirit-forward"],
     ["Stir all ingredients with ice.", "Strain over fresh ice in a rocks glass.", "Garnish with a lemon twist."],
     [ing("whiskey_rye", "30ml"), ing("cognac_vs", "30ml"), ing("vermouth_sweet", "30ml"), ing("benedictine", "7.5ml"), ing("peychauds_bitters", "2 dash"), ing("angostura_bitters", "1 dash")]),
    ("New York Sour", "A Whiskey Sour topped with a red wine float.", "rocks", "shake", "medium",
     ["modern-classic", "sour"],
     ["Shake bourbon, lemon juice, and simple syrup with ice.", "Strain over fresh ice in a rocks glass.", "Float red wine on top."],
     [ing("whiskey_bourbon", "60ml"), ing("lemon_juice", "22ml"), ing("simple_syrup", "15ml"), ing("port_ruby", "20ml", prep="float", sub="Traditionally a dry red wine float; ruby port is the nearest catalogued wine and reads sweeter.")]),
    ("Ward 8", "A Boston Prohibition-era whiskey sour with grenadine.", "coupe", "shake", "easy",
     ["classic", "sour"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("whiskey_rye", "60ml"), ing("lemon_juice", "15ml"), ing("orange_juice", "15ml"), ing("grenadine", "10ml")]),
    ("Algonquin", "A rye, dry vermouth, and pineapple cocktail.", "coupe", "shake", "medium",
     ["classic", "sour"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("whiskey_rye", "45ml"), ing("vermouth_dry", "22ml"), ing("pineapple_juice", "22ml")]),
    ("Brown Derby", "A grapefruit and honey bourbon sour.", "rocks", "shake", "easy",
     ["modern-classic", "sour"],
     ["Shake all ingredients with ice.", "Strain over fresh ice in a rocks glass."],
     [ing("whiskey_bourbon", "60ml"), ing("grapefruit_juice", "30ml"), ing("honey_syrup", "15ml")]),
    ("Kentucky Mule", "A bourbon riff on the Moscow Mule.", "highball", "build", "easy",
     ["modern-classic", "tall", "refreshing"],
     ["Build bourbon and lime juice over ice in a copper mug or highball.", "Top with ginger beer.", "Garnish with a lime wedge."],
     [ing("whiskey_bourbon", "45ml"), ing("lime_juice", "15ml"), ing("ginger_beer", "top"), ing("lime_wedge", "1")]),
    ("Perfect Manhattan", "A Manhattan split between sweet and dry vermouth.", "coupe", "stir", "easy",
     ["classic", "spirit-forward"],
     ["Stir all ingredients with ice.", "Strain into a chilled coupe.", "Garnish with a lemon twist."],
     [ing("whiskey_rye", "60ml"), ing("vermouth_sweet", "15ml"), ing("vermouth_dry", "15ml"), ing("angostura_bitters", "2 dash"), ing("lemon_twist", "1")]),

    # ---------------- Rum ----------------
    ("Daiquiri", "Rum, lime, and sugar in perfect balance.", "coupe", "shake", "easy",
     ["classic", "sour", "iba-official"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("rum_white", "60ml"), ing("lime_juice", "22ml"), ing("simple_syrup", "15ml")]),
    ("Mojito", "Rum, lime, mint, and soda over crushed ice.", "highball", "build", "easy",
     ["classic", "tall", "refreshing", "iba-official"],
     ["Muddle mint with simple syrup and lime juice in a highball glass.", "Add rum and fill with crushed ice.", "Top with club soda and stir.", "Garnish with a mint sprig."],
     [ing("rum_white", "60ml"), ing("lime_juice", "22ml"), ing("simple_syrup", "15ml"), ing("fresh_mint", "10 leaves", prep="muddled"), ing("club_soda", "top")]),
    ("Dark 'n' Stormy", "Dark rum and spicy ginger beer.", "highball", "build", "easy",
     ["classic", "tall", "refreshing"],
     ["Fill a highball glass with ice.", "Add ginger beer.", "Float dark rum on top.", "Garnish with a lime wedge."],
     [ing("rum_dark", "50ml", prep="float"), ing("ginger_beer", "top"), ing("lime_wedge", "1")]),
    ("Mai Tai", "A tiki classic layering aged rums with orgeat and lime.", "rocks", "shake", "medium",
     ["classic", "tiki", "iba-official"],
     ["Shake rums, orange liqueur, orgeat, and lime juice with ice.", "Strain over crushed ice in a rocks glass.", "Garnish with mint and a lime shell."],
     [ing("rum_agricole", "30ml"), ing("rum_gold", "30ml"), ing("orange_curacao", "15ml"), ing("orgeat", "15ml"), ing("lime_juice", "22ml"), ing("fresh_mint", "1 sprig", optional=True)]),
    ("Piña Colada", "Blended rum, pineapple, and coconut cream.", "hurricane", "blend", "easy",
     ["classic", "tropical", "iba-official"],
     ["Blend all ingredients with a cup of ice until smooth.", "Pour into a hurricane glass.", "Garnish with a pineapple wedge and cherry."],
     [ing("rum_white", "60ml"), ing("pineapple_juice", "90ml"), ing("coconut_cream", "30ml"), ing("fresh_pineapple", "1 wedge", optional=True)]),
    ("Hurricane", "A New Orleans tiki classic loaded with fruit.", "hurricane", "shake", "medium",
     ["classic", "tiki", "tropical"],
     ["Shake all ingredients with ice.", "Strain over fresh ice in a hurricane glass.", "Garnish with an orange wheel and cherry."],
     [ing("rum_white", "45ml"), ing("rum_dark", "45ml"), ing("passion_fruit_syrup", "30ml"), ing("orange_juice", "30ml"), ing("lime_juice", "15ml"), ing("grenadine", "10ml")]),
    ("Rum Punch", "A crowd-friendly tropical rum punch.", "hurricane", "shake", "easy",
     ["tropical", "party"],
     ["Shake all ingredients with ice.", "Strain over fresh ice in a hurricane glass.", "Garnish with an orange wheel."],
     [ing("rum_gold", "60ml"), ing("orange_juice", "45ml"), ing("pineapple_juice", "45ml"), ing("grenadine", "15ml"), ing("lime_juice", "15ml")]),
    ("Zombie", "A strong, multi-rum tiki classic.", "hurricane", "shake", "advanced",
     ["classic", "tiki", "strong"],
     ["Shake all ingredients hard with ice.", "Strain over crushed ice in a hurricane glass.", "Garnish with a mint sprig."],
     [ing("rum_white", "30ml"), ing("rum_gold", "30ml"), ing("rum_dark", "30ml"), ing("lime_juice", "22ml"), ing("falernum", "15ml"), ing("grenadine", "10ml"), ing("angostura_bitters", "1 dash")]),
    ("Painkiller", "A rich, coconut-forward dark rum tiki drink.", "hurricane", "shake", "easy",
     ["tiki", "tropical"],
     ["Shake all ingredients with ice.", "Strain over crushed ice in a hurricane glass.", "Garnish with grated nutmeg."],
     [ing("rum_dark", "60ml"), ing("pineapple_juice", "60ml"), ing("orange_juice", "30ml"), ing("coconut_cream", "30ml")]),
    ("Jungle Bird", "A tiki classic balanced with bitter aperitif.", "rocks", "shake", "medium",
     ["modern-classic", "tiki", "bitter"],
     ["Shake all ingredients with ice.", "Strain over fresh ice in a rocks glass.", "Garnish with a pineapple wedge."],
     [ing("rum_dark", "45ml"), ing("campari_style", "22ml"), ing("pineapple_juice", "45ml"), ing("lime_juice", "15ml"), ing("simple_syrup", "10ml")]),
    ("Hemingway Daiquiri", "A tart, grapefruit-forward Daiquiri variant.", "coupe", "shake", "medium",
     ["modern-classic", "sour"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("rum_white", "60ml"), ing("chambord", "15ml", sub="Traditionally maraschino liqueur; raspberry liqueur substitutes with a fruitier profile."), ing("grapefruit_juice", "22ml"), ing("lime_juice", "15ml")]),
    ("El Presidente", "A refined Cuban rum and vermouth classic.", "coupe", "stir", "medium",
     ["classic", "spirit-forward"],
     ["Stir all ingredients with ice.", "Strain into a chilled coupe.", "Garnish with an orange twist."],
     [ing("rum_white", "45ml"), ing("vermouth_blanc", "22ml"), ing("orange_curacao", "10ml"), ing("grenadine", "5ml")]),
    ("Rum Old Fashioned", "An Old Fashioned reimagined with aged rum.", "rocks", "build", "easy",
     ["modern-classic", "spirit-forward"],
     ["Muddle demerara syrup with bitters in a rocks glass.", "Add rum and a large ice cube.", "Stir until chilled.", "Garnish with an orange twist."],
     [ing("rum_dark", "60ml"), ing("demerara_syrup", "7.5ml"), ing("angostura_bitters", "2 dash"), ing("orange_wheel", "1")]),

    # ---------------- Tequila & Mezcal ----------------
    ("Margarita", "Tequila, orange liqueur, and lime — perfectly balanced.", "rocks", "shake", "easy",
     ["classic", "sour", "iba-official"],
     ["Shake all ingredients with ice.", "Strain over fresh ice in a salt-rimmed rocks glass."],
     [ing("tequila_blanco", "50ml"), ing("triple_sec", "20ml"), ing("lime_juice", "20ml"), ing("salt_rim", "1", optional=True)]),
    ("Paloma", "Tequila and grapefruit soda, Mexico's favourite highball.", "highball", "build", "easy",
     ["classic", "tall", "refreshing"],
     ["Build tequila and lime juice over ice in a salt-rimmed highball glass.", "Top with grapefruit juice and club soda.", "Garnish with a lime wheel."],
     [ing("tequila_blanco", "50ml"), ing("lime_juice", "15ml"), ing("grapefruit_juice", "60ml"), ing("club_soda", "top"), ing("salt_rim", "1", optional=True)]),
    ("Tommy's Margarita", "A Margarita variant swapping triple sec for agave syrup.", "rocks", "shake", "easy",
     ["modern-classic", "sour"],
     ["Shake all ingredients with ice.", "Strain over fresh ice in a rocks glass."],
     [ing("tequila_blanco", "60ml"), ing("lime_juice", "22ml"), ing("simple_syrup", "15ml", sub="Traditionally agave syrup; simple syrup is the nearest catalogued sweetener.")]),
    ("Oaxacan Old Fashioned", "A smoky mezcal-tequila Old Fashioned.", "rocks", "build", "medium",
     ["modern-classic", "smoky", "spirit-forward"],
     ["Muddle agave syrup with bitters in a rocks glass.", "Add tequila and mezcal with a large ice cube.", "Stir until chilled.", "Garnish with an orange twist."],
     [ing("tequila_reposado", "45ml"), ing("mezcal", "15ml"), ing("demerara_syrup", "7.5ml", sub="Traditionally agave syrup; demerara syrup is the nearest catalogued sweetener."), ing("angostura_bitters", "2 dash"), ing("orange_wheel", "1")]),
    ("Tequila Sunrise", "Tequila, orange juice, and a grenadine sunrise.", "highball", "build", "easy",
     ["classic", "tall", "sweet"],
     ["Build tequila and orange juice over ice in a highball glass.", "Slowly pour grenadine down the side to settle at the bottom.", "Garnish with an orange wheel and cherry."],
     [ing("tequila_blanco", "45ml"), ing("orange_juice", "90ml"), ing("grenadine", "15ml"), ing("orange_wheel", "1", optional=True)]),
    ("Mezcal Negroni", "A smoky twist on the Negroni.", "rocks", "build", "easy",
     ["modern-classic", "bitter", "smoky"],
     ["Build all ingredients over ice in a rocks glass.", "Stir briefly.", "Garnish with an orange wheel."],
     [ing("mezcal", "30ml"), ing("vermouth_sweet", "30ml"), ing("campari_style", "30ml"), ing("orange_wheel", "1")]),
    ("El Diablo", "Tequila, cassis, lime, and ginger beer.", "highball", "build", "easy",
     ["modern-classic", "tall", "refreshing"],
     ["Build tequila, cassis, and lime juice over ice in a highball glass.", "Top with ginger beer.", "Garnish with a lime wheel."],
     [ing("tequila_blanco", "45ml"), ing("chambord", "15ml", sub="Traditionally crème de cassis; raspberry liqueur substitutes with a similar dark-berry sweetness."), ing("lime_juice", "15ml"), ing("ginger_beer", "top")]),
    ("Naked and Famous", "An even-parts smoky, bitter, herbal mezcal cocktail.", "coupe", "shake", "medium",
     ["modern-classic", "even-parts", "smoky"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("mezcal", "22ml"), ing("aperol_style", "22ml"), ing("chartreuse_green", "22ml"), ing("lime_juice", "22ml")]),
    ("Tequila Old Fashioned", "An Old Fashioned built on reposado tequila.", "rocks", "build", "easy",
     ["modern-classic", "spirit-forward"],
     ["Muddle agave syrup with bitters in a rocks glass.", "Add tequila and a large ice cube.", "Stir until chilled.", "Garnish with an orange twist."],
     [ing("tequila_reposado", "60ml"), ing("demerara_syrup", "7.5ml"), ing("angostura_bitters", "2 dash"), ing("orange_wheel", "1")]),

    # ---------------- Vodka ----------------
    ("Espresso Martini", "Vodka, coffee liqueur, and fresh espresso, shaken to a foam.", "coupe", "shake", "medium",
     ["modern-classic", "coffee"],
     ["Shake all ingredients hard with ice to build foam.", "Double strain into a chilled coupe.", "Garnish with three coffee beans."],
     [ing("vodka_neutral", "45ml"), ing("coffee_liqueur", "30ml"), ing("cold_brew", "30ml"), ing("simple_syrup", "5ml", optional=True)]),
    ("Moscow Mule", "Vodka, lime, and spicy ginger beer in a copper mug.", "highball", "build", "easy",
     ["classic", "tall", "refreshing"],
     ["Build vodka and lime juice over ice in a copper mug or highball.", "Top with ginger beer.", "Garnish with a lime wedge."],
     [ing("vodka_neutral", "45ml"), ing("lime_juice", "15ml"), ing("ginger_beer", "top"), ing("lime_wedge", "1")]),
    ("Cosmopolitan", "Vodka, orange liqueur, lime, and cranberry.", "coupe", "shake", "easy",
     ["classic", "sour"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe.", "Garnish with an orange twist."],
     [ing("vodka_citrus", "45ml"), ing("triple_sec", "15ml"), ing("cranberry_juice", "30ml"), ing("lime_juice", "15ml")]),
    ("White Russian", "Vodka, coffee liqueur, and cream over ice.", "rocks", "build", "easy",
     ["classic", "creamy"],
     ["Build vodka and coffee liqueur over ice in a rocks glass.", "Float cream on top."],
     [ing("vodka_neutral", "50ml"), ing("coffee_liqueur", "20ml"), ing("heavy_cream", "20ml", prep="float")]),
    ("Vodka Martini", "A Martini made with vodka in place of gin.", "martini", "stir", "easy",
     ["classic", "spirit-forward"],
     ["Stir vodka and vermouth with ice.", "Strain into a chilled martini glass.", "Garnish with a lemon twist or olive."],
     [ing("vodka_neutral", "60ml"), ing("vermouth_dry", "10ml"), ing("olive", "1", optional=True)]),
    ("Bloody Mary", "A savoury vodka and tomato juice brunch classic.", "highball", "build", "medium",
     ["classic", "savory", "brunch"],
     ["Build all ingredients over ice in a highball glass.", "Stir well.", "Garnish with a celery stalk and lime wedge."],
     [ing("vodka_neutral", "45ml"), ing("tomato_juice", "120ml"), ing("lime_juice", "15ml"), ing("angostura_bitters", "2 dash")]),
    ("Vodka Gimlet", "A Gimlet made with vodka.", "coupe", "shake", "easy",
     ["classic", "sour"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("vodka_neutral", "60ml"), ing("lime_juice", "22ml"), ing("simple_syrup", "15ml")]),
    ("Sea Breeze", "Vodka with cranberry and grapefruit.", "highball", "build", "easy",
     ["classic", "tall", "refreshing"],
     ["Build all ingredients over ice in a highball glass.", "Stir gently.", "Garnish with a lime wedge."],
     [ing("vodka_neutral", "45ml"), ing("cranberry_juice", "90ml"), ing("grapefruit_juice", "30ml"), ing("lime_wedge", "1", optional=True)]),
    ("Black Russian", "Vodka and coffee liqueur, unlengthened.", "rocks", "build", "easy",
     ["classic", "spirit-forward"],
     ["Build vodka and coffee liqueur over ice in a rocks glass.", "Stir briefly."],
     [ing("vodka_neutral", "50ml"), ing("coffee_liqueur", "20ml")]),
    ("Salty Dog", "Vodka and grapefruit in a salt-rimmed glass.", "highball", "build", "easy",
     ["classic", "tall", "refreshing"],
     ["Build vodka and grapefruit juice over ice in a salt-rimmed highball glass.", "Stir gently."],
     [ing("vodka_neutral", "45ml"), ing("grapefruit_juice", "120ml"), ing("salt_rim", "1")]),
    ("Screwdriver", "Vodka and orange juice, simply built.", "highball", "build", "easy",
     ["classic", "tall", "brunch"],
     ["Build vodka and orange juice over ice in a highball glass.", "Stir gently."],
     [ing("vodka_neutral", "45ml"), ing("orange_juice", "120ml")]),
    ("Vodka Collins", "A tall vodka and lemon fizz.", "collins", "shake", "easy",
     ["classic", "tall", "refreshing"],
     ["Shake vodka, lemon juice, and simple syrup with ice.", "Strain into a collins glass over fresh ice.", "Top with club soda.", "Garnish with a lemon wheel."],
     [ing("vodka_neutral", "45ml"), ing("lemon_juice", "22ml"), ing("simple_syrup", "15ml"), ing("club_soda", "top")]),
    ("Kamikaze", "A sharp, sweet-tart vodka shooter-turned-cocktail.", "coupe", "shake", "easy",
     ["classic", "sour"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("vodka_neutral", "30ml"), ing("triple_sec", "30ml"), ing("lime_juice", "30ml")]),
    ("Harvey Wallbanger", "A Screwdriver topped with a herbal liqueur float.", "highball", "build", "easy",
     ["classic", "tall"],
     ["Build vodka and orange juice over ice in a highball glass.", "Float Bénédictine on top."],
     [ing("vodka_neutral", "45ml"), ing("orange_juice", "120ml"), ing("benedictine", "15ml", prep="float", sub="Traditionally Galliano; Bénédictine is the nearest catalogued herbal liqueur.")]),

    # ---------------- Wine & Sparkling ----------------
    ("Aperol Spritz", "The ubiquitous low-ABV bitter aperitivo spritz.", "wine", "build", "easy",
     ["classic", "sparkling", "low-abv"],
     ["Fill a wine glass with ice.", "Add Aperol and Prosecco.", "Top with a splash of club soda.", "Garnish with an orange wheel."],
     [ing("aperol_style", "60ml"), ing("prosecco", "90ml"), ing("club_soda", "30ml"), ing("orange_wheel", "1")]),
    ("Kir Royale", "Champagne with a dash of cassis.", "flute", "build", "easy",
     ["classic", "sparkling"],
     ["Add cassis-style liqueur to a chilled flute.", "Top with Champagne."],
     [ing("chambord", "10ml", sub="Traditionally crème de cassis; raspberry liqueur substitutes with a similar berry sweetness."), ing("champagne", "top")]),
    ("Bellini", "Peach purée and Prosecco.", "flute", "build", "easy",
     ["classic", "sparkling", "brunch", "iba-official"],
     ["Add peach purée to a chilled flute.", "Top slowly with Prosecco.", "Stir gently."],
     [ing("fresh_peach", "1", prep="puréed"), ing("prosecco", "top")]),
    ("Mimosa", "Sparkling wine and orange juice, brunch's favourite.", "flute", "build", "easy",
     ["classic", "sparkling", "brunch"],
     ["Add orange juice to a chilled flute.", "Top with Champagne."],
     [ing("orange_juice", "60ml"), ing("champagne", "top")]),
    ("Americano", "A low-ABV precursor to the Negroni.", "highball", "build", "easy",
     ["classic", "bitter", "low-abv", "iba-official"],
     ["Build bitter aperitif and sweet vermouth over ice in a highball glass.", "Top with club soda.", "Garnish with an orange wheel."],
     [ing("campari_style", "30ml"), ing("vermouth_sweet", "30ml"), ing("club_soda", "top"), ing("orange_wheel", "1")]),
    ("Champagne Cocktail", "A sugar-and-bitters classic topped with Champagne.", "flute", "build", "easy",
     ["classic", "sparkling"],
     ["Place a sugar cube soaked in bitters in a flute.", "Top with Champagne.", "Garnish with a lemon twist."],
     [ing("angostura_bitters", "3 dash"), ing("simple_syrup", "5ml", sub="Traditionally a sugar cube; simple syrup is the nearest catalogued sweetener."), ing("champagne", "top"), ing("lemon_twist", "1", optional=True)]),
    ("Rossini", "A Bellini made with strawberry instead of peach.", "flute", "build", "easy",
     ["modern-classic", "sparkling", "brunch"],
     ["Add strawberry purée to a chilled flute.", "Top slowly with Prosecco.", "Stir gently."],
     [ing("fresh_strawberry", "3", prep="puréed"), ing("prosecco", "top")]),
    ("Poinsettia", "A festive cranberry Mimosa variant.", "flute", "build", "easy",
     ["modern-classic", "sparkling", "brunch"],
     ["Add cranberry juice and orange liqueur to a chilled flute.", "Top with Champagne."],
     [ing("cranberry_juice", "45ml"), ing("triple_sec", "10ml"), ing("champagne", "top")]),
    ("Black Velvet", "Stout and Champagne in equal measure.", "flute", "build", "easy",
     ["classic", "sparkling"],
     ["Pour Champagne into a chilled flute.", "Top slowly with stout, layering gently."],
     [ing("champagne", "75ml"), ing("cola", "75ml", sub="Traditionally stout beer; cola is the nearest catalogued carbonated mixer and changes the flavour significantly — best treated as a stand-in until a beer ingredient exists.")]),

    # ---------------- Brandy & Cognac ----------------
    ("Sidecar", "Cognac, orange liqueur, and lemon in a sugar-rimmed glass.", "coupe", "shake", "medium",
     ["classic", "sour", "iba-official"],
     ["Shake all ingredients with ice.", "Double strain into a sugar-rimmed chilled coupe."],
     [ing("cognac_vs", "50ml"), ing("triple_sec", "20ml"), ing("lemon_juice", "20ml"), ing("sugar_rim", "1", optional=True)]),
    ("Brandy Alexander", "A rich, dessert-like cognac and cream cocktail.", "coupe", "shake", "easy",
     ["classic", "creamy", "dessert"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe.", "Garnish with grated nutmeg."],
     [ing("cognac_vs", "30ml"), ing("hazelnut_liqueur", "30ml", sub="Traditionally crème de cacao; hazelnut liqueur substitutes with a nuttier sweetness."), ing("heavy_cream", "30ml")]),
    ("Between the Sheets", "A cognac-rum sour in the Sidecar family.", "coupe", "shake", "medium",
     ["classic", "sour"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("cognac_vs", "22ml"), ing("rum_white", "22ml"), ing("triple_sec", "22ml"), ing("lemon_juice", "15ml")]),
    ("Pisco Sour", "Peru's national cocktail, frothed with egg white.", "coupe", "shake", "medium",
     ["classic", "sour", "iba-official"],
     ["Dry shake all ingredients without ice.", "Shake again with ice.", "Double strain into a chilled coupe.", "Garnish with bitters drops on the foam."],
     [ing("pisco", "60ml"), ing("lime_juice", "22ml"), ing("simple_syrup", "15ml"), ing("egg_white", "15ml"), ing("angostura_bitters", "2 dash", prep="garnish")]),
    ("French Connection", "Cognac and amaretto, simply built over ice.", "rocks", "build", "easy",
     ["classic", "spirit-forward"],
     ["Build both ingredients over ice in a rocks glass.", "Stir briefly."],
     [ing("cognac_vs", "45ml"), ing("amaretto", "22ml")]),
    ("Jack Rose", "A tart apple brandy sour.", "coupe", "shake", "medium",
     ["classic", "sour"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("calvados", "60ml"), ing("lime_juice", "22ml"), ing("grenadine", "15ml")]),
    ("Metropolitan", "A brandy Cosmopolitan variant.", "coupe", "shake", "medium",
     ["modern-classic", "sour"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("cognac_vs", "45ml"), ing("chambord", "15ml"), ing("lime_juice", "15ml"), ing("simple_syrup", "10ml")]),

    # ---------------- Liqueur-forward ----------------
    ("Amaretto Sour", "A nutty, tart amaretto sour.", "rocks", "shake", "easy",
     ["classic", "sour"],
     ["Shake all ingredients with ice.", "Strain over fresh ice in a rocks glass.", "Garnish with a cherry."],
     [ing("amaretto", "60ml"), ing("lemon_juice", "22ml"), ing("simple_syrup", "10ml"), ing("egg_white", "15ml", optional=True), ing("fresh_cherry", "1", optional=True)]),
    ("Grasshopper", "A minty, dessert-like cream cocktail.", "coupe", "shake", "easy",
     ["classic", "creamy", "dessert"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("chartreuse_green", "22ml", sub="Traditionally crème de menthe; green Chartreuse substitutes with a stronger herbal intensity — use less to taste."), ing("hazelnut_liqueur", "22ml", sub="Traditionally white crème de cacao; hazelnut liqueur substitutes with a nuttier sweetness."), ing("heavy_cream", "22ml")]),
    ("Godfather", "Scotch and amaretto, simply built.", "rocks", "build", "easy",
     ["classic", "spirit-forward"],
     ["Build both ingredients over ice in a rocks glass.", "Stir briefly."],
     [ing("whiskey_scotch_blended", "45ml"), ing("amaretto", "22ml")]),
    ("Godmother", "Vodka and amaretto, simply built.", "rocks", "build", "easy",
     ["classic", "spirit-forward"],
     ["Build both ingredients over ice in a rocks glass.", "Stir briefly."],
     [ing("vodka_neutral", "45ml"), ing("amaretto", "22ml")]),
    ("Negroni Sbagliato", "A Negroni with Prosecco standing in for gin.", "rocks", "build", "easy",
     ["modern-classic", "bitter", "sparkling"],
     ["Build sweet vermouth and bitter aperitif over ice in a rocks glass.", "Top with Prosecco.", "Garnish with an orange wheel."],
     [ing("vermouth_sweet", "30ml"), ing("campari_style", "30ml"), ing("prosecco", "30ml"), ing("orange_wheel", "1")]),
    ("French Martini", "Vodka, raspberry liqueur, and pineapple, shaken frothy.", "coupe", "shake", "easy",
     ["modern-classic", "fruity"],
     ["Shake all ingredients hard with ice.", "Double strain into a chilled coupe."],
     [ing("vodka_neutral", "45ml"), ing("chambord", "15ml"), ing("pineapple_juice", "30ml")]),
    ("Golden Cadillac", "A dessert-style cream cocktail with orange liqueur and cream.", "coupe", "shake", "easy",
     ["classic", "creamy", "dessert"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("hazelnut_liqueur", "22ml", sub="Traditionally Galliano; hazelnut liqueur is the nearest catalogued sweet herbal-adjacent liqueur."), ing("orange_curacao", "22ml"), ing("heavy_cream", "22ml")]),
    ("Toasted Almond", "A dessert-style coffee and amaretto cream cocktail.", "rocks", "shake", "easy",
     ["classic", "creamy", "dessert"],
     ["Shake all ingredients with ice.", "Strain over fresh ice in a rocks glass."],
     [ing("amaretto", "30ml"), ing("coffee_liqueur", "30ml"), ing("heavy_cream", "30ml")]),
    ("Stinger", "Cognac and crème de menthe, stirred sharp.", "rocks", "stir", "easy",
     ["classic", "spirit-forward"],
     ["Stir both ingredients with ice.", "Strain over fresh ice in a rocks glass."],
     [ing("cognac_vs", "60ml"), ing("chartreuse_green", "22ml", sub="Traditionally white crème de menthe; green Chartreuse substitutes with far more herbal intensity — use less to taste.")]),

    # ---------------- Low-ABV / No-ABV ----------------
    ("Virgin Mojito", "All the mint and lime of a Mojito, no rum.", "highball", "build", "easy",
     ["no-abv", "tall", "refreshing"],
     ["Muddle mint with simple syrup and lime juice in a highball glass.", "Fill with crushed ice.", "Top with club soda and stir.", "Garnish with a mint sprig."],
     [ing("lime_juice", "22ml"), ing("simple_syrup", "15ml"), ing("fresh_mint", "10 leaves", prep="muddled"), ing("club_soda", "top")]),
    ("Shirley Temple", "Ginger ale and grenadine, a classic mocktail.", "highball", "build", "easy",
     ["no-abv", "tall", "kid-friendly"],
     ["Fill a highball glass with ice.", "Add grenadine.", "Top with ginger ale.", "Garnish with a cherry."],
     [ing("grenadine", "15ml"), ing("ginger_ale", "top"), ing("fresh_cherry", "1")]),
    ("Arnold Palmer Spritz", "Iced tea and lemonade with a sparkling top.", "highball", "build", "easy",
     ["no-abv", "tall", "refreshing"],
     ["Fill a highball glass with ice.", "Add cold brew and lemon juice with simple syrup.", "Top with lemon-lime soda.", "Stir gently."],
     [ing("cold_brew", "60ml", sub="Traditionally iced black tea; cold brew coffee is the nearest catalogued cold infused base — swap for brewed iced tea if preferred."), ing("lemon_juice", "15ml"), ing("simple_syrup", "10ml"), ing("lemon_lime_soda", "top")]),
    ("Ginger Mule (Non-Alcoholic)", "A spicy, zero-proof take on the Moscow Mule.", "highball", "build", "easy",
     ["no-abv", "tall", "refreshing"],
     ["Build lime juice over ice in a copper mug or highball.", "Top with ginger beer.", "Garnish with a lime wedge."],
     [ing("lime_juice", "15ml"), ing("ginger_beer", "top"), ing("lime_wedge", "1")]),
    ("Cucumber Cooler (Non-Alcoholic)", "A crisp, herbal cucumber refresher.", "highball", "shake", "easy",
     ["no-abv", "tall", "refreshing", "herbal"],
     ["Muddle cucumber with lime juice and simple syrup in a shaker.", "Shake with ice.", "Strain into a highball glass over fresh ice.", "Top with club soda."],
     [ing("cucumber", "4 slices", prep="muddled"), ing("lime_juice", "15ml"), ing("simple_syrup", "10ml"), ing("club_soda", "top")]),
    ("Virgin Piña Colada", "A zero-proof Piña Colada.", "hurricane", "blend", "easy",
     ["no-abv", "tropical"],
     ["Blend all ingredients with a cup of ice until smooth.", "Pour into a hurricane glass.", "Garnish with a pineapple wedge."],
     [ing("pineapple_juice", "120ml"), ing("coconut_cream", "45ml"), ing("fresh_pineapple", "1 wedge", optional=True)]),
    ("Passion Fruit Spritz (Non-Alcoholic)", "A bright, tropical zero-proof spritz.", "wine", "build", "easy",
     ["no-abv", "sparkling", "tropical"],
     ["Fill a wine glass with ice.", "Add passion fruit syrup and lime juice.", "Top with club soda.", "Garnish with a lime wheel."],
     [ing("passion_fruit_syrup", "30ml"), ing("lime_juice", "10ml"), ing("club_soda", "top")]),

    # ---------------- Warm ----------------
    ("Mulled Wine", "Red wine warmed with spice and citrus.", "mug", "build", "easy",
     ["warm", "classic", "seasonal"],
     ["Warm red wine gently with demerara syrup, cinnamon, and orange in a saucepan (do not boil).", "Ladle into a warmed mug.", "Garnish with a cinnamon stick."],
     [ing("port_ruby", "150ml", sub="Traditionally still red wine gently mulled; ruby port is the nearest catalogued red wine and is noticeably sweeter/stronger — dilute with water to taste."), ing("demerara_syrup", "10ml"), ing("cinnamon_stick", "1"), ing("orange_wheel", "1")]),
    ("Hot Buttered Rum", "Dark rum warmed with butter and spice.", "mug", "build", "medium",
     ["warm", "classic", "seasonal"],
     ["Combine dark rum and demerara syrup in a warmed mug.", "Top with hot water.", "Stir in a small pat of butter.", "Garnish with a cinnamon stick."],
     [ing("rum_dark", "45ml"), ing("demerara_syrup", "15ml"), ing("cinnamon_stick", "1")]),
    ("Tom and Jerry", "A festive warm eggnog-style rum and brandy punch.", "mug", "build", "advanced",
     ["warm", "classic", "seasonal"],
     ["Whip egg white and yolk separately, then fold together with sugar into a batter.", "Add rum and cognac to a warmed mug with a spoonful of batter.", "Top with hot water or milk and stir.", "Garnish with grated nutmeg."],
     [ing("rum_dark", "30ml"), ing("cognac_vs", "30ml"), ing("egg_white", "15ml"), ing("simple_syrup", "10ml"), ing("heavy_cream", "60ml", sub="Traditionally hot milk; heavy cream is the nearest catalogued dairy ingredient — thin with hot water to taste.")]),

    # ---------------- Additional classics (gin) ----------------
    ("Bronx", "A Martini-Manhattan hybrid with orange juice.", "coupe", "shake", "medium",
     ["classic", "sour"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("gin_london_dry", "45ml"), ing("vermouth_dry", "15ml"), ing("vermouth_sweet", "15ml"), ing("orange_juice", "15ml")]),
    ("Income Tax Cocktail", "A Bronx sharpened with bitters.", "coupe", "shake", "medium",
     ["classic", "sour"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("gin_london_dry", "45ml"), ing("vermouth_dry", "15ml"), ing("vermouth_sweet", "15ml"), ing("orange_juice", "15ml"), ing("angostura_bitters", "2 dash")]),
    ("Journalist", "A layered, six-ingredient gin classic.", "coupe", "shake", "medium",
     ["classic", "spirit-forward"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("gin_london_dry", "45ml"), ing("vermouth_dry", "15ml"), ing("vermouth_sweet", "15ml"), ing("triple_sec", "7.5ml"), ing("lemon_juice", "7.5ml"), ing("angostura_bitters", "2 dash")]),
    ("Monkey Gland", "A curious gin, orange, and absinthe classic.", "coupe", "shake", "medium",
     ["classic", "sour"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("gin_london_dry", "50ml"), ing("orange_juice", "20ml"), ing("grenadine", "5ml"), ing("absinthe", "1 dash")]),
    ("Pink Lady", "A frothy pink gin sour from the Jazz Age.", "coupe", "shake", "medium",
     ["classic", "sour"],
     ["Dry shake all ingredients without ice.", "Shake again with ice.", "Double strain into a chilled coupe."],
     [ing("gin_london_dry", "45ml"), ing("calvados", "15ml", sub="Traditionally applejack; calvados is the nearest catalogued apple brandy."), ing("lemon_juice", "15ml"), ing("grenadine", "10ml"), ing("egg_white", "15ml")]),
    ("Casino", "A refined pre-Prohibition gin classic.", "coupe", "shake", "medium",
     ["classic", "spirit-forward"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("gin_london_dry", "50ml"), ing("chambord", "5ml", sub="Traditionally maraschino liqueur; raspberry liqueur is a rough substitute."), ing("orange_bitters", "2 dash"), ing("lemon_juice", "5ml")]),
    ("Alexander", "A gin-based dessert cocktail, cousin to the Brandy Alexander.", "coupe", "shake", "easy",
     ["classic", "creamy", "dessert"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe.", "Garnish with grated nutmeg."],
     [ing("gin_london_dry", "30ml"), ing("hazelnut_liqueur", "30ml", sub="Traditionally crème de cacao; hazelnut liqueur substitutes with a nuttier sweetness."), ing("heavy_cream", "30ml")]),
    ("Suffering Bastard", "A gin-and-cognac tiki cooler with ginger beer.", "highball", "build", "medium",
     ["classic", "tiki", "tall"],
     ["Build gin, cognac, lime juice, and bitters over ice in a highball glass.", "Top with ginger beer.", "Garnish with a mint sprig and cucumber."],
     [ing("gin_london_dry", "22ml"), ing("cognac_vs", "22ml"), ing("lime_juice", "15ml"), ing("angostura_bitters", "2 dash"), ing("ginger_beer", "top")]),

    # ---------------- Additional classics (whiskey) ----------------
    ("Presbyterian", "Whiskey lengthened with ginger ale and soda.", "highball", "build", "easy",
     ["classic", "tall", "refreshing"],
     ["Build whiskey over ice in a highball glass.", "Top with equal parts ginger ale and club soda."],
     [ing("whiskey_bourbon", "45ml"), ing("ginger_ale", "top"), ing("club_soda", "top")]),
    ("Horse's Neck", "Whiskey and ginger ale with a long lemon spiral.", "highball", "build", "easy",
     ["classic", "tall"],
     ["Drape a long lemon peel spiral inside a highball glass.", "Fill with ice and add whiskey.", "Top with ginger ale."],
     [ing("whiskey_bourbon", "45ml"), ing("ginger_ale", "top"), ing("lemon_twist", "1", prep="long spiral peel")]),
    ("Whiskey Ginger", "The simplest whiskey highball.", "highball", "build", "easy",
     ["classic", "tall"],
     ["Build whiskey over ice in a highball glass.", "Top with ginger ale."],
     [ing("whiskey_bourbon", "45ml"), ing("ginger_ale", "top")]),
    ("Black Manhattan", "A Manhattan made bittersweet with a bitter aperitif.", "coupe", "stir", "medium",
     ["modern-classic", "spirit-forward", "bitter"],
     ["Stir all ingredients with ice.", "Strain into a chilled coupe.", "Garnish with a cherry."],
     [ing("whiskey_rye", "60ml"), ing("campari_style", "30ml"), ing("angostura_bitters", "2 dash"), ing("fresh_cherry", "1")]),
    ("Remember the Maine", "A smoky, cherry-tinged rye Manhattan variant.", "coupe", "stir", "medium",
     ["classic", "spirit-forward", "smoky"],
     ["Stir all ingredients with ice.", "Strain into a chilled coupe.", "Garnish with a cherry."],
     [ing("whiskey_rye", "60ml"), ing("vermouth_sweet", "30ml"), ing("chambord", "7.5ml", sub="Traditionally cherry brandy; raspberry liqueur is the nearest catalogued substitute."), ing("absinthe", "1 dash")]),
    ("Trinidad Sour", "An unconventional modern classic built on Angostura bitters.", "coupe", "shake", "medium",
     ["modern-classic", "sour", "bitter"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("angostura_bitters", "45ml"), ing("orgeat", "22ml"), ing("lemon_juice", "22ml"), ing("whiskey_rye", "15ml")]),

    # ---------------- Additional classics (rum) ----------------
    ("Bacardi Cocktail", "A pink, lime-forward Daiquiri variant.", "coupe", "shake", "easy",
     ["classic", "sour", "iba-official"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("rum_white", "60ml"), ing("lime_juice", "22ml"), ing("grenadine", "10ml")]),
    ("Corn 'n Oil", "A rich, dark rum and falernum sipper.", "rocks", "build", "easy",
     ["classic", "tiki", "spirit-forward"],
     ["Build all ingredients over ice in a rocks glass.", "Stir briefly."],
     [ing("rum_dark", "60ml"), ing("falernum", "15ml"), ing("lime_juice", "10ml"), ing("angostura_bitters", "2 dash")]),
    ("Bee's Kiss", "A honeyed, creamy rum dessert sip.", "coupe", "shake", "easy",
     ["classic", "creamy", "dessert"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("rum_white", "45ml"), ing("honey_syrup", "15ml"), ing("heavy_cream", "15ml")]),
    ("Scorpion", "A tiki punch blending rum and cognac.", "hurricane", "shake", "medium",
     ["classic", "tiki"],
     ["Shake all ingredients with ice.", "Strain over crushed ice in a hurricane glass.", "Garnish with a mint sprig."],
     [ing("rum_white", "45ml"), ing("cognac_vs", "15ml"), ing("orange_juice", "45ml"), ing("orgeat", "15ml"), ing("lime_juice", "22ml")]),
    ("Navy Grog", "A three-rum tiki grog with citrus and honey.", "hurricane", "shake", "medium",
     ["classic", "tiki"],
     ["Shake all ingredients with ice.", "Strain over crushed ice in a hurricane glass."],
     [ing("rum_white", "22ml"), ing("rum_gold", "22ml"), ing("rum_dark", "22ml"), ing("lime_juice", "15ml"), ing("grapefruit_juice", "15ml"), ing("honey_syrup", "15ml")]),
    ("Kingston Negroni", "A Negroni built on funky Jamaican-style dark rum.", "rocks", "build", "easy",
     ["modern-classic", "bitter"],
     ["Build all ingredients over ice in a rocks glass.", "Stir briefly.", "Garnish with an orange wheel."],
     [ing("rum_dark", "30ml"), ing("vermouth_sweet", "30ml"), ing("campari_style", "30ml"), ing("orange_wheel", "1")]),
    ("Air Mail", "A Cuban rum classic topped with Champagne.", "flute", "shake", "medium",
     ["classic", "sparkling"],
     ["Shake rum, lime juice, and honey syrup with ice.", "Strain into a flute.", "Top with Champagne."],
     [ing("rum_gold", "45ml"), ing("lime_juice", "15ml"), ing("honey_syrup", "15ml"), ing("champagne", "top")]),

    # ---------------- Additional classics (tequila/vodka) ----------------
    ("Matador", "A simple, tropical tequila and pineapple sour.", "coupe", "shake", "easy",
     ["modern-classic", "tropical"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("tequila_blanco", "45ml"), ing("pineapple_juice", "45ml"), ing("lime_juice", "15ml")]),
    ("Brave Bull", "Tequila and coffee liqueur, simply built.", "rocks", "build", "easy",
     ["classic", "spirit-forward", "coffee"],
     ["Build both ingredients over ice in a rocks glass.", "Stir briefly."],
     [ing("tequila_blanco", "45ml"), ing("coffee_liqueur", "22ml")]),
    ("Conquistador", "A creamy tequila and coffee dessert cocktail.", "rocks", "shake", "easy",
     ["modern-classic", "creamy", "dessert"],
     ["Shake all ingredients with ice.", "Strain over fresh ice in a rocks glass."],
     [ing("tequila_blanco", "45ml"), ing("coffee_liqueur", "22ml"), ing("heavy_cream", "22ml")]),
    ("Chi-Chi", "A vodka Piña Colada.", "hurricane", "blend", "easy",
     ["classic", "tropical"],
     ["Blend all ingredients with a cup of ice until smooth.", "Pour into a hurricane glass.", "Garnish with a pineapple wedge."],
     [ing("vodka_neutral", "45ml"), ing("pineapple_juice", "90ml"), ing("coconut_cream", "30ml")]),
    ("Vodka Sour", "A straightforward vodka sour.", "rocks", "shake", "easy",
     ["classic", "sour"],
     ["Shake all ingredients with ice.", "Strain over fresh ice in a rocks glass."],
     [ing("vodka_neutral", "60ml"), ing("lemon_juice", "22ml"), ing("simple_syrup", "15ml")]),
    ("Greyhound", "Vodka and grapefruit, unrimmed.", "highball", "build", "easy",
     ["classic", "tall"],
     ["Build both ingredients over ice in a highball glass.", "Stir gently."],
     [ing("vodka_neutral", "45ml"), ing("grapefruit_juice", "120ml")]),
    ("Cape Codder", "Vodka, cranberry, and a squeeze of lime.", "highball", "build", "easy",
     ["classic", "tall"],
     ["Build all ingredients over ice in a highball glass.", "Stir gently."],
     [ing("vodka_neutral", "45ml"), ing("cranberry_juice", "120ml"), ing("lime_juice", "10ml")]),
    ("Madras", "Vodka with cranberry and orange juice.", "highball", "build", "easy",
     ["classic", "tall"],
     ["Build all ingredients over ice in a highball glass.", "Stir gently."],
     [ing("vodka_neutral", "45ml"), ing("cranberry_juice", "60ml"), ing("orange_juice", "60ml")]),
    ("Woo Woo", "Vodka, peach schnapps, and cranberry.", "rocks", "shake", "easy",
     ["classic", "sweet"],
     ["Shake all ingredients with ice.", "Strain over fresh ice in a rocks glass."],
     [ing("vodka_neutral", "30ml"), ing("peach_schnapps", "30ml"), ing("cranberry_juice", "45ml")]),
    ("Sex on the Beach", "A fruity vodka and peach schnapps highball.", "highball", "shake", "easy",
     ["classic", "tall", "sweet"],
     ["Shake all ingredients with ice.", "Strain over fresh ice in a highball glass."],
     [ing("vodka_neutral", "30ml"), ing("peach_schnapps", "15ml"), ing("orange_juice", "45ml"), ing("cranberry_juice", "45ml")]),
    ("Fuzzy Navel", "Peach schnapps and orange juice, easygoing and sweet.", "highball", "build", "easy",
     ["classic", "tall", "sweet"],
     ["Build both ingredients over ice in a highball glass.", "Stir gently."],
     [ing("peach_schnapps", "45ml"), ing("orange_juice", "120ml")]),
    ("Pink Squirrel", "A pastel, almond-forward dessert cocktail.", "coupe", "shake", "easy",
     ["classic", "creamy", "dessert"],
     ["Shake all ingredients with ice.", "Double strain into a chilled coupe."],
     [ing("amaretto", "22ml", sub="Traditionally crème de noyaux (almond liqueur); amaretto is the nearest catalogued almond-flavoured liqueur."), ing("hazelnut_liqueur", "22ml", sub="Traditionally white crème de cacao; hazelnut liqueur substitutes with a nuttier sweetness."), ing("heavy_cream", "22ml")]),

    # ---------------- Additional low/no-ABV and warm ----------------
    ("Spiced Apple Cider (Warm, Non-Alcoholic)", "A warming, spiced zero-proof cider.", "mug", "build", "easy",
     ["warm", "no-abv", "seasonal"],
     ["Warm pressed apple with ginger syrup and cinnamon in a saucepan.", "Pour into a warmed mug.", "Garnish with a cinnamon stick."],
     [ing("fresh_apple", "150ml", prep="pressed to juice"), ing("ginger_syrup", "15ml"), ing("cinnamon_stick", "1")]),
    ("Grapefruit Rosemary Spritz (Non-Alcoholic)", "A bright, herbal zero-proof spritz.", "wine", "shake", "easy",
     ["no-abv", "sparkling", "herbal", "refreshing"],
     ["Muddle rosemary with honey syrup in a shaker.", "Add grapefruit juice, shake with ice.", "Strain into a wine glass over ice.", "Top with club soda.", "Garnish with a rosemary sprig."],
     [ing("grapefruit_juice", "60ml"), ing("fresh_rosemary", "1 sprig", prep="muddled"), ing("honey_syrup", "10ml"), ing("club_soda", "top")]),

    # ---------------- A few more, for margin above the 150 target ----------------
    ("Salty Chihuahua", "A tequila Greyhound, rimmed with salt.", "highball", "build", "easy",
     ["modern-classic", "tall"],
     ["Build tequila and grapefruit juice over ice in a salt-rimmed highball glass.", "Stir gently."],
     [ing("tequila_blanco", "45ml"), ing("grapefruit_juice", "120ml"), ing("salt_rim", "1")]),
    ("Batanga", "A rustic tequila and cola highball, stirred with a knife.", "highball", "build", "easy",
     ["classic", "tall"],
     ["Build tequila and lime juice over ice in a salt-rimmed highball glass.", "Top with cola and stir."],
     [ing("tequila_blanco", "45ml"), ing("lime_juice", "10ml"), ing("cola", "top"), ing("salt_rim", "1", optional=True)]),
    ("Ranch Water", "A minimal, bone-dry tequila and soda cooler.", "highball", "build", "easy",
     ["modern-classic", "tall", "refreshing"],
     ["Build tequila and lime juice over ice in a highball glass.", "Top with club soda."],
     [ing("tequila_blanco", "45ml"), ing("lime_juice", "15ml"), ing("club_soda", "top")]),
    ("Bamboo", "A dry, sherry-based aperitif classic.", "coupe", "stir", "medium",
     ["classic", "spirit-forward", "low-abv"],
     ["Stir all ingredients with ice.", "Strain into a chilled coupe.", "Garnish with a lemon twist."],
     [ing("sherry_fino", "45ml"), ing("vermouth_dry", "45ml"), ing("orange_bitters", "2 dash"), ing("lemon_twist", "1", optional=True)]),
    ("Adonis", "A sherry and sweet vermouth aperitif, gentle and dry.", "coupe", "stir", "medium",
     ["classic", "spirit-forward", "low-abv"],
     ["Stir all ingredients with ice.", "Strain into a chilled coupe.", "Garnish with an orange twist."],
     [ing("sherry_fino", "45ml"), ing("vermouth_sweet", "30ml"), ing("orange_bitters", "2 dash")]),
    ("Widow's Kiss", "An opulent apple brandy classic layered with herbal liqueurs.", "coupe", "stir", "advanced",
     ["classic", "spirit-forward"],
     ["Stir all ingredients with ice.", "Strain into a chilled coupe."],
     [ing("calvados", "45ml"), ing("benedictine", "22ml"), ing("chartreuse_green", "22ml"), ing("angostura_bitters", "2 dash")]),
    ("Cable Car", "A spiced-rum Sidecar variant with a cinnamon-sugar rim.", "coupe", "shake", "medium",
     ["modern-classic", "sour"],
     ["Shake all ingredients with ice.", "Double strain into a cinnamon-sugar-rimmed chilled coupe."],
     [ing("rum_spiced", "45ml"), ing("triple_sec", "15ml"), ing("lemon_juice", "15ml"), ing("cinnamon_stick", "1", optional=True)]),
    ("Jamaican Mule", "A funky dark-rum riff on the Moscow Mule.", "highball", "build", "easy",
     ["modern-classic", "tall", "refreshing"],
     ["Build dark rum and lime juice over ice in a copper mug or highball.", "Top with ginger beer.", "Garnish with a lime wedge."],
     [ing("rum_dark", "45ml"), ing("lime_juice", "15ml"), ing("ginger_beer", "top"), ing("lime_wedge", "1")]),
]


def build_taxonomy():
    categories_json = []
    style_lookup = {}  # slug -> (uuid, categoryId, familyId, flavorProfile dict)
    for cat_slug, cat_name, families in TAXONOMY:
        cat_id = uid("category:" + cat_slug)
        families_json = []
        for fam_slug, fam_name, styles in families:
            fam_id = uid("family:" + cat_slug + ":" + fam_slug)
            styles_json = []
            for style_slug, style_name, brands, abv_range, prof in styles:
                style_id = uid("style:" + style_slug)
                abv_min, abv_max = abv_range
                full_profile = dict(prof)
                full_profile["abv"] = round((abv_min + abv_max) / 2, 2)
                style_obj = {
                    "id": style_id,
                    "name": style_name,
                    "familyId": fam_id,
                    "categoryId": cat_id,
                    "exampleBrands": brands,
                    "flavorProfile": full_profile,
                    "abvMin": abv_min,
                    "abvMax": abv_max,
                }
                styles_json.append(style_obj)
                assert style_slug not in style_lookup, f"duplicate style slug {style_slug}"
                style_lookup[style_slug] = (style_id, cat_id, fam_id, full_profile, cat_name)
            families_json.append({
                "id": fam_id,
                "name": fam_name,
                "categoryId": cat_id,
                "styles": styles_json,
            })
        categories_json.append({
            "id": cat_id,
            "name": cat_name,
            "families": families_json,
        })
    return categories_json, style_lookup


ROLE_WEIGHT_BY_CATEGORY = {
    "Spirit": 1.0,
    "Liqueur": 0.7,
    "Wine & Fortified": 0.6,
    "Mixer": 0.4,
    "Syrup": 0.5,
    "Fruit": 0.4,
    "Garnish": 0.15,
}


def compute_recipe_profile(ingredient_slugs_with_optional, style_lookup):
    total_weight = 0.0
    acc = {d: 0.0 for d in DIMS}
    acc["abv"] = 0.0
    for slug, optional in ingredient_slugs_with_optional:
        if optional:
            continue
        _id, _cat_id, _fam_id, prof, cat_name = style_lookup[slug]
        w = ROLE_WEIGHT_BY_CATEGORY.get(cat_name, 0.3)
        total_weight += w
        for d in DIMS:
            acc[d] += prof[d] * w
        acc["abv"] += prof["abv"] * w
    if total_weight == 0:
        return {**{d: 0.0 for d in DIMS}, "abv": 0.0}
    result = {d: round(acc[d] / total_weight, 3) for d in DIMS}
    result["abv"] = round(acc["abv"] / total_weight, 2)
    return result


GLASS_MAP = {
    "coupe": "coupe", "rocks": "rocks", "highball": "highball", "martini": "martini",
    "collins": "collins", "hurricane": "hurricane", "flute": "flute", "wine": "wineGlass",
    "mug": "mug",
}
METHOD_MAP = {"shake": "shake", "stir": "stir", "build": "build", "blend": "blend", "throw": "throw"}
DIFFICULTY_MAP = {"easy": "easy", "medium": "medium", "advanced": "advanced"}


def build_recipes(style_lookup):
    recipes_json = []
    seen_names = set()
    for (name, desc, glass, method, difficulty, tags, steps, ingredients) in RECIPES:
        assert name not in seen_names, f"duplicate recipe name {name}"
        seen_names.add(name)
        recipe_id = uid("recipe:" + name)
        ingredient_objs = []
        slug_optional_pairs = []
        for (slug, amount, prep, optional, sub) in ingredients:
            assert slug in style_lookup, f"{name}: unknown ingredient slug {slug}"
            style_id, *_ = style_lookup[slug]
            ingredient_objs.append({
                "ingredientStyleId": style_id,
                "amount": amount,
                "preparation": prep,
                "isOptional": optional,
                "substituteNotes": sub,
            })
            slug_optional_pairs.append((slug, optional))
        flavor_profile = compute_recipe_profile(slug_optional_pairs, style_lookup)
        recipes_json.append({
            "id": recipe_id,
            "name": name,
            "description": desc,
            "glassType": GLASS_MAP[glass],
            "method": METHOD_MAP[method],
            "ingredients": ingredient_objs,
            "steps": steps,
            "flavorProfile": flavor_profile,
            "tags": tags,
            "difficulty": DIFFICULTY_MAP[difficulty],
            "imageURL": None,
        })
    return recipes_json


def main():
    categories_json, style_lookup = build_taxonomy()
    total_styles = sum(len(f["styles"]) for c in categories_json for f in c["families"])
    print(f"Ingredient styles: {total_styles}")
    assert total_styles >= 60, f"need >=60 styles, got {total_styles}"

    recipes_json = build_recipes(style_lookup)
    print(f"Recipes: {len(recipes_json)}")
    assert len(recipes_json) >= 150, f"need >=150 recipes, got {len(recipes_json)}"

    # Referential integrity check
    valid_style_ids = {v[0] for v in style_lookup.values()}
    for r in recipes_json:
        for i in r["ingredients"]:
            assert i["ingredientStyleId"] in valid_style_ids, f"dangling ref in {r['name']}"

    # Flavour profile sanity: every style profile sums > 0 (excluding pure water-like items like club soda,
    # egg white, salt rim which are legitimately flavourless — check separately)
    zero_profile_slugs = []
    for slug, (sid, cid, fid, prof, cat_name) in style_lookup.items():
        s = sum(prof[d] for d in DIMS)
        if s == 0:
            zero_profile_slugs.append(slug)
    print(f"Zero-flavour styles (expected: neutral bases like club soda/egg white/salt/heavy cream/plain fruit): {zero_profile_slugs}")

    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "taxonomy.json").write_text(json.dumps(categories_json, indent=2, ensure_ascii=False), encoding="utf-8")
    (out_dir / "recipes.json").write_text(json.dumps(recipes_json, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Wrote {out_dir / 'taxonomy.json'} and {out_dir / 'recipes.json'}")


if __name__ == "__main__":
    main()
