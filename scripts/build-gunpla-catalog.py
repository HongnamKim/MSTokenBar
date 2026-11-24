#!/usr/bin/env python3
"""Build the local gallery index and optionally export a portable, offline HTML file."""
import argparse
import base64
import csv
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs/gunpla"
ART = ROOT / "assets/sprites"
BUNDLE = ROOT / "Sources/PokeTokenBar/Resources/Gunpla"
GRADES = ("sd", "mgsd", "hg", "rg", "mg", "verka", "mgex", "pg")
WORKSHOP = {
    "airbrush": "에어브러시", "box-question": "미개봉 상자", "custom-mark": "전용기 마크",
    "custom-medal": "전용기 메달", "hangar-trophy": "격납고 트로피", "hourglass": "모래시계",
    "masking-tape": "마스킹 테이프", "paint-set": "도료 세트", "panel-line-pen": "먹선 펜",
    "sanding-sponge": "사포 스펀지", "series-medal": "작품 메달", "update": "업데이트", "warning": "주의",
}


def grade_name(grade):
    return "Ver.Ka" if grade == "verka" else grade.upper()


def picture(path, embed):
    data = path.read_bytes()
    if embed:
        return "data:image/png;base64," + base64.b64encode(data).decode("ascii")
    return os.path.relpath(path, DOCS)


def catalog(embed):
    references = {}
    for path in sorted(ART.glob("*/references.csv")):
        with path.open(encoding="utf-8-sig", newline="") as stream:
            for row in csv.DictReader(stream):
                file = path.parent / row["파일"]
                key = file.stem.replace("-mg-ver-ka", "-verka")
                if key in references:
                    raise ValueError(f"Multiple sources for {key}")
                references[key] = (file, row["키트"], row.get("조립 사진", ""), row.get("장착 확인 사진", ""))

    cards = []
    series = sorted(json.loads((BUNDLE / "series.json").read_text())["series"], key=lambda s: s["order"])
    machines = json.loads((BUNDLE / "machines.json").read_text())["machines"]
    for work in series:
        for machine in (m for m in machines if m["series"] == work["id"]):
            for grade in machine["grades"]:
                key = machine.get("sprites", {}).get(grade)
                if not key:
                    continue
                path, kit, front, rear = references.pop(key)
                if not (BUNDLE / "Sprites" / (key + ".gif")).is_file():
                    raise FileNotFoundError(key)
                cards.append(dict(group=work["names"]["ko"], kind="기체", grade=grade_name(grade),
                                  title=machine["names"]["ko"], model=machine["modelNumber"], machine=machine["id"],
                                  aliases=list(machine["names"].values()) + list(work["names"].values()),
                                  kit=kit, official=machine["gradeSources"][grade], front=front, rear=rear,
                                  file=path.name, image=picture(path, embed)))
    if references:
        raise ValueError(f"Unregistered artwork: {', '.join(references)}")
    for group, folder in [("등급 배지", "GradeBadges"), ("작업실", "Workshop")]:
        files = sorted((BUNDLE / folder).glob("*.png"))
        if folder == "GradeBadges":
            files.sort(key=lambda f: GRADES.index(f.stem))
        for path in files:
            grade = grade_name(path.stem) if folder == "GradeBadges" else ""
            cards.append(dict(group=group, kind="공용 도트", grade=grade, title=grade or WORKSHOP[path.stem],
                              file=path.name, image=picture(path, embed)))
    icon = ROOT / "assets/icon.png"
    cards.append(dict(group="앱 아이콘", kind="공용 도트", title="MSTokenBar 앱 아이콘", grade="",
                      file=icon.name, image=picture(icon, embed)))
    for path in [*sorted((ART / "rx-78-2").glob("*.png")), DOCS / "images/gunpla-hangar.png"]:
        suffix = path.stem.removeprefix("rx-78-2-")
        grade = grade_name(suffix) if suffix in GRADES else ""
        title = "격납고 콘셉트" if path.stem == "gunpla-hangar" else ("RX-78-2 등급 비교" if not grade else "RX-78-2 초기 시안")
        cards.append(dict(group="초기 시안", kind="시안", title=title, grade=grade,
                          file=path.name, image=picture(path, embed)))
    return cards


def data_script(embed):
    payload = json.dumps(catalog(embed), ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c")
    return "const catalogItems = " + payload + ";\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--standalone", type=Path, help="also export a self-contained HTML file here")
    args = parser.parse_args()
    (DOCS / "catalog-data.js").write_text(data_script(False), encoding="utf-8")
    if args.standalone:
        template = (DOCS / "catalog.html").read_text(encoding="utf-8")
        portable = template.replace('<script src="catalog-data.js"></script>', "<script>" + data_script(True) + "</script>")
        args.standalone.write_text(portable, encoding="utf-8")


if __name__ == "__main__":
    main()
