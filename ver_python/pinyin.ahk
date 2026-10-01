#Requires AutoHotkey v2.0
#SingleInstance Force

; --- Global State Variables ---
global G_RawChars := []       
global G_RawPinyins := []     
global G_UserTyped := []      
global PracticeGui := ""      
global WB := ""               
global SaveFile := A_ScriptDir "\progress_save.ini" 
global DictFile := A_ScriptDir "\custom_pinyin.txt"  ; Custom pinyin dictionary path
global G_PinyinOnlyMode := false            

; --- 【UI Optimization】Redistributed heights to grant Web Layout more room ---
global ScaleFactor := A_ScreenDPI / 96  
global GuiW := Integer(Min(A_ScreenWidth * 0.55, 1100))
global GuiH := Integer(GuiW * 0.65)                   

global WebW := Integer(GuiW - 30)
global WebH := Integer(GuiH * 0.72)                 ; Increased from 0.60 to fit large font rows safely
global EditH := Integer(GuiH * 0.07)                ; Compressed slightly to prioritize reading area
global BtnW := Integer(GuiW * 0.20)
global BtnH := Integer(GuiH * 0.05)
global FontSize := Integer(Max(10, GuiH * 0.016))   ; Reduced interface font scale down from 0.022

; =========================================================================
; 🚀 Launch Program: Check save file and initialize adaptive interface
; =========================================================================
InitMainProgram()

InitMainProgram() {
    savedText := ""
    savedBuffer := ""
    
    ; 🚀 Auto-Generate Dictionary File if Missing
    if !FileExist(DictFile) {
        defaultContent := "不易=bu2,yi4"
        FileAppend(defaultContent, DictFile, "UTF-8")
    }
    
    if FileExist(SaveFile) {
        try {
            savedText := IniRead(SaveFile, "SaveState", "InputText", "")
            savedBuffer := IniRead(SaveFile, "SaveState", "TypedBuffer", "")
        } catch {
            ; Fail silently if save state is corrupted
        }
    }
    
    if (savedText == "") {
        savedText := "中文不易，多加努力。"
        savedBuffer := ""
    }
    
    CreatePracticeWindow()
    ProcessAndStart(savedText, savedBuffer, false) 
}

; =========================================================================
; Core Processing and Python Communication Chain
; =========================================================================
ProcessAndStart(inputText, savedBuffer := "", showNotify := true) {
    inputText := RegExReplace(inputText, "[\r\n]+", "") 
    inputText := RegExReplace(inputText, "[^\x{4e00}-\x{9fa5}a-zA-Z0-9，。！？ ]")     
    
    if (Trim(inputText) == "") {
        MsgBox("请输入一些文字后再开始练习哦！", "提示")
        return
    }

    inputTemp := A_ScriptDir "\input_temp.txt"
    outputTemp := A_ScriptDir "\output_temp.txt"
    pyScript := A_ScriptDir "\pinyin_core.py"
    ;inputTemp := A_ScriptDir "\dist\input_temp.txt"
    ;outputTemp := A_ScriptDir "\dist\output_temp.txt"
    ;pyScript := A_ScriptDir "\dist\pinyin_core\pinyin_core.exe"

    if (!FileExist(pyScript)) {
        MsgBox("未在当前目录下找到 [pinyin_core.py] 脚本！`n请确保它与 AHK 脚本放在同一文件夹。", "错误")
        return
    }
    
    if FileExist(inputTemp)
        FileDelete(inputTemp)
    if FileExist(outputTemp)
        FileDelete(outputTemp)
        
    FileAppend(inputText, inputTemp, "UTF-8")
    RunWait(A_ComSpec ' /c python "' pyScript '"', A_ScriptDir, "Hide")
    ;RunWait('"' pyScript '"', A_ScriptDir, "Hide")
    
    if (!FileExist(outputTemp)) {
        MsgBox("Python 转译引擎未响应，请确保环境正常并安装了 pypinyin 库。", "转译失败")
        return
    }
    
    rawResult := FileRead(outputTemp, "UTF-8")
    
    global G_RawChars := []
    global G_RawPinyins := []
    global G_UserTyped := [] 
    
    Pos := 1
    ; 💖 彻底修复：提取捕获组 [1] 和 [2]，确保拼音数组里存的是干净的拼音
    while RegExMatch(rawResult, "m)^([^\t\r\n]+)\t([^\t\r\n]*)", &Match, Pos) {
        Pos := Match.Pos + Match.Len
        rawCh := Trim(Match[1], "`r`n") 
        rawPy := Trim(Match[2], "`r`n")
        
        if (rawPy == "") {
            rawPy := rawCh 
        }
        G_RawChars.Push(rawCh)
        G_RawPinyins.Push(rawPy)
    }
    
    if (G_RawChars.Length == 0) {
        MsgBox("未能识别出有效字符，请更换文本再试。", "提示")
        return
    }
    
    ; 🚀 注入你的 1-to-1 词典替换逻辑
    ApplyCustomPinyinDict()
    
    if (savedBuffer != "") {
        Loop Parse, savedBuffer {
            if (A_Index <= G_RawChars.Length)
                G_UserTyped.Push(A_LoopField)
        }
    }
    
    global G_CurrentOriginalText := inputText
    
    if (PracticeGui != "") {
        PracticeGui["TypedInput"].Value := ""
        PracticeGui["TypedInput"].Focus() 
    }

    RefreshWebGrid()
    
    if (showNotify) {
        ToolTip("✨ 文章转译更换成功！快来练习吧。")
        SetTimer(() => ToolTip(), -2000) 
    }
}

; 🚀 1-to-1 纯净逻辑：严格要求“汉字字数 = 拼音个数”
ApplyCustomPinyinDict() {
    global G_RawChars, G_RawPinyins, DictFile
    if !FileExist(DictFile)
        return
        
    fullText := ""
    for char in G_RawChars {
        fullText .= char
    }
    
    dictContent := FileRead(DictFile, "UTF-8")
    
    Loop Parse, dictContent, "`n", "`r" {
        line := Trim(A_LoopField)
        if (line == "" || InStr(line, "=") == 0)
            continue
            
        parts := StrSplit(line, "=")
        searchWord := Trim(parts[1])  ; 词组，例如：银行
        pinyinStr := Trim(parts[2])   ; 拼音，例如：yin2,hang2
        pinyinList := StrSplit(pinyinStr, ",")
        
        wordLen := StrLen(searchWord)
        
        ; 严格校验：汉字数和拼音数必须相等
        if (wordLen == 0 || pinyinList.Length != wordLen)
            continue 
            
        ; 依次转换为标准声调
        Loop pinyinList.Length {
            pinyinList[A_Index] := ConvertNumToTone(pinyinList[A_Index])
        }
            
        startPos := 1
        while (offset := InStr(fullText, searchWord, false, startPos)) {
            ; 找到词组后，严格执行 1对1 强行覆盖
            Loop wordLen {
                targetIdx := offset + A_Index - 1
                if (targetIdx <= G_RawPinyins.Length) {
                    G_RawPinyins[targetIdx] := pinyinList[A_Index]
                }
            }
            startPos := offset + wordLen 
        }
    }
}


; 🚀 彻底修复版：将数字声调转换为声调字符
ConvertNumToTone(py) {
    py := StrLower(Trim(py))
    if (py == "")
        return ""
        
    ; 处理特殊的 v 替换为 ü
    py := StrReplace(py, "v", "ü")
    
    ; 提取末尾的数字声调 (1-4)
    tone := 0
    if RegExMatch(py, "([1-4])$", &match) {
        tone := Integer(match[1])   ; 获取第一个捕获组文本转换为整数
        py := SubStr(py, 1, -1)     ; 只有匹配到声调数字时，才移除末尾的1位数字
    }
    
    ; 如果没有声调或者声调不在1-4之间，直接返回
    if (tone < 1 || tone > 4)
        return py
        
    ; 声调标注优先级规则：a > o > e > ui/iu(标在后一个) > i/u/ü
    toneMap := Map(
        "a", ["ā", "á", "ǎ", "à"],
        "o", ["ō", "ó", "ǒ", "ò"],
        "e", ["ē", "é", "ě", "è"],
        "i", ["ī", "í", "ǐ", "ì"],
        "u", ["ū", "ú", "ǔ", "ù"],
        "ü", ["ǖ", "ǘ", "ǚ", "ǜ"]
    )
    
    ; 1. 优先检查 a, o, e
    for vowel in ["a", "o", "e"] {
        if InStr(py, vowel) {
            ; 💖 核心修复：1 应该放在第 6 个参数位（Limit）来限制只替换 1 次
            ; 参数顺序：Haystack, Needle, ReplaceText, CaseSense, OutputVarCount, Limit
            return StrReplace(py, vowel, toneMap[vowel][tone], false, , 1)
        }
    }
    
    ; 2. 检查特殊的 ui 和 iu 组合（声调留在最后一个元音上）
    if InStr(py, "ui") {
        return StrReplace(py, "ui", "u" . toneMap["i"][tone], false, , 1)
    }
    if InStr(py, "iu") {
        return StrReplace(py, "iu", "i" . toneMap["u"][tone], false, , 1)
    }
    
    ; 3. 检查剩余的 i, u, ü
    for vowel in ["i", "u", "ü"] {
        if InStr(py, vowel) {
            return StrReplace(py, vowel, toneMap[vowel][tone], false, , 1)
        }
    }
    
    return py
}





; =========================================================================
; Percentage GUI Layout
; =========================================================================
CreatePracticeWindow() {
    global PracticeGui, WB, GuiW, GuiH, WebW, WebH, EditH, BtnW, BtnH, FontSize
    
    PracticeGui := Gui("+Resize -DPIScale", "姐儿妹儿拼音练习器")
    PracticeGui.SetFont("s" FontSize, "Microsoft YaHei")
    
    WebControl := PracticeGui.Add("ActiveX", "w" WebW " h" WebH " x15 y15", "Shell.Explorer")
    WB := WebControl.Value
    
    PracticeGui.Add("Text", "x15 y+10", "⌨️ 请在下方敲击键盘进行对照练习：")
    
    TypeCollector := PracticeGui.Add("Edit", "w" WebW " h" EditH " vTypedInput")
    TypeCollector.OnEvent("Change", OnTextChanged)
    
    LeftBtnW := Integer(BtnW * 0.9)
    
    UrlTextBtn := PracticeGui.Add("Button", "w" LeftBtnW " h" BtnH " x15 y+10", "🌐 GitHub导入")
    UrlTextBtn.OnEvent("Click", OnUrlTextClick)
    
    EditCurrentBtn := PracticeGui.Add("Button", "w" LeftBtnW " h" BtnH " x+12 yp", "📝 编辑当前文本")
    EditCurrentBtn.OnEvent("Click", OnEditCurrentTextClick)
    
    NewTextBtn := PracticeGui.Add("Button", "w" LeftBtnW " h" BtnH " x+12 yp", "🔄 导入新文章")
    NewTextBtn.OnEvent("Click", OnImportNewTextClick)
    
    ToggleModeBtn := PracticeGui.Add("Button", "w" BtnW " h" BtnH " x+20 yp vToggleModeBtn", "🔤 拼音模式")
    ToggleModeBtn.OnEvent("Click", OnToggleModeClick)
    
    PracticeGui.OnEvent("Close", OnGuiClose)
    
    OnMessage(0x0006, WM_ACTIVATE) 
    
    PracticeGui.Show("w" GuiW " h" GuiH)
    TypeCollector.Focus() 
}

WM_ACTIVATE(wParam, lParam, msg, hwnd) {
    global PracticeGui
    if (wParam != 0 && PracticeGui != "" && hwnd == PracticeGui.Hwnd) {
        SetTimer(() => (PracticeGui != "" ? PracticeGui["TypedInput"].Focus() : ""), -10)
    }
}

OnTextChanged(CtrlObj, *) {
    global G_UserTyped, G_RawChars
    
    currentInput := CtrlObj.Value
    if (currentInput == "")
        return
        
    if IsIMEComposing()
        return
        
    maxLen := G_RawChars.Length
    
    Loop Parse, currentInput {
        if (G_UserTyped.Length >= maxLen)
            break
            
        G_UserTyped.Push(A_LoopField)
        
        currentIdx := G_UserTyped.Length
        if (G_UserTyped[currentIdx] != G_RawChars[currentIdx]) {
            SoundBeep(440, 100) 
        }
    }
    
    CtrlObj.Value := ""
    RefreshWebGrid()
}

IsIMEComposing() {
    hwnd := WinExist("A")
    if !hwnd
        return false
    himc := DllCall("imm32\ImmGetContext", "Ptr", hwnd, "Ptr")
    if !himc
        return false
    len := DllCall("imm32\ImmGetCompositionString", "Ptr", himc, "UInt", 0x0008, "Ptr", 0, "UInt", 0, "Int") 
    DllCall("imm32\ImmReleaseContext", "Ptr", hwnd, "Ptr", himc)
    return len > 0
}
#HotIf WinActive("姐儿妹儿拼音练习器")
~LButton:: {
    global PracticeGui
    if (PracticeGui != "") {
        MouseGetPos ,, &clickedHwnd, &clickedCtrl
        if (clickedCtrl != "Button1" && clickedCtrl != "Button2" && clickedCtrl != "Button3" && clickedCtrl != "Button4") {
            SetTimer(() => (PracticeGui != "" ? PracticeGui["TypedInput"].Focus() : ""), -20)
        }
    }
}

$Backspace:: {
    global G_UserTyped
    
    if IsIMEComposing() {
        Send("{Backspace}")
        return
    }
    
    if (G_UserTyped.Length > 0) {
        G_UserTyped.Pop() 
        RefreshWebGrid()   
    }
}
#HotIf

OnGuiClose(*) {
    global G_UserTyped, G_CurrentOriginalText, SaveFile
    try {
        if FileExist(SaveFile) {
            FileDelete(SaveFile)
        }
        
        savedBuffer := ""
        for char in G_UserTyped {
            savedBuffer .= char
        }
        
        IniWrite(G_CurrentOriginalText, SaveFile, "SaveState", "InputText")
        IniWrite(savedBuffer, SaveFile, "SaveState", "TypedBuffer")
    } catch {
        ; Silent Exit
    }
    ExitApp()
}

OnUrlTextClick(*) {
    global PracticeGui
    targetUrl := "https://raw.githubusercontent.com/wjw8629/pinyin/refs/heads/main/1.txt"
    
    if (InStr(targetUrl, "您的用户名")) {
        MsgBox("请先右键编辑 AHK 脚本，将代码中 [OnUrlTextClick] 函数内的 targetUrl 修改为您真实的 GitHub 纯文本直链再使用哦！", "提示")
        return
    }
    
    ToolTip("🌐 正在从云端拉取最新练习文章，请稍候...")
    
    try {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.Open("GET", targetUrl, true)
        whr.Send()
        if (!whr.WaitForResponse(5)) { 
            throw Error("连接超时")
        }
        
        if (whr.Status != 200) {
            throw Error("HTTP 状态错误: " whr.Status)
        }
        
        responseText := whr.ResponseText
        ToolTip() 
        
        if (Trim(responseText) == "") {
            MsgBox("从云端成功获取了响应，但内容似乎为空，请检查文件！", "导入失败")
            return
        }
        
        ProcessAndStart(responseText, "", true)
        
    } catch Error as err {
        ToolTip()
        MsgBox("网络文章获取失败！`n请检查网络连接，或确保您的 GitHub 链接为公开的 Raw 直链。`n`n错误详细信息: " err.Message, "网络故障")
    }
}

OnEditCurrentTextClick(*) {
    global PracticeGui, G_CurrentOriginalText
    
    ModalGui := Gui("-MinimizeBox -MaximizeBox +Owner" PracticeGui.Hwnd, "编辑当前练习文本")
    ModalGui.SetFont("s11", "Microsoft YaHei")
    ModalGui.Add("Text",, "您可以在下方直接修改当前正在练习的段落：")
    
    EditField := ModalGui.Add("Edit", "w500 h180 vEditInputText +Multi", G_CurrentOriginalText)
    
    ConfirmBtn := ModalGui.Add("Button", "w120 x190 y+15 Default", "⚡ 确认修改")
    ConfirmBtn.OnEvent("Click", (*) => (
        txt := EditField.Value,
        ModalGui.Destroy(),
        Sleep(100), 
        ProcessAndStart(txt, "", true) 
    ))
    ModalGui.Show()
}

OnImportNewTextClick(*) {
    global PracticeGui
    
    ModalGui := Gui("-MinimizeBox -MaximizeBox +Owner" PracticeGui.Hwnd, "更换练习文章")
    ModalGui.SetFont("s11", "Microsoft YaHei")
    ModalGui.Add("Text",, "请在下方粘贴全新的中文练习段落：")
    NewInputField := ModalGui.Add("Edit", "w500 h180 vNewInputText +Multi", "")
    
    ConfirmBtn := ModalGui.Add("Button", "w120 x190 y+15 Default", "⚡ 确认更换")
    ConfirmBtn.OnEvent("Click", (*) => (
        txt := NewInputField.Value,
        ModalGui.Destroy(),
        Sleep(100), 
        ProcessAndStart(txt, "", true) 
    ))
    ModalGui.Show()
}

OnToggleModeClick(CtrlObj, *) {
    global G_PinyinOnlyMode, PracticeGui
    G_PinyinOnlyMode := !G_PinyinOnlyMode 
    
    if (G_PinyinOnlyMode) {
        CtrlObj.Text := "✨ 正常模式" 
    } else {
        CtrlObj.Text := "🔤 拼音模式"
    }
    
    RefreshWebGrid() 
    if (PracticeGui != "") {
        PracticeGui["TypedInput"].Focus() 
    }
}

RefreshWebGrid() {
    global G_RawChars, G_RawPinyins, G_UserTyped, WB, G_PinyinOnlyMode
    
    htmlBody := ""
    typedLength := G_UserTyped.Length
    
    Loop G_RawChars.Length {
        idx := A_Index
        ch := G_RawChars[idx]
        py := G_RawPinyins[idx]
        
        statusClass := "pending"      
        displayTypedChar := "&nbsp;"  
        
        if (ch == " ") {
            chDisp := "&nbsp;"
            pyDisp := "&nbsp;"
        } else {
            chDisp := G_PinyinOnlyMode ? "&nbsp;" : ch
            pyDisp := py
        }
        
        if (idx <= typedLength) {
            userChar := G_UserTyped[idx]
            displayTypedChar := (userChar == " ") ? "&nbsp;" : userChar
            
            if (userChar == ch) {
                statusClass := "correct"  
            } else {
                statusClass := "wrong"    
            }
        }
        
        if (idx == typedLength + 1) {
            statusClass .= " current"     
            htmlBody .= "<div id='active-node' class='word-block " statusClass "'>"
        } else {
            htmlBody .= "<div class='word-block " statusClass "'>"
        }
        
        htmlBody .= "  <div class='pinyin-cell'>" . pyDisp . "</div>"
                 . "  <div class='char-cell'>" . chDisp . "</div>"
                 . "  <div class='typed-cell'>" . displayTypedChar . "</div>"
                 . "</div>"
    }
    
    htmlHead := "<!DOCTYPE html><html><head><meta http-equiv='X-UA-Compatible' content='IE=edge'><meta charset='utf-8'><style>"
    
    htmlStyle := "html { font-size: 16px; } "
    htmlStyle .= "html, body { height: 100%; margin: 0; padding: 0; background-color: #FFFFFF; font-family: 'Microsoft YaHei', sans-serif; overflow-x: hidden; user-select: none; } "
    htmlStyle .= "body { box-sizing: border-box; padding: 15px 15px; } "
    htmlStyle .= ".main-container { display: flex; flex-direction: row; flex-wrap: wrap; width: 100%; text-align: left; padding: 0; margin: 0; } "
    
    htmlStyle .= ".word-block { display: inline-block; zoom: 1; vertical-align: bottom; min-width: 75px; max-width: 150px; text-align: center; margin: 0 5px 22px 5px; box-sizing: border-box; padding: 2px 2px; border-radius: 4px; border: 1px solid transparent; height: 98px; } "
    htmlStyle .= ".pinyin-cell { font-size: 1.0rem; color: #0066CC; font-family: 'Courier New', sans-serif; font-weight: bold; height: 18px; line-height: 1.1; text-align: center; width: 100%; word-break: break-all; overflow: hidden; } "
    htmlStyle .= ".char-cell { font-size: 1.55rem; color: #333333; height: 32px; line-height: 1.2; text-align: center; width: 100%; margin-top: 0px; font-weight: 500; } "
    htmlStyle .= ".typed-cell { font-size: 1.55rem; height: 38px; line-height: 1.4; text-align: center; width: 100%; margin-top: 0px; border-top: 1px dashed #DDD; padding-top: 6px; } "
    
    htmlStyle .= ".pending { color: #666666; background-color: #EEEEEE; border-color: #E5E5E5; } "
    
    htmlStyle .= ".correct { background-color: #EFFFF4; border-color: #A2E6B1; } .correct .typed-cell { color: #28A745; } "
    htmlStyle .= ".wrong { background-color: #FFF0F0; border-color: #FFA3A3; } .wrong .typed-cell { color: #DC3545; } "
    htmlStyle .= ".current { background-color: #FFF9E6; border-color: #FFE082; border-bottom: 2px solid #FFC107; } .current .char-cell { font-weight: bold; color: #B38600; } "
    htmlStyle .= "</style></head><body><div class='main-container'>" . htmlBody . "</div>"
    
    htmlScript := "<script>"
               . "window.onload = function() {"
               . "  var activeNode = document.getElementById('active-node');"
               . "  if (activeNode) {"
               . "    var rect = activeNode.getBoundingClientRect();"
               . "    var viewHeight = window.innerHeight || document.documentElement.clientHeight || document.body.clientHeight;"
               . "    "
               . "    if (viewHeight > 0) {"
               . "      if (rect.bottom > viewHeight || rect.top < 0) {"
               . "        activeNode.scrollIntoView(true);"
               . "        var currentScrollY = document.documentElement.scrollTop || document.body.scrollTop;"
               . "        if (currentScrollY > 15) {"
               . "          window.scrollTo(0, currentScrollY - 15);"
               . "        }"
               . "      } else {"
               . "        var currentScroll = document.documentElement.scrollTop || document.body.scrollTop;"
               . "        window.scrollTo(0, currentScroll);"
               . "      }"
               . "    }"
               . "  }"
               . "};"
               . "</script>"
    htmlEnd := "</body></html>"
    fullHtml := htmlHead . htmlStyle . htmlScript . htmlEnd
    htmlTemp := A_ScriptDir "\layout_temp.html"
    if FileExist(htmlTemp) {
        FileDelete(htmlTemp)
    }
    FileAppend(fullHtml, htmlTemp, "UTF-8")
    WB.Navigate(htmlTemp)
}
