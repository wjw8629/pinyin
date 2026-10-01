import os
import sys
import traceback

def main():
    # 🛠️ Safety check: Locate the exact root folder relative to PyInstaller structure
    if getattr(sys, 'frozen', False):
        exe_dir = os.path.dirname(sys.executable)
        current_dir = os.path.dirname(exe_dir)
    else:
        current_dir = os.path.dirname(os.path.abspath(__file__))
        
    input_file = os.path.join(current_dir, "input_temp.txt")
    output_file = os.path.join(current_dir, "output_temp.txt")
    crash_log = os.path.join(current_dir, "crash_log.txt")
    
    # Force clean previous log state instances
    if os.path.exists(crash_log):
        try: os.remove(crash_log)
        except: pass

    try:
        # Defer intensive imports inside the handler loop to track asset linkage crashes
        from pypinyin import pinyin, Style
        
        if not os.path.exists(input_file):
            with open(crash_log, "w", encoding="utf-8") as f:
                f.write(f"Error: input_temp.txt was not found at expected path:\n{input_file}")
            return

        with open(input_file, "r", encoding="utf-8-sig") as f:
            text = f.read()

        if not text.strip():
            with open(crash_log, "w", encoding="utf-8") as f:
                f.write("Error: input_temp.txt was found but it is completely empty.")
            return

        results = []
        for char in text:
            if '\u4e00' <= char <= '\u9fa5':
                # =================== 关键修改点 ===================
                # 将 Style.NORMAL 修改为 Style.TONE 以重新显示声调
                py_list = pinyin(char, style=Style.TONE)
                # =================================================
                py = py_list[0][0] if (py_list and py_list[0]) else ""
            else:
                py = ""
            results.append(f"{char}\t{py}")

        with open(output_file, "w", encoding="utf-8") as f:
            f.write("\n".join(results))
            
    except Exception as e:
        # 🚨 Catch any crash, map the traceback, and output to a plain text log file
        with open(crash_log, "w", encoding="utf-8") as f:
            f.write("=== CRITICAL TRANSLATION ENGINE CRASH ===\n")
            f.write(f"Exception Type: {type(e).__name__}\n")
            f.write(f"Exception Message: {str(e)}\n\n")
            f.write("--- Stack Traceback ---\n")
            f.write(traceback.format_exc())

if __name__ == "__main__":
    main()
