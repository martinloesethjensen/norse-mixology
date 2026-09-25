# Catalog Repo & Publishing Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the public `norse-catalog` repo that validates the catalog and publishes content-hashed JSON plus a manifest to GitHub Pages.

**Architecture:** `generate.py` (moved from the app repo) emits `taxonomy.json` / `recipes.json`. `catalog/validate.py` enforces invariants; `catalog/build.py` runs generate → validate → writes `site/v1/` (hashed files, `manifest.json`, `history.json`, last 3 versions retained). The author runs the build locally and commits `site/`; CI re-runs the idempotent build, fails if `site/` would change, and deploys `site/` to Pages. CI never writes to the repo.

**Tech Stack:** Python 3 standard library only (code must run on Python 3.9 locally and 3.12 in CI; tests use `unittest`), GitHub Actions, GitHub Pages.

**Spec:** `/Users/mlj/dev/norse-mixology/docs/superpowers/specs/2026-09-23-catalog-delivery-design.md` (§2, §5 rows 1–5)

**This is Plan 1 of 2.** Plan 2 (`2026-09-23-ios-sqlite-catalog.md`) builds the iOS client; its final tasks need this plan's Pages URL to be live.

## Global Constraints

- Repo: `norse-catalog`, **public**, local path `/Users/mlj/dev/norse-catalog`, owner GitHub account `martinloesethjensen`.
- Pages base URL: `https://martinloesethjensen.github.io/norse-catalog/`; published paths live under `/v1/`.
- `manifest.json` fields exactly: `schemaVersion` (int, `1`), `contentVersion` (first 8 hex of `sha256(taxonomy_sha256_hex + recipes_sha256_hex)`), `generatedAt` (`YYYY-MM-DDTHH:MM:SSZ`, UTC), `taxonomy` / `recipes` objects with `path`, `sha256` (64 lowercase hex), `bytes` (int).
- Hashed filenames: `taxonomy.<first 8 hex of sha256>.json`, `recipes.<first 8 hex of sha256>.json`.
- Keep the hashed files referenced by the current + previous 2 manifests (3 versions); prune older.
- Each published JSON file ≤ 1,000,000 bytes.
- Enum values must match the iOS decoders exactly — glassType: `coupe rocks highball martini collins hurricane flute mug wineGlass`; method: `shake stir build blend throw`; difficulty: `easy medium advanced`.
- No third-party Python dependencies.
- Steps marked **USER ACTION** are outward-facing (creating a public repo, changing GitHub settings). Ask the user and wait for an explicit yes before running them.

---

## File Structure

```
/Users/mlj/dev/norse-catalog/
├── .gitignore
├── README.md                    # authoring workflow + incident runbook (row 3)
├── generate.py                  # copied verbatim from norse-mixology/seed-data/generate.py
├── catalog/
│   ├── __init__.py
│   ├── validate.py              # validate(taxonomy, recipes) -> list[str]; CLI
│   └── build.py                 # publish(...) + CLI `python3 -m catalog.build`
├── tests/
│   ├── __init__.py
│   ├── fixtures.py              # minimal_catalog() small valid catalog
│   ├── test_validate.py
│   └── test_build.py
├── site/v1/                     # generated, committed
└── .github/workflows/
    ├── check.yml
    └── publish.yml
```

---

### Task 1: Repo scaffold, generator, and validator

**Files:**
- Create: `/Users/mlj/dev/norse-catalog/.gitignore`, `generate.py`, `catalog/__init__.py`, `catalog/validate.py`, `tests/__init__.py`, `tests/fixtures.py`, `tests/test_validate.py`

**Interfaces:**
- Produces: `catalog.validate.validate(taxonomy: list, recipes: list) -> list[str]` (empty list = valid), `catalog.validate.MAX_FILE_BYTES = 1_000_000`, `tests.fixtures.minimal_catalog() -> tuple[list, list]`.

- [ ] **Step 1: Create the repo and copy the generator**

```bash
mkdir -p /Users/mlj/dev/norse-catalog/catalog /Users/mlj/dev/norse-catalog/tests
cd /Users/mlj/dev/norse-catalog
git init -b main
cp /Users/mlj/dev/norse-mixology/seed-data/generate.py generate.py
touch catalog/__init__.py tests/__init__.py
printf '__pycache__/\n*.pyc\n.DS_Store\nbuild/\n' > .gitignore
```

- [ ] **Step 2: Write the test fixture**

`tests/fixtures.py`:

```python
"""A tiny, valid catalog in the exact JSON shape generate.py emits."""
from __future__ import annotations

import copy

CAT = "11111111-1111-5111-8111-111111111111"
FAM = "22222222-2222-5222-8222-222222222222"
STYLE_A = "33333333-3333-5333-8333-333333333333"
STYLE_B = "44444444-4444-5444-8444-444444444444"
RECIPE = "55555555-5555-5555-8555-555555555555"


def _profile(**overrides):
    p = {d: 0.1 for d in ("sweetness", "bitterness", "smokiness", "citrus", "floral",
                          "spice", "herbal", "fruity", "oaky")}
    p["abv"] = 40.0
    p.update(overrides)
    return p


_TAXONOMY = [{
    "id": CAT, "name": "Spirit",
    "families": [{
        "id": FAM, "name": "Gin", "categoryId": CAT,
        "styles": [
            {"id": STYLE_A, "name": "London Dry Gin", "familyId": FAM, "categoryId": CAT,
             "exampleBrands": ["Tanqueray"], "flavorProfile": _profile(herbal=0.7),
             "abvMin": 37.5, "abvMax": 47.0},
            {"id": STYLE_B, "name": "Old Tom Gin", "familyId": FAM, "categoryId": CAT,
             "exampleBrands": [], "flavorProfile": _profile(sweetness=0.5),
             "abvMin": 40.0, "abvMax": 47.0},
        ],
    }],
}]

_RECIPES = [{
    "id": RECIPE, "name": "Gin Rickey", "description": "Gin and lime.",
    "glassType": "highball", "method": "build",
    "ingredients": [
        {"ingredientStyleId": STYLE_A, "amount": "50ml", "preparation": None,
         "isOptional": False, "substituteNotes": None},
    ],
    "steps": ["Build over ice."],
    "flavorProfile": _profile(),
    "tags": ["classic"], "difficulty": "easy", "imageURL": None,
}]


def minimal_catalog():
    """Returns fresh deep copies so tests can mutate freely."""
    return copy.deepcopy(_TAXONOMY), copy.deepcopy(_RECIPES)
```

- [ ] **Step 3: Write the failing validator tests**

`tests/test_validate.py`:

```python
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from catalog.validate import validate
from tests.fixtures import STYLE_A, minimal_catalog

REPO = Path(__file__).resolve().parent.parent


class ValidateTests(unittest.TestCase):
    def assertInvalid(self, taxonomy, recipes, fragment):
        errors = validate(taxonomy, recipes)
        self.assertTrue(any(fragment in e for e in errors),
                        f"expected an error containing {fragment!r}, got {errors}")

    def test_minimal_catalog_is_valid(self):
        self.assertEqual(validate(*minimal_catalog()), [])

    def test_duplicate_id_is_rejected(self):
        taxonomy, recipes = minimal_catalog()
        recipes[0]["id"] = STYLE_A
        self.assertInvalid(taxonomy, recipes, "duplicate id")

    def test_non_uuid_id_is_rejected(self):
        taxonomy, recipes = minimal_catalog()
        taxonomy[0]["id"] = "not-a-uuid"
        self.assertInvalid(taxonomy, recipes, "invalid id")

    def test_dangling_recipe_style_reference_is_rejected(self):
        taxonomy, recipes = minimal_catalog()
        recipes[0]["ingredients"][0]["ingredientStyleId"] = "99999999-9999-5999-8999-999999999999"
        self.assertInvalid(taxonomy, recipes, "unknown style")

    def test_flavour_out_of_range_is_rejected(self):
        taxonomy, recipes = minimal_catalog()
        taxonomy[0]["families"][0]["styles"][0]["flavorProfile"]["citrus"] = 1.5
        self.assertInvalid(taxonomy, recipes, "flavorProfile.citrus")

    def test_family_category_mismatch_is_rejected(self):
        taxonomy, recipes = minimal_catalog()
        taxonomy[0]["families"][0]["categoryId"] = "99999999-9999-5999-8999-999999999999"
        self.assertInvalid(taxonomy, recipes, "categoryId does not match")

    def test_style_family_mismatch_is_rejected(self):
        taxonomy, recipes = minimal_catalog()
        taxonomy[0]["families"][0]["styles"][0]["familyId"] = "99999999-9999-5999-8999-999999999999"
        self.assertInvalid(taxonomy, recipes, "familyId does not match")

    def test_abv_min_above_max_is_rejected(self):
        taxonomy, recipes = minimal_catalog()
        taxonomy[0]["families"][0]["styles"][0]["abvMin"] = 50.0
        self.assertInvalid(taxonomy, recipes, "abvMin")

    def test_unknown_glass_type_is_rejected(self):
        taxonomy, recipes = minimal_catalog()
        recipes[0]["glassType"] = "bucket"
        self.assertInvalid(taxonomy, recipes, "glassType")

    def test_empty_steps_are_rejected(self):
        taxonomy, recipes = minimal_catalog()
        recipes[0]["steps"] = []
        self.assertInvalid(taxonomy, recipes, "steps")

    def test_empty_ingredients_are_rejected(self):
        taxonomy, recipes = minimal_catalog()
        recipes[0]["ingredients"] = []
        self.assertInvalid(taxonomy, recipes, "ingredients")

    def test_missing_name_is_rejected(self):
        taxonomy, recipes = minimal_catalog()
        recipes[0]["name"] = "  "
        self.assertInvalid(taxonomy, recipes, "name")

    def test_non_object_entries_do_not_crash(self):
        errors = validate(["oops"], [42])
        self.assertTrue(errors)

    def test_real_generated_catalog_is_valid(self):
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run([sys.executable, str(REPO / "generate.py"), tmp],
                           check=True, capture_output=True)
            taxonomy = json.loads((Path(tmp) / "taxonomy.json").read_text(encoding="utf-8"))
            recipes = json.loads((Path(tmp) / "recipes.json").read_text(encoding="utf-8"))
        self.assertEqual(validate(taxonomy, recipes), [])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `cd /Users/mlj/dev/norse-catalog && python3 -m unittest tests.test_validate -v`
Expected: FAIL/ERROR — `ModuleNotFoundError` or `ImportError: cannot import name 'validate'`.

- [ ] **Step 5: Implement the validator**

`catalog/validate.py`:

```python
"""Invariant checks for the generated catalog.

`validate()` returns human-readable error strings; an empty list means the
catalog is publishable. Enum sets mirror the iOS decoders exactly — a value
the app can't decode must never be published.
"""
from __future__ import annotations

import json
import sys
import uuid
from pathlib import Path

DIMS = ("sweetness", "bitterness", "smokiness", "citrus", "floral",
        "spice", "herbal", "fruity", "oaky")
GLASS_TYPES = {"coupe", "rocks", "highball", "martini", "collins", "hurricane",
               "flute", "mug", "wineGlass"}
METHODS = {"shake", "stir", "build", "blend", "throw"}
DIFFICULTIES = {"easy", "medium", "advanced"}
MAX_FILE_BYTES = 1_000_000


def _is_uuid(value) -> bool:
    try:
        return str(uuid.UUID(value)) == value
    except (ValueError, TypeError, AttributeError):
        return False


def _is_number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _is_text(value) -> bool:
    return isinstance(value, str) and value.strip() != ""


def _check_profile(where: str, profile, errors: list) -> None:
    if not isinstance(profile, dict):
        errors.append(f"{where}: flavorProfile missing")
        return
    for dim in DIMS:
        v = profile.get(dim)
        if not _is_number(v) or not 0.0 <= v <= 1.0:
            errors.append(f"{where}: flavorProfile.{dim} must be a number in 0-1, got {v!r}")
    abv = profile.get("abv")
    if not _is_number(abv) or not 0.0 <= abv <= 100.0:
        errors.append(f"{where}: flavorProfile.abv must be a number in 0-100, got {abv!r}")


def validate(taxonomy, recipes) -> list:
    errors: list = []
    seen_ids: set = set()
    style_ids: set = set()

    def claim(where: str, value) -> None:
        if not _is_uuid(value):
            errors.append(f"{where}: invalid id {value!r}")
            return
        if value in seen_ids:
            errors.append(f"{where}: duplicate id {value}")
        seen_ids.add(value)

    if not isinstance(taxonomy, list) or not taxonomy:
        errors.append("taxonomy: must be a non-empty list")
        taxonomy = []
    for category in taxonomy:
        if not isinstance(category, dict):
            errors.append(f"taxonomy: category must be an object, got {category!r}")
            continue
        cw = f"category {category.get('name')!r}"
        claim(cw, category.get("id"))
        if not _is_text(category.get("name")):
            errors.append(f"{cw}: name required")
        families = category.get("families")
        if not isinstance(families, list) or not families:
            errors.append(f"{cw}: families must be a non-empty list")
            continue
        for family in families:
            if not isinstance(family, dict):
                errors.append(f"{cw}: family must be an object")
                continue
            fw = f"family {family.get('name')!r}"
            claim(fw, family.get("id"))
            if not _is_text(family.get("name")):
                errors.append(f"{fw}: name required")
            if family.get("categoryId") != category.get("id"):
                errors.append(f"{fw}: categoryId does not match its parent category")
            styles = family.get("styles")
            if not isinstance(styles, list) or not styles:
                errors.append(f"{fw}: styles must be a non-empty list")
                continue
            for style in styles:
                if not isinstance(style, dict):
                    errors.append(f"{fw}: style must be an object")
                    continue
                sw = f"style {style.get('name')!r}"
                claim(sw, style.get("id"))
                style_ids.add(style.get("id"))
                if not _is_text(style.get("name")):
                    errors.append(f"{sw}: name required")
                if style.get("familyId") != family.get("id"):
                    errors.append(f"{sw}: familyId does not match its parent family")
                if style.get("categoryId") != category.get("id"):
                    errors.append(f"{sw}: categoryId does not match its parent category")
                brands = style.get("exampleBrands")
                if not isinstance(brands, list) or not all(_is_text(b) for b in brands):
                    errors.append(f"{sw}: exampleBrands must be a list of non-empty strings")
                lo, hi = style.get("abvMin"), style.get("abvMax")
                if not _is_number(lo) or not _is_number(hi) or lo > hi:
                    errors.append(f"{sw}: abvMin/abvMax must be numbers with abvMin <= abvMax")
                _check_profile(sw, style.get("flavorProfile"), errors)

    if not isinstance(recipes, list) or not recipes:
        errors.append("recipes: must be a non-empty list")
        recipes = []
    for recipe in recipes:
        if not isinstance(recipe, dict):
            errors.append(f"recipes: recipe must be an object, got {recipe!r}")
            continue
        rw = f"recipe {recipe.get('name')!r}"
        claim(rw, recipe.get("id"))
        for field in ("name", "description"):
            if not _is_text(recipe.get(field)):
                errors.append(f"{rw}: {field} required")
        if recipe.get("glassType") not in GLASS_TYPES:
            errors.append(f"{rw}: glassType {recipe.get('glassType')!r} is not one of {sorted(GLASS_TYPES)}")
        if recipe.get("method") not in METHODS:
            errors.append(f"{rw}: method {recipe.get('method')!r} is not one of {sorted(METHODS)}")
        if recipe.get("difficulty") not in DIFFICULTIES:
            errors.append(f"{rw}: difficulty {recipe.get('difficulty')!r} is not one of {sorted(DIFFICULTIES)}")
        steps = recipe.get("steps")
        if not isinstance(steps, list) or not steps or not all(_is_text(s) for s in steps):
            errors.append(f"{rw}: steps must be a non-empty list of non-empty strings")
        tags = recipe.get("tags")
        if not isinstance(tags, list) or not all(_is_text(t) for t in tags) or len(set(tags)) != len(tags):
            errors.append(f"{rw}: tags must be a list of unique non-empty strings")
        image = recipe.get("imageURL")
        if image is not None and not isinstance(image, str):
            errors.append(f"{rw}: imageURL must be a string or null")
        _check_profile(rw, recipe.get("flavorProfile"), errors)
        ingredients = recipe.get("ingredients")
        if not isinstance(ingredients, list) or not ingredients:
            errors.append(f"{rw}: ingredients must be a non-empty list")
            continue
        for i, ing in enumerate(ingredients):
            iw = f"{rw} ingredient {i}"
            if not isinstance(ing, dict):
                errors.append(f"{iw}: must be an object")
                continue
            if ing.get("ingredientStyleId") not in style_ids:
                errors.append(f"{iw}: unknown style {ing.get('ingredientStyleId')!r}")
            if not _is_text(ing.get("amount")):
                errors.append(f"{iw}: amount required")
            if not isinstance(ing.get("isOptional"), bool):
                errors.append(f"{iw}: isOptional must be a boolean")
            for field in ("preparation", "substituteNotes"):
                if ing.get(field) is not None and not isinstance(ing.get(field), str):
                    errors.append(f"{iw}: {field} must be a string or null")
    return errors


def main(argv: list) -> int:
    folder = Path(argv[1]) if len(argv) > 1 else Path(".")
    taxonomy = json.loads((folder / "taxonomy.json").read_text(encoding="utf-8"))
    recipes = json.loads((folder / "recipes.json").read_text(encoding="utf-8"))
    errors = validate(taxonomy, recipes)
    for e in errors:
        print(e, file=sys.stderr)
    print(f"{len(errors)} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd /Users/mlj/dev/norse-catalog && python3 -m unittest tests.test_validate -v`
Expected: all 14 tests PASS. If `test_real_generated_catalog_is_valid` fails, **stop and report the errors** — it means the existing seed data violates an invariant; do not loosen the validator without asking.

- [ ] **Step 7: Commit**

```bash
cd /Users/mlj/dev/norse-catalog
git add .gitignore generate.py catalog tests
git commit -m "feat: catalog generator and invariant validator"
```

---

### Task 2: Build step — hashed files, manifest, retention

**Files:**
- Create: `/Users/mlj/dev/norse-catalog/catalog/build.py`, `tests/test_build.py`

**Interfaces:**
- Consumes: `catalog.validate.validate`, `catalog.validate.MAX_FILE_BYTES`, `tests.fixtures.minimal_catalog`.
- Produces: `catalog.build.publish(taxonomy_bytes: bytes, recipes_bytes: bytes, site_v1: Path, now: datetime) -> bool` (True = new version written, False = content unchanged, nothing touched); `catalog.build.BuildError(Exception)`; CLI `python3 -m catalog.build` (generates into a temp dir, publishes to `site/v1`).

- [ ] **Step 1: Write the failing build tests**

`tests/test_build.py`:

```python
import hashlib
import json
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from catalog.build import BuildError, publish
from tests.fixtures import minimal_catalog

T0 = datetime(2026, 9, 23, 10, 0, 0, tzinfo=timezone.utc)


def encode(obj) -> bytes:
    return (json.dumps(obj, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def catalog_bytes(recipe_name="Gin Rickey"):
    taxonomy, recipes = minimal_catalog()
    recipes[0]["name"] = recipe_name
    return encode(taxonomy), encode(recipes)


class PublishTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.site = Path(self._tmp.name) / "site" / "v1"

    def tearDown(self):
        self._tmp.cleanup()

    def manifest(self):
        return json.loads((self.site / "manifest.json").read_text(encoding="utf-8"))

    def snapshot(self):
        return {p.name: p.read_bytes() for p in sorted(self.site.iterdir())}

    def test_first_publish_writes_manifest_and_hashed_files(self):
        tax, rec = catalog_bytes()
        self.assertTrue(publish(tax, rec, self.site, T0))
        m = self.manifest()
        tax_sha = hashlib.sha256(tax).hexdigest()
        rec_sha = hashlib.sha256(rec).hexdigest()
        self.assertEqual(m["schemaVersion"], 1)
        self.assertEqual(m["generatedAt"], "2026-09-23T10:00:00Z")
        self.assertEqual(m["contentVersion"], hashlib.sha256((tax_sha + rec_sha).encode()).hexdigest()[:8])
        self.assertEqual(m["taxonomy"], {"path": f"taxonomy.{tax_sha[:8]}.json", "sha256": tax_sha, "bytes": len(tax)})
        self.assertEqual(m["recipes"], {"path": f"recipes.{rec_sha[:8]}.json", "sha256": rec_sha, "bytes": len(rec)})
        self.assertEqual((self.site / m["taxonomy"]["path"]).read_bytes(), tax)
        self.assertEqual((self.site / m["recipes"]["path"]).read_bytes(), rec)

    def test_unchanged_content_is_a_byte_for_byte_no_op(self):
        tax, rec = catalog_bytes()
        publish(tax, rec, self.site, T0)
        before = self.snapshot()
        self.assertFalse(publish(tax, rec, self.site, T0 + timedelta(days=1)))
        self.assertEqual(self.snapshot(), before)

    def test_retention_keeps_the_last_three_versions(self):
        paths_per_version = []
        for i in range(4):
            tax, rec = catalog_bytes(recipe_name=f"Gin Rickey {i}")
            publish(tax, rec, self.site, T0 + timedelta(hours=i))
            m = self.manifest()
            paths_per_version.append({m["taxonomy"]["path"], m["recipes"]["path"]})
        on_disk = {p.name for p in self.site.iterdir()}
        for kept in paths_per_version[1:]:
            self.assertTrue(kept <= on_disk, f"{kept} should still be published")
        oldest_only = paths_per_version[0] - set().union(*paths_per_version[1:])
        self.assertTrue(oldest_only, "fixture should give version 0 a unique recipes file")
        self.assertFalse(oldest_only & on_disk, "version 0's unique files should be pruned")
        history = json.loads((self.site / "history.json").read_text(encoding="utf-8"))
        self.assertEqual(len(history), 3)
        self.assertEqual(history[0], self.manifest())

    def test_reverting_content_publishes_a_new_manifest(self):
        a = catalog_bytes("A")
        b = catalog_bytes("B")
        publish(*a, self.site, T0)
        first_version = self.manifest()["contentVersion"]
        publish(*b, self.site, T0 + timedelta(hours=1))
        self.assertTrue(publish(*a, self.site, T0 + timedelta(hours=2)))
        m = self.manifest()
        self.assertEqual(m["contentVersion"], first_version)
        self.assertEqual(m["generatedAt"], "2026-09-23T12:00:00Z")

    def test_invalid_content_raises_and_leaves_site_untouched(self):
        publish(*catalog_bytes(), self.site, T0)
        before = self.snapshot()
        taxonomy, recipes = minimal_catalog()
        recipes[0]["steps"] = []
        with self.assertRaises(BuildError):
            publish(encode(taxonomy), encode(recipes), self.site, T0 + timedelta(hours=1))
        self.assertEqual(self.snapshot(), before)

    def test_oversized_file_raises(self):
        tax, _ = catalog_bytes()
        with self.assertRaises(BuildError):
            publish(tax, b" " * 1_000_001, self.site, T0)
        self.assertFalse(self.site.exists())

    def test_non_json_raises_build_error(self):
        with self.assertRaises(BuildError):
            publish(b"<html>", b"[]", self.site, T0)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/mlj/dev/norse-catalog && python3 -m unittest tests.test_build -v`
Expected: ERROR — `ModuleNotFoundError: No module named 'catalog.build'`.

- [ ] **Step 3: Implement the build step**

`catalog/build.py`:

```python
"""generate.py → validate → site/v1 (content-hashed files + manifest).

Idempotent: unchanged content leaves site/ byte-for-byte untouched, which is
what lets CI re-run the build and fail on any diff. manifest.json is written
last, so an interrupted build never points at files that don't exist.
"""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from catalog.validate import MAX_FILE_BYTES, validate

SCHEMA_VERSION = 1
KEEP_VERSIONS = 3
REPO = Path(__file__).resolve().parent.parent
HASHED_FILE = re.compile(r"^(taxonomy|recipes)\.[0-9a-f]{8}\.json$")


class BuildError(Exception):
    pass


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _write_json(path: Path, obj) -> None:
    path.write_text(json.dumps(obj, indent=2) + "\n", encoding="utf-8")


def publish(taxonomy_bytes: bytes, recipes_bytes: bytes, site_v1: Path, now: datetime) -> bool:
    for name, data in (("taxonomy", taxonomy_bytes), ("recipes", recipes_bytes)):
        if len(data) > MAX_FILE_BYTES:
            raise BuildError(f"{name}.json is {len(data)} bytes; the limit is {MAX_FILE_BYTES}")
    try:
        taxonomy = json.loads(taxonomy_bytes)
        recipes = json.loads(recipes_bytes)
    except ValueError as exc:
        raise BuildError(f"catalog is not valid JSON: {exc}") from exc
    errors = validate(taxonomy, recipes)
    if errors:
        raise BuildError("validation failed:\n" + "\n".join(errors))

    tax_sha, rec_sha = _sha256(taxonomy_bytes), _sha256(recipes_bytes)
    content_version = _sha256((tax_sha + rec_sha).encode("ascii"))[:8]

    history_path = site_v1 / "history.json"
    history = json.loads(history_path.read_text(encoding="utf-8")) if history_path.exists() else []
    if history and history[0]["contentVersion"] == content_version:
        return False

    manifest = {
        "schemaVersion": SCHEMA_VERSION,
        "contentVersion": content_version,
        "generatedAt": now.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "taxonomy": {"path": f"taxonomy.{tax_sha[:8]}.json", "sha256": tax_sha, "bytes": len(taxonomy_bytes)},
        "recipes": {"path": f"recipes.{rec_sha[:8]}.json", "sha256": rec_sha, "bytes": len(recipes_bytes)},
    }

    site_v1.mkdir(parents=True, exist_ok=True)
    (site_v1 / manifest["taxonomy"]["path"]).write_bytes(taxonomy_bytes)
    (site_v1 / manifest["recipes"]["path"]).write_bytes(recipes_bytes)

    history = [manifest] + history[: KEEP_VERSIONS - 1]
    keep = {m[k]["path"] for m in history for k in ("taxonomy", "recipes")}
    for path in site_v1.iterdir():
        if HASHED_FILE.match(path.name) and path.name not in keep:
            path.unlink()

    _write_json(history_path, history)
    _write_json(site_v1 / "manifest.json", manifest)
    return True


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run([sys.executable, str(REPO / "generate.py"), tmp], check=True)
        taxonomy_bytes = (Path(tmp) / "taxonomy.json").read_bytes()
        recipes_bytes = (Path(tmp) / "recipes.json").read_bytes()
    try:
        changed = publish(taxonomy_bytes, recipes_bytes, REPO / "site" / "v1", datetime.now(timezone.utc))
    except BuildError as exc:
        print(exc, file=sys.stderr)
        return 1
    print("Published a new catalog version." if changed else "Catalog unchanged; site/ untouched.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/mlj/dev/norse-catalog && python3 -m unittest discover -s tests -t . -v`
Expected: all tests in `test_validate` and `test_build` PASS.

- [ ] **Step 5: Build the real site and check it is idempotent**

```bash
cd /Users/mlj/dev/norse-catalog
python3 -m catalog.build            # expect: "Published a new catalog version."
python3 -m catalog.build            # expect: "Catalog unchanged; site/ untouched."
ls site/v1                          # expect: history.json manifest.json recipes.<8hex>.json taxonomy.<8hex>.json
```

Then confirm the published bytes match the app repo's current seed data (so the move changed nothing):

```bash
cd /Users/mlj/dev/norse-catalog
cmp site/v1/taxonomy.*.json /Users/mlj/dev/norse-mixology/seed-data/taxonomy.json && echo taxonomy-identical
cmp site/v1/recipes.*.json /Users/mlj/dev/norse-mixology/seed-data/recipes.json && echo recipes-identical
```

Expected: both `-identical` lines print. If not, stop and report — `generate.py` output has drifted from the committed seed data and the user must decide which is correct.

- [ ] **Step 6: Commit**

```bash
cd /Users/mlj/dev/norse-catalog
git add catalog/build.py tests/test_build.py site
git commit -m "feat: content-hashed site build with manifest and 3-version retention"
```

---

### Task 3: CI workflows and README runbook

**Files:**
- Create: `/Users/mlj/dev/norse-catalog/.github/workflows/check.yml`, `.github/workflows/publish.yml`, `README.md`

**Interfaces:**
- Consumes: `python -m unittest discover -s tests -t .`, `python -m catalog.build`.
- Produces: a status check named `check` (used by branch protection in Task 4); a Pages deployment from `site/`.

- [ ] **Step 1: Write `check.yml`**

```yaml
name: check
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - name: Unit tests
        run: python -m unittest discover -s tests -t . -v
      - name: site/ is up to date with generate.py
        run: |
          python -m catalog.build
          if [ -n "$(git status --porcelain -- site/)" ]; then
            git status --porcelain -- site/
            echo "::error::site/ is stale. Run 'python3 -m catalog.build' locally and commit site/."
            exit 1
          fi
```

- [ ] **Step 2: Write `publish.yml`**

```yaml
name: publish
on:
  push:
    branches: [main]
  workflow_dispatch:
permissions:
  contents: read
  pages: write
  id-token: write
concurrency:
  group: pages
  cancel-in-progress: false
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - name: Unit tests
        run: python -m unittest discover -s tests -t . -v
      - name: Refuse to publish a stale site/
        run: |
          python -m catalog.build
          test -z "$(git status --porcelain -- site/)"
      - uses: actions/configure-pages@v5
      - uses: actions/upload-pages-artifact@v3
        with:
          path: site
      - id: deployment
        uses: actions/deploy-pages@v4
```

- [ ] **Step 3: Write `README.md`**

````markdown
# norse-catalog

Public ingredient taxonomy and recipe catalog for the Norse Mixology apps, published to
`https://martinloesethjensen.github.io/norse-catalog/v1/manifest.json`.

## Changing the catalog

1. Edit `generate.py`.
2. `python3 -m unittest discover -s tests -t . -v`
3. `python3 -m catalog.build` — validates and writes `site/v1/` (hashed files + `manifest.json`).
4. Commit `generate.py` **and** `site/`, open a PR. CI fails if `site/` is stale or invalid.
5. Merge → the `publish` workflow deploys to Pages. Apps pick it up on their next cold launch
   and apply it on the launch after that.

## Incident: bad content was published

Content that passes validation but is wrong (typo, bad recipe):

1. `git revert <bad commit>` on a branch, run `python3 -m catalog.build`, commit `site/`, PR, merge.
2. The build publishes a new manifest (new `generatedAt`) pointing at the reverted content;
   clients replace the bad catalog on their next refresh.

Never delete files from `site/v1/` by hand — the build retains the last 3 versions so a
CDN-cached manifest never points at a missing file.

## Guarantees the apps rely on

- `manifest.json` schema is fixed for `/v1/`; breaking changes go to `/v2/`.
- Hashed files are immutable once published.
- Everything published has passed `catalog/validate.py`.
````

- [ ] **Step 4: Validate the workflow YAML parses**

Run: `cd /Users/mlj/dev/norse-catalog && ruby -ryaml -e 'ARGV.each { |f| YAML.load_file(f); puts "ok #{f}" }' .github/workflows/*.yml`
Expected: `ok .github/workflows/check.yml` and `ok .github/workflows/publish.yml`.

- [ ] **Step 5: Commit**

```bash
cd /Users/mlj/dev/norse-catalog
git add .github README.md
git commit -m "ci: check and publish workflows; README with authoring and incident runbook"
```

---

### Task 4: Publish to GitHub and verify the live contract

**Files:** none (GitHub configuration + verification).

**Interfaces:**
- Produces: live `https://martinloesethjensen.github.io/norse-catalog/v1/manifest.json` — Plan 2's sync script and updater consume it.

- [ ] **Step 1: USER ACTION — create the public repo and push**

Ask the user: "Create public GitHub repo `martinloesethjensen/norse-catalog` and push `main`?" On an explicit yes:

```bash
cd /Users/mlj/dev/norse-catalog
gh repo create martinloesethjensen/norse-catalog --public --source . --push \
  --description "Norse Mixology ingredient taxonomy and recipe catalog"
```

- [ ] **Step 2: USER ACTION — enable Pages from GitHub Actions**

Ask first. On yes:

```bash
gh api -X POST repos/martinloesethjensen/norse-catalog/pages -f build_type=workflow
gh workflow run publish.yml -R martinloesethjensen/norse-catalog
gh run watch -R martinloesethjensen/norse-catalog "$(gh run list -R martinloesethjensen/norse-catalog -w publish -L 1 --json databaseId -q '.[0].databaseId')"
```

Expected: the run finishes successfully.

- [ ] **Step 3: USER ACTION — protect `main`**

Ask first. On yes:

```bash
gh api -X PUT repos/martinloesethjensen/norse-catalog/branches/main/protection \
  --input - <<'EOF'
{
  "required_status_checks": { "strict": true, "contexts": ["check"] },
  "enforce_admins": false,
  "required_pull_request_reviews": { "required_approving_review_count": 0 },
  "restrictions": null
}
EOF
```

Also remind the user to confirm 2FA is enabled on the account (spec §2, repo security); do not check or change account settings yourself.

- [ ] **Step 4: Verify the live contract (hashes, ETag, 304)**

```bash
BASE=https://martinloesethjensen.github.io/norse-catalog/v1
curl -sSf "$BASE/manifest.json" -o /tmp/manifest.json && cat /tmp/manifest.json
python3 - <<'EOF'
import hashlib, json, urllib.request
base = "https://martinloesethjensen.github.io/norse-catalog/v1/"
m = json.load(open("/tmp/manifest.json"))
for key in ("taxonomy", "recipes"):
    data = urllib.request.urlopen(base + m[key]["path"]).read()
    assert hashlib.sha256(data).hexdigest() == m[key]["sha256"], key
    assert len(data) == m[key]["bytes"], key
    print(key, "hash ok")
EOF
ETAG=$(curl -sSI "$BASE/manifest.json" | awk 'tolower($1)=="etag:" {print $2}' | tr -d '\r')
echo "ETag: $ETAG"
curl -s -o /dev/null -w '%{http_code}\n' -H "If-None-Match: $ETAG" "$BASE/manifest.json"
```

Expected: both `hash ok` lines, a non-empty ETag, and `304` from the last command. Record the result in the task report — Plan 2 depends on this URL.
