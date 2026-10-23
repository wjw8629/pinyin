import sys

sys.dont_write_bytecode = True

import re
import unicodedata
from pathlib import Path
import tkinter as tk


def is_hanzi(char):
	name = unicodedata.name(char, "")
	return name.startswith(("CJK UNIFIED IDEOGRAPH-", "CJK COMPATIBILITY IDEOGRAPH-"))


def compare_files():
	folder = Path(__file__).resolve().parent
	current_path = folder / "current.txt"
	learned_path = folder / "learned.txt"

	current_text = current_path.read_text(encoding="utf-8")
	learned_text = learned_path.read_text(encoding="utf-8")

	learned_lines = learned_text.splitlines()
	if learned_lines and re.fullmatch(r"已学\d+字", learned_lines[0].strip()):
		learned_text = "".join(learned_lines[1:])

	learned_chars = {char for char in learned_text if is_hanzi(char)}
	missing_chars = list(dict.fromkeys(
		char for char in current_text
		if is_hanzi(char) and char not in learned_chars
	))
	return missing_chars


def show_notification(missing_chars):
	count = len(missing_chars)
	if count:
		full_message = f"有 {count} 个汉字还没学：{' '.join(missing_chars)}"
		preview = " ".join(missing_chars[:24])
		if count > 24:
			preview += " ..."
		message = f"有 {count} 个汉字还没学\n{preview}"
	else:
		message = "未学汉字：0 个\ncurrent.txt 里的汉字都已学会。"
		full_message = message

	print(full_message)

	try:
		root = tk.Tk()
		root.overrideredirect(True)
		root.attributes("-topmost", True)
		root.configure(bg="#fff7d6", highlightthickness=1, highlightbackground="#d6c98a")

		label = tk.Label(
			root,
			text=message,
			bg="#fff7d6",
			fg="#252525",
			font=("Microsoft YaHei UI", 10),
			justify="left",
			padx=16,
			pady=12,
			wraplength=320,
		)
		label.pack()

		root.update_idletasks()
		width = min(max(300, root.winfo_reqwidth()), 380)
		height = root.winfo_reqheight()
		x = (root.winfo_screenwidth() - width) // 2
		y = (root.winfo_screenheight() - height) // 2
		root.geometry(f"{width}x{height}+{x}+{y}")

		def close_when_not_hovered():
			pointer_x = root.winfo_pointerx()
			pointer_y = root.winfo_pointery()
			left = root.winfo_rootx()
			top = root.winfo_rooty()
			inside = (
				left <= pointer_x < left + root.winfo_width()
				and top <= pointer_y < top + root.winfo_height()
			)
			if inside:
				root.after(100, close_when_not_hovered)
			else:
				root.destroy()

		root.after(2000, close_when_not_hovered)
		root.mainloop()
	except tk.TclError:
		pass


if __name__ == "__main__":
	show_notification(compare_files())
