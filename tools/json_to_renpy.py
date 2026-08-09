#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
VN Studio → Ren'Py 工程转换器
把 VN Studio 导出的 project.json 生成可运行的 Ren'Py 工程（game/ 目录）。

用法:
    python3 json_to_renpy.py <project.json> [-o <输出目录>]

输出:
    <out>/game/
        script.rpy     剧情（label/menu/play music/scene）
        options.rpy    基本配置
        images/        背景与 CG（文件名已 slug 化）
        audio/         BGM（文件名已 slug 化）

说明:
    - 素材文件名含中文/空格时统一 slug 化，并在 script 中同步引用
    - 缺失素材自动跳过（Ren'Py 会提示缺失，agent 可后续补齐）
    - 这是"最小可玩"基准工程，agent 可在此基础上加标题画面/画廊/存档等
"""
import argparse, json, os, re, shutil, sys


def slug(name: str) -> str:
    # 保留中文/字母/数字/下划线，其余(空格等)变下划线，避免素材名被吞掉
    base, ext = os.path.splitext(name or "")
    base = re.sub(r"[^A-Za-z0-9_\u4e00-\u9fff]+", "_", base).strip("_") or "asset"
    base = re.sub(r"_+", "_", base)
    ext = (ext or "").lower()
    if ext not in (".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp",
                   ".mp3", ".wav", ".ogg", ".m4a", ".flac", ".aac", ".opus"):
        ext = ""
    return base + ext


def safe_ident(s: str) -> str:
    s = re.sub(r"[^A-Za-z0-9_]+", "_", s).strip("_")
    s = re.sub(r"_+", "_", s)
    if not s or s[0].isdigit():
        s = "c_" + s
    return s


def build(proj: dict, out_dir: str):
    script = proj["script"]
    scenes = script.get("scenes", [])
    characters = proj.get("characters", [])
    img_dir = os.path.join(out_dir, "images")
    aud_dir = os.path.join(out_dir, "audio")
    os.makedirs(img_dir, exist_ok=True)
    os.makedirs(aud_dir, exist_ok=True)

    asset_src = os.path.join(os.path.dirname(proj_path), "assets")
    copied = {}

    def copy_asset(name: str) -> str:
        """复制素材并返回新文件名（无源文件则原样返回以便提示）"""
        if not name:
            return ""
        if name in copied:
            return copied[name]
        new = slug(name)
        src = os.path.join(asset_src, name)
        if os.path.isfile(src):
            ext = os.path.splitext(new)[1].lower()
            dst_dir = aud_dir if ext in (".mp3", ".wav", ".ogg", ".m4a",
                                         ".flac", ".aac", ".opus") else img_dir
            shutil.copy2(src, os.path.join(dst_dir, new))
        copied[name] = new
        return new

    # ---- 素材 ----
    for s in scenes:
        if s.get("bg"):
            copy_asset(s["bg"])
        if s.get("bgm"):
            copy_asset(s["bgm"])
        for ln in s.get("dialogue", []):
            if ln.get("cg"):
                copy_asset(ln["cg"])

    # ---- 角色 ----
    char_lines = ['define narrator = Character(None, what_color="#e8e8ff")']
    char_ids = {}
    for c in characters:
        cid = safe_ident("ch_" + (c.get("id") or ""))
        char_ids[c.get("name", "")] = cid
        color = c.get("color") or "#ff7ab8"
        char_lines.append(
            f'define {cid} = Character("{c.get("name","")}", color="{color}")')
    for s in scenes:
        for ln in s.get("dialogue", []):
            sp = (ln.get("speaker") or "").strip()
            if sp and sp not in char_ids:
                cid = safe_ident("ch_" + sp)
                char_ids[sp] = cid
                char_lines.append(f'define {cid} = Character("{sp}")')

    # ---- 场景脚本 ----
    lines = []
    lines.append('label start:')
    start = script.get("start_scene") or (scenes[0]["id"] if scenes else "")
    lines.append(f'    jump sc_{safe_ident(start)}')
    lines.append('')
    lines.append('image black = Solid("#000000")')
    lines.append('')
    for s in scenes:
        sid = safe_ident(s.get("id", ""))
        lines.append(f'label sc_{sid}:')
        bg = copy_asset(s.get("bg") or "")
        if bg:
            img = safe_ident("bg_" + os.path.splitext(bg)[0])
            lines.append(f'    image {img} = "images/{bg}"')
            lines.append(f'    scene {img}')
        else:
            lines.append('    scene black')
        bgm = copy_asset(s.get("bgm") or "")
        if bgm:
            vol = float(s.get("bgm_volume") or 0.8)
            lines.append(f'    play music "audio/{bgm}" volume {vol:.2f}')
        lines.append('    with dissolve')
        lines.append('')
        for i, ln in enumerate(s.get("dialogue", [])):
            cg = copy_asset(ln.get("cg") or "")
            if cg:
                img = safe_ident("cg_" + os.path.splitext(cg)[0])
                lines.append(f'    image {img} = "images/{cg}"')
                lines.append(f'    show {img} with dissolve')
            sp = (ln.get("speaker") or "").strip()
            text = (ln.get("text") or "").replace('"', '\\"')
            who = char_ids.get(sp, "narrator") if sp else "narrator"
            if text:
                lines.append(f'    {who} "{text}"')
            if cg:
                lines.append(f'    hide {img} with dissolve')
            lines.append('')
        choices = s.get("choices") or []
        if choices:
            lines.append('    menu:')
            for ch in choices:
                t = (ch.get("text") or "").replace('"', '\\"')
                raw_next = ch.get("next") or ""
                lines.append(f'        "{t}":')
                if raw_next:
                    lines.append(f'            jump sc_{safe_ident(raw_next)}')
                else:
                    lines.append('            jump ending')
            lines.append('')
        raw_next = s.get("next") or ""
        if not choices and raw_next:
            lines.append(f'    jump sc_{safe_ident(raw_next)}')
            lines.append('')
        if not choices and not raw_next:
            lines.append('    jump ending')
            lines.append('')
    lines.append('label ending:')
    lines.append('    "— 完 —"')
    lines.append('    return')

    # ---- 写文件 ----
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "script.rpy"), "w", encoding="utf-8") as f:
        f.write("\n".join(char_lines) + "\n\n" + "\n".join(lines))
    with open(os.path.join(out_dir, "options.rpy"), "w", encoding="utf-8") as f:
        f.write(f'''define config.name = "{script.get('title') or proj.get('title') or 'VN Studio Game'}"
define config.version = "1.0"
define config.save_directory = "vnstudio-{safe_ident(proj.get('id') or 'game')}"
define config.window_title = "{script.get('title') or 'VN Studio Game'}"
define config.developer = False
''')
    print(f"OK: Ren'Py 工程已生成 -> {out_dir}")
    print(f"    场景 {len(scenes)} 个 | 角色 {len(char_ids)} 个 | 素材 {len(copied)} 个")
    print("    下一步：用 Ren'Py SDK 打开该工程运行/打包，或交给 agent 继续润色")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("project_json")
    ap.add_argument("-o", "--out", default=".")
    args = ap.parse_args()
    proj_path = args.project_json
    proj = json.load(open(proj_path, encoding="utf-8"))
    build(proj, os.path.join(args.out, "game"))
