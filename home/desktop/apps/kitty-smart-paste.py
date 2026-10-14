"""Ctrl+V in kitty: paste the clipboard as text, or hand the key to the program.

Wispr Flow's Linux helper puts its transcript on the clipboard and presses
Ctrl+V. Kitty pastes on Ctrl+Shift+V, so a bare Ctrl+V reached the program as
the key itself, and Codex and Claude Code read that as "paste an image" and
found none. Now Ctrl+V pastes text, except in two cases where the program
gets the key as before: the clipboard holds an image (Codex and Claude Code
paste it themselves), or an editor is in the foreground (vim's visual block).
"""
import json
import os
import subprocess

from kittens.tui.handler import result_handler

EDITORS = {'vi', 'vim', 'nvim', 'view', 'vimdiff', 'emacs', 'nano', 'hx', 'kak', 'micro'}


def main(args):
    pass


def clipboard_types():
    try:
        out = subprocess.run(['wl-paste', '--list-types'], capture_output=True, text=True, timeout=1)
    except Exception:
        return []
    return out.stdout.split()


def program(cmdline):
    name = os.path.basename(cmdline[0]) if cmdline else ''
    if name.startswith('.') and name.endswith('-wrapped'):
        name = name[1:-len('-wrapped')]
    return name


def foreground(boss, w):
    try:
        tree = json.loads(boss.call_remote_control(w, ('ls', f'--match=id:{w.id}')))
        procs = [p for os_win in tree for tab in os_win['tabs'] for win in tab['windows']
                 for p in win.get('foreground_processes', [])]
    except Exception:
        return set()
    return {program(p.get('cmdline')) for p in procs}


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    w = boss.window_id_map.get(target_window_id)
    if w is None:
        return
    types = clipboard_types()
    image = any(t.startswith('image/') for t in types)
    if types and not image and not foreground(boss, w) & EDITORS:
        text = subprocess.run(['wl-paste', '--no-newline'], capture_output=True, text=True, timeout=1).stdout
        w.paste_text(text)
        return
    boss.call_remote_control(w, ('send-key', f'--match=id:{w.id}', 'ctrl+v'))
