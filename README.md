\# ⌨️ 姐儿妹儿拼音练习器 (Pinyin Typing Practice)

\# ======= 中文不易，多加努力 ：）=======





\#1， 编译命令



&#x20; pyinstaller --onedir --noconsole pinyin\_core.py





\#2，修改以下，ahk里面搜索“替换”，同时可以搜索到github文件的路径位置



&#x20;   ;RunWait(A\_ComSpec ' /c python "' pyScript '"', A\_ScriptDir, "Hide")

&#x20;   RunWait('"' pyScript '"', A\_ScriptDir, "Hide")



&#x20;   inputTemp := A\_ScriptDir "\\dist\\input\_temp.txt"

&#x20;   outputTemp := A\_ScriptDir "\\dist\\output\_temp.txt"

&#x20;   pyScript := A\_ScriptDir "\\dist\\pinyin\_core\\pinyin\_core.exe"

&#x20;   ;inputTemp := A\_ScriptDir "\\input\_temp.txt"

&#x20;   ;outputTemp := A\_ScriptDir "\\output\_temp.txt"

&#x20;   ;pyScript := A\_ScriptDir "\\pinyin\_core.py"







