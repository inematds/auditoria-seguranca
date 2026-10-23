#!/usr/bin/env python3
"""Versão do projeto num lugar só: o arquivo VERSION ("1.1.1 23/10/2026").

    python3 ferramentas/versao.py                 # mostra a versão e confere se tudo está igual
    python3 ferramentas/versao.py 1.1.2           # nova versão, data de hoje
    python3 ferramentas/versao.py 1.1.2 24/10/2026

Atualiza: VERSION, VERSAO= do audita.sh, capa e rodapé do guia PT/EN/ES (<span data-v="versao|data">)
e a linha de versão no topo dos README PT/EN/ES. O CHANGELOG.md continua à mão.
Regra (CLAUDE.md global): patch sobe o último número; minor sobe o do meio e mantém o último.
"""
import datetime
import pathlib
import re
import sys

R = pathlib.Path(__file__).resolve().parent.parent
GUIAS = {"guia/index.html": "pt", "guia/en/index.html": "en", "guia/es/index.html": "es"}
READMES = {"README.md": "pt", "README.en.md": "en", "README.es.md": "es"}


def data_lang(d, lang):  # d = dd/mm/aaaa
    dd, mm, aa = d.split("/")
    return f"{mm}/{dd}/{aa}" if lang == "en" else d


def aplicar(v, d, so_conferir=False):
    difs = []

    def troca(p, novo):
        f = R / p
        velho = f.read_text()
        if velho != novo:
            difs.append(p)
            if not so_conferir:
                f.write_text(novo)

    troca("VERSION", f"{v} {d}\n")
    a = (R / "audita.sh").read_text()
    a = re.sub(r"^VERSAO=.*$", f"VERSAO={v}", a, count=1, flags=re.M)
    a = re.sub(r"^# audita\.sh \S+ —", f"# audita.sh {v} —", a, count=1, flags=re.M)
    troca("audita.sh", a)
    for p, lang in GUIAS.items():
        s = (R / p).read_text()
        s = re.sub(r'(<span data-v="versao">)[^<]*(</span>)', rf"\g<1>{v}\g<2>", s)
        s = re.sub(r'(<span data-v="data">)[^<]*(</span>)', rf"\g<1>{data_lang(d, lang)}\g<2>", s)
        troca(p, s)
    for p, lang in READMES.items():
        s = (R / p).read_text()
        s = re.sub(r"^(\*\*\S+ )v[0-9.]+( · .*? )[0-9/]+(\*\* <!-- versao)", rf"\g<1>v{v}\g<2>{data_lang(d, lang)}\g<3>", s,
                   count=1, flags=re.M)
        troca(p, s)
    return difs


if __name__ == "__main__":
    atual = (R / "VERSION").read_text().split()
    if len(sys.argv) == 1:
        difs = aplicar(atual[0], atual[1], so_conferir=True)
        print(f"versão {atual[0]} de {atual[1]}" + (f" — DIVERGE em: {', '.join(difs)}" if difs else " — tudo igual"))
        sys.exit(1 if difs else 0)
    v = sys.argv[1]
    if not re.fullmatch(r"\d+\.\d+\.\d+", v):
        sys.exit("versão no formato X.Y.Z")
    d = sys.argv[2] if len(sys.argv) > 2 else datetime.date.today().strftime("%d/%m/%Y")
    print("atualizados:", ", ".join(aplicar(v, d)) or "nada")
