\# ⌨️ 姐儿妹儿拼音练习器 (Pinyin Typing Practice)

\# ======= 中文不易，多加努力 ：）=======

<br>



\#1， 编译命令



&#x20; pyinstaller --onedir --noconsole --clean pinyin_core.py



<br>



\#2，修改以下，ahk里面搜索“替换”


&#x20;   ;RunWait(A\_ComSpec ' /c python "' pyScript '"', A\_ScriptDir, "Hide")

&#x20;   RunWait('"' PyExe '"', A_ScriptDir, "Hide")



&#x20;   ;global InputTemp := A_ScriptDir "\input_temp.txt"

&#x20;   global InputTemp := A_ScriptDir "\dist\input_temp.txt"

&#x20;   ;global OutputTemp := A_ScriptDir "\output_temp.txt"

&#x20;   global OutputTemp := A_ScriptDir "\dist\output_temp.txt"



