#Requires AutoHotkey v2.0
#SingleInstance Force

; --- Global State Variables ---
global G_RawChars := []       
global G_RawPinyins := []     
global G_UserTyped := []      
global PracticeGui := ""      
global WB := ""               
global StudyGui := ""         
global StudyPrevBtn := ""    
global StudyNextBtn := ""    
global StudyIndexText := ""  
global StudyCharText := ""    
global TitleText := ""        
global WebControl := ""       
global TypeCollector := ""     
global SaveFile := A_ScriptDir "\progress_save.ini" 
global DictFile := A_ScriptDir "\custom_pinyin.txt"  ; Custom pinyin dictionary path
global InputTemp := A_ScriptDir "\dist\input_temp.txt"
;替换
global InputTemp := A_ScriptDir "\input_temp.txt"
;global OutputTemp := A_ScriptDir "\dist\output_temp.txt"
global OutputTemp := A_ScriptDir "\output_temp.txt"
;global OutputTemp := A_ScriptDir "\dist\output_temp.txt"
global PyScript := A_ScriptDir "\pinyin_core.py"
global PyExe := A_ScriptDir "\dist\pinyin_core\pinyin_core.exe"
global G_PinyinOnlyMode := false            

global ChatGui := ""
global ChatInput := ""
global ChatWeb := ""
global ChatWB := ""
global ChatSendBtn := ""
global ChatBtn := ""
global ChatIsReady := false
global ChatHistoryFile := ""
global ChatMessages := []
global ChatLastRenderHtml := ""
global ChatHistoryDirty := false
global ChatListenSocket := 0
global ChatSocketDLL := 0
global ChatLastSentText := ""
global ChatLastSentTick := 0
global ChatLogFile := A_ScriptDir "\chat_history_log.txt"
global ChatConfigFile := A_ScriptDir "\chat_config.ini"
global ChatPort := 28911
global ChatHistoryLimit := 1000
global ChatNickName := ""
global DownloadDictUrl := "https://raw.githubusercontent.com/wjw8629/pinyin/refs/heads/main/custom_pinyin.txt"  ; Leave blank and fill in the actual dictionary download URL later

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

    
    if FileExist(inputTemp)
        FileDelete(inputTemp)
    if FileExist(outputTemp)
        FileDelete(outputTemp)
        
    FileAppend(inputText, inputTemp, "UTF-8")
    if FileExist(PyExe)
            RunWait('"' PyExe '"', A_ScriptDir, "Hide")
        else if FileExist(PyScript)
            RunWait(A_ComSpec ' /c python "' PyScript '"', A_ScriptDir, "Hide")
        else {
            MsgBox("未找到 Python 转译引擎，请确保 dist 文件夹存在或安装了 Python。", "转译失败")
            return
        }
    
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
ApplyCustomPinyinDict(chars := unset, pinyins := unset) {
    global G_RawChars, G_RawPinyins, DictFile

    if IsSet(chars) {
        targetChars := chars
        targetPinyins := pinyins
    } else {
        targetChars := G_RawChars
        targetPinyins := G_RawPinyins
    }

    if !FileExist(DictFile)
        return

    fullText := ""
    for char in targetChars {
        fullText .= char
    }

    dictContent := FileRead(DictFile, "UTF-8")

    Loop Parse, dictContent, "`n", "`r" {
        line := Trim(A_LoopField)
        if (line == "" || InStr(line, "=") == 0)
            continue

        parts := StrSplit(line, "=")
        searchWord := Trim(parts[1])
        pinyinStr := Trim(parts[2])
        pinyinList := StrSplit(pinyinStr, ",")
        wordLen := StrLen(searchWord)

        if (wordLen == 0 || pinyinList.Length != wordLen)
            continue

        Loop pinyinList.Length {
            pinyinList[A_Index] := ConvertNumToTone(pinyinList[A_Index])
        }

        startPos := 1
        while (offset := InStr(fullText, searchWord, false, startPos)) {
            Loop wordLen {
                targetIdx := offset + A_Index - 1
                if (targetIdx <= targetPinyins.Length) {
                    targetPinyins[targetIdx] := pinyinList[A_Index]
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
    global PracticeGui, WB, GuiW, GuiH, WebW, WebH, EditH, BtnW, BtnH, FontSize, TitleText, WebControl, TypeCollector
    
    PracticeGui := Gui("+Resize -DPIScale", "姐儿妹儿拼音练习器")
    PracticeGui.SetFont("s" FontSize, "Microsoft YaHei")

    TitleText := PracticeGui.Add("Text", "x15 y15", "⌨️ 请在下方敲击键盘进行对照练习：")
    WebControl := PracticeGui.Add("ActiveX", "w" WebW " h" WebH " x15 y+10", "Shell.Explorer")
    WB := WebControl.Value

    TypeCollector := PracticeGui.Add("Edit", "w" WebW " h" EditH " x15 y+10 vTypedInput")
    TypeCollector.OnEvent("Change", OnTextChanged)

    LeftBtnW := Integer(BtnW * 0.9)
    NewTextBtn := PracticeGui.Add("Button", "w" LeftBtnW " h" BtnH " x15 y+10", "🔄 导入新文章")
    NewTextBtn.OnEvent("Click", OnImportNewTextClick)

    StudyBtn := PracticeGui.Add("Button", "w" LeftBtnW " h" BtnH " x+12 yp", "📖 生字练习")
    StudyBtn.OnEvent("Click", OnStudyModeClick)

    ToggleModeBtn := PracticeGui.Add("Button", "w" BtnW " h" BtnH " x+20 yp vToggleModeBtn", "🔤 拼音模式")
    ToggleModeBtn.OnEvent("Click", OnToggleModeClick)

    global ChatBtn
    ChatBtn := PracticeGui.Add("Button", "w" LeftBtnW " h" BtnH " x+12 yp", "💬 聊天")
    ChatBtn.OnEvent("Click", OnOpenChatClick)

    global DictDownloadBtn
    DictDownloadBtn := PracticeGui.Add("Button", "w" LeftBtnW " h" BtnH " x+12 yp", "📥 下载多音字字典")
    DictDownloadBtn.OnEvent("Click", OnDownloadDictionaryClick)

    PracticeGui.OnEvent("Close", OnGuiClose)
    PracticeGui.OnEvent("Size", OnPracticeGuiResize)

    OnMessage(0x0006, WM_ACTIVATE)

    PracticeGui.Show("w" GuiW " h" GuiH)
    TypeCollector.Focus()
}

OnPracticeGuiResize(GuiObj, MinMax, NewWidth, NewHeight) {
    global PracticeGui, WB, GuiW, GuiH, WebW, WebH, EditH, BtnW, BtnH, TitleText, WebControl, TypeCollector

    if (PracticeGui == "" || WB == "")
        return

    GuiW := Max(NewWidth, 380)
    GuiH := Max(NewHeight, 320)

    contentW := Max(300, GuiW - 30)
    leftBtnW := Max(100, Min(180, Integer(contentW * 0.22)))
    gap := Max(8, Integer(contentW * 0.015))
    toggleBtnW := Max(100, Min(180, Integer(contentW * 0.24)))

    WebW := Max(270, GuiW - 30)
    WebH := Max(120, Integer(GuiH * 0.72))
    EditH := Max(28, Integer(GuiH * 0.07))
    BtnW := Max(100, Min(180, Integer(GuiW * 0.20)))
    BtnH := Max(30, Integer(GuiH * 0.05))

    TitleText.Move(15, 15, contentW, 25)
    WebControl.Move(15, 45, WebW, WebH)
    TypeCollector.Move(15, 45 + WebH + 10, WebW, EditH)

    TypeCollector.GetPos(&inputX, &inputY, &inputW, &inputH)
    inputBottomY := inputY + inputH
    buttonY := Integer((inputBottomY + GuiH) / 2 - BtnH / 2)
    buttonY := Max(buttonY, inputBottomY + 10)

    NewTextBtnX := 15
    StudyBtnX := NewTextBtnX + leftBtnW + gap
    ToggleBtnX := StudyBtnX + leftBtnW + gap
    ChatBtnX := ToggleBtnX + toggleBtnW + gap
    DictBtnX := ChatBtnX + leftBtnW + gap

    PracticeGui["Button1"].Move(NewTextBtnX, buttonY, leftBtnW, BtnH)
    PracticeGui["Button2"].Move(StudyBtnX, buttonY, leftBtnW, BtnH)
    PracticeGui["Button3"].Move(ToggleBtnX, buttonY, toggleBtnW, BtnH)
    ChatBtn.Move(ChatBtnX, buttonY, leftBtnW, BtnH)
    DictDownloadBtn.Move(DictBtnX, buttonY, leftBtnW, BtnH)

    RefreshWebGrid()
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
        if (clickedCtrl != "Button1" && clickedCtrl != "Button2" && clickedCtrl != "Button3" && clickedCtrl != "Button4" && clickedCtrl != "Button5") {
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

OnUrlTextClick(ModalGui := "") {
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

        if (ModalGui != "") {
            ModalGui.Destroy()
            Sleep(100)
        }
        
        ProcessAndStart(responseText, "", true)
        
    } catch Error as err {
        ToolTip()
        MsgBox("网络文章获取失败！`n请检查网络连接，或确保您的 GitHub 链接为公开的 Raw 直链。`n`n错误详细信息: " err.Message, "网络故障")
    }
}

OnImportNewTextClick(*) {
    global PracticeGui, G_CurrentOriginalText
    
    modalW := Max(420, Min(620, GuiW))
    modalH := Max(260, Min(360, GuiH))
    inputW := modalW - 30
    inputH := Max(120, modalH - 112)

    ModalGui := Gui("-MinimizeBox -MaximizeBox +Owner" PracticeGui.Hwnd, "导入新文章")
    ModalGui.SetFont("s11", "Microsoft YaHei")
    ModalGui.Add("Text", "x15 y15", "请在下方输入或编辑正文：")
    NewInputField := ModalGui.Add("Edit", "w" inputW " h" inputH " x15 y+10 vNewInputText +Multi", G_CurrentOriginalText)

    NewInputField.GetPos(&inputX, &inputY, &inputW, &inputH)
    buttonW := Max(120, Min(150, Integer((modalW - 42) / 2)))
    buttonGap := 12
    buttonY := inputY + inputH + 12

    GitHubBtn := ModalGui.Add("Button", "w" buttonW " h36 x15 y" buttonY, "🌐 从 GitHub 导入")
    GitHubBtn.OnEvent("Click", (*) => OnUrlTextClick(ModalGui))

    ConfirmBtn := ModalGui.Add("Button", "w" buttonW " h36 x+" buttonGap " yp Default", "⚡ 确认更换")
    ConfirmBtn.OnEvent("Click", (*) => (
        txt := NewInputField.Value,
        ModalGui.Destroy(),
        Sleep(100),
        ProcessAndStart(txt, "", true)
    ))
    ModalGui.Show("w" modalW " h" modalH)
}

OnStudyModeClick(*) {
    global PracticeGui, StudyGui, StudyChars, StudyPinyins, StudyPageIndex

    if (PracticeGui == "")
        return

    StudyChars := GetUniqueStudyChars()
    if (StudyChars.Length == 0) {
        MsgBox("当前文本没有可用于生字练习的汉字。", "提示")
        return
    }

    StudyChars := NormalizeStudyChars(StudyChars)
    if (StudyChars.Length == 0) {
        MsgBox("当前文本中的生字有效字符为空，请重新导入。", "提示")
        return
    }

    StudyPinyins := []
    for idx, ch in StudyChars {
        StudyPinyins.Push(GetStudyPinyin(ch))
    }

    StudyPageIndex := 1
    ShuffleStudyChars()
    StudyChars := NormalizeStudyChars(StudyChars)
    if (StudyChars.Length == 0) {
        MsgBox("打乱后没有可显示的生字。", "提示")
        return
    }
    CreateStudyWindow()
    PracticeGui.Hide()
    StudyGui.Show("w" GuiW " h" GuiH)
}

GetUniqueStudyChars() {
    global G_RawChars
    seen := Map()
    chars := []

    for _, ch in G_RawChars {
        if (Trim(ch) == "" || seen.Has(ch))
            continue
        if (!RegExMatch(ch, "[\x{4e00}-\x{9fa5}]"))
            continue
        seen[ch] := true
        chars.Push(ch)
    }

    return chars
}

NormalizeStudyChars(chars) {
    normalized := []
    seen := Map()

    for _, ch in chars {
        if (Trim(ch) == "" || RegExMatch(ch, "\s"))
            continue
        if (!RegExMatch(ch, "[\x{4e00}-\x{9fa5}]"))
            continue
        if (seen.Has(ch))
            continue
        seen[ch] := true
        normalized.Push(ch)
    }

    return normalized
}

GetStudyPinyin(ch) {
    global G_RawChars, G_RawPinyins

    for idx, rawChar in G_RawChars {
        if (rawChar == ch) {
            return G_RawPinyins[idx]
        }
    }

    return ch
}

ShuffleStudyChars() {
    global StudyChars

    Loop StudyChars.Length - 1 {
        index := StudyChars.Length - A_Index + 1
        j := Random(1, index)
        temp := StudyChars[index]
        StudyChars[index] := StudyChars[j]
        StudyChars[j] := temp
    }
}

CreateStudyWindow() {
    global StudyGui, StudyPrevBtn, StudyNextBtn, StudyIndexText, StudyCharText, GuiW, GuiH, FontSize
    global StudyChars, StudyPinyins, StudyPageIndex

    if (StudyGui != "") {
        StudyGui.Destroy()
        StudyGui := ""
    }

        StudyGui := Gui("+Resize -DPIScale", "生字练习 · 单字翻页")
    
    ; 1. 明确设置窗口的内边距，让整体布局更美观
    StudyGui.MarginX := 20
    StudyGui.MarginY := 20

    ; 标题行
    StudyGui.SetFont("s" FontSize + 4, "Microsoft YaHei")
    StudyGui.Add("Text", "x15 y15 w" (GuiW - 30), "📖 认识生字 · 随机单字练习")

    ; 2. 居中大区域的宽度（去掉两侧按钮占用的空间）
    local CenterAreaW := GuiW - 260

    ; 3. 顶部进度文本：使用相对定位，明确限制高度防止被下方的巨型字冲散
    StudyGui.SetFont("s18", "Microsoft YaHei")
    StudyIndexText := StudyGui.Add("Text", "x130 y+20 w" CenterAreaW " h35 Center", "当前共有 " StudyChars.Length " 个字")

    ; 4. 超大汉字区域：y+10 表示紧跟在进度文本下方 10 像素，不再使用绝对的 y80
    ; 同时把高度 h 设为自动（不写 h），让 AHK 自动根据 s220 申请足够的纵向空间，彻底杜绝重叠！
    StudyGui.SetFont("s220 Bold", "Microsoft YaHei")
    StudyCharText := StudyGui.Add("Text", "x130 y+10 w" CenterAreaW " Center", "")

    ; 5. 调整左右翻页按钮的 Y 轴坐标：让他们根据超大汉字居中对齐
    ; 获取大汉字控件的坐标信息，动态计算出按钮最完美的垂直居中位置
    StudyCharText.GetPos(&cX, &cY, &cW, &cH)
    local BtnY := cY + Integer((cH - 80) / 2)

    ; 左翻页按钮
    StudyGui.SetFont("s24", "Microsoft YaHei") ; 让箭头的符号也稍微大一点
    StudyPrevBtn := StudyGui.Add("Button", "x15 y" BtnY " w100 h80", "←")
    StudyPrevBtn.OnEvent("Click", (*) => GoStudyPage(-1))

    ; 右翻页按钮（精准靠在右侧边缘内）
    StudyNextBtn := StudyGui.Add("Button", "x" (GuiW - 115) " y" BtnY " w100 h80", "→")
    StudyNextBtn.OnEvent("Click", (*) => GoStudyPage(1))

    StudyGui.OnEvent("Close", OnReturnToPractice)

    ; 首次进入生字界面时，立即读取并显示第一个有效生字
    RefreshStudyPage()

    ; 6. 务必确保你在下面显示窗口时，传入了正确的 GuiW 和 GuiH
    ; StudyGui.Show("w" GuiW " h" (cY + cH + 40)) ; 建议高度根据内容自动撑开，更不容易出错

}

OnStudyGuiResize(GuiObj, MinMax, NewWidth, NewHeight) {
    global StudyPrevBtn, StudyNextBtn, StudyIndexText, StudyCharText, GuiW, GuiH

    if (StudyPrevBtn == "" || StudyNextBtn == "" || StudyIndexText == "" || StudyCharText == "")
        return

    GuiW := Max(NewWidth, 380)
    GuiH := Max(NewHeight, 320)

    leftMargin := 15
    rightMargin := 115
    cardX := 125
    cardW := Max(130, GuiW - 240)
    cardH := Max(120, GuiH - 160)
    navY := Integer((GuiH - 80) / 2)

    ; 左右按钮与文字区域互不重叠
    StudyPrevBtn.Move(leftMargin, navY, 100, 80)
    StudyIndexText.Move(cardX, 25, cardW, 30)
    StudyCharText.Move(cardX, 80, cardW, cardH)
    StudyNextBtn.Move(GuiW - rightMargin, navY, 100, 80)

    charFont := Max(120, Min(220, Integer(Min(GuiW, GuiH) * 0.45)))
    StudyCharText.SetFont("s" charFont, "Microsoft YaHei")
    RefreshStudyPage()
}

GoStudyPage(step) {
    global StudyChars, StudyPageIndex

    if (StudyChars.Length == 0)
        return

    nextIndex := StudyPageIndex + step
    if (nextIndex < 1)
        nextIndex := StudyChars.Length
    else if (nextIndex > StudyChars.Length)
        nextIndex := 1

    StudyPageIndex := nextIndex
    RefreshStudyPage()
}

RefreshStudyPage() {
    global StudyGui, StudyIndexText, StudyCharText, StudyChars, StudyPageIndex, GuiW, GuiH

    if (StudyGui == "" || StudyIndexText == "" || StudyCharText == "" || StudyChars.Length == 0)
        return

    if (StudyPageIndex < 1 || StudyPageIndex > StudyChars.Length)
        StudyPageIndex := 1

    while (StudyPageIndex <= StudyChars.Length && Trim(StudyChars[StudyPageIndex]) == "") {
        StudyChars.RemoveAt(StudyPageIndex)
        if (StudyPageIndex > StudyChars.Length)
            StudyPageIndex := 1
    }

    if (StudyChars.Length == 0)
        return

    currentChar := StudyChars[StudyPageIndex]
    StudyIndexText.Text := "当前共有 " StudyChars.Length " 个字"
    StudyCharText.Text := currentChar

    if (StudyCharText != "") {
        charFont := Max(120, Min(220, Integer(Min(GuiW, GuiH) * 0.45)))
        StudyCharText.SetFont("s" charFont, "Microsoft YaHei")
    }
}

OnReturnToPractice(*) {
    global PracticeGui, StudyGui

    if (StudyGui != "") {
        StudyGui.Destroy()
        StudyGui := ""
    }
    if (PracticeGui != "") {
        PracticeGui.Show("w" GuiW " h" GuiH)
        PracticeGui["TypedInput"].Focus()
    }
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
    htmlStyle .= ".char-cell { font-size: 1.52rem; color: #333333; height: 32px; line-height: 1.2; text-align: center; width: 100%; margin-top: 0px; font-weight: 500; } "
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

; =========================================================================
; � Dictionary download
; =========================================================================
OnDownloadDictionaryClick(*) {
    global DownloadDictUrl

    if (Trim(DownloadDictUrl) == "") {
        MsgBox("请先在脚本顶部设置 DownloadDictUrl，再点击下载多音字字典。", "下载地址未配置")
        return
    }

    targetFile := DictFile
    ToolTip("📥 正在下载并覆盖 custom_pinyin.txt，请稍候...")

    try {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.Open("GET", DownloadDictUrl, true)
        whr.Send()
        if (!whr.WaitForResponse(10))
            throw Error("连接超时")
        if (whr.Status != 200)
            throw Error("HTTP 状态错误: " whr.Status)

        if (FileExist(targetFile))
            FileDelete(targetFile)
        FileAppend(whr.ResponseText, targetFile, "UTF-8")
        ToolTip("✅ 已下载并覆盖 custom_pinyin.txt")
        SetTimer(() => ToolTip(), -2000)
    } catch Error as err {
        ToolTip()
        MsgBox("下载并覆盖 custom_pinyin.txt 失败！`n请检查下载地址和网络连接。`n`n错误详细信息: " err.Message, "下载失败")
    }
}

; =========================================================================
; �💬 Chat integration (lazy initialization to avoid startup delay)
; =========================================================================
OnOpenChatClick(*) {
    global ChatGui, ChatBtn, ChatIsReady, ChatInput

    if (ChatIsReady && ChatGui != "") {
        ChatGui.Show()
        ChatInput.Focus()
        return
    }

    InitChat()
    if (ChatIsReady && ChatGui != "") {
        ChatGui.Show()
        ChatInput.Focus()
    }
}

InitChat() {
    global ChatGui, ChatInput, ChatWeb, ChatWB, ChatSendBtn, ChatNickName
    global ChatHistoryFile, ChatMessages, ChatIsReady, ChatLogFile, ChatConfigFile
    global ChatPort, ChatHistoryLimit, ChatListenSocket, ChatSocketDLL
    global ChatLastSentText, ChatLastSentTick

    if (ChatIsReady)
        return

    if !FileExist(DictFile) {
        FileAppend("不易=bu2,yi4", DictFile, "UTF-8")
    }

    if FileExist(ChatConfigFile) {
        try ChatNickName := IniRead(ChatConfigFile, "UserInfo", "Nickname", "")
    }
    if (ChatNickName = "") {
        ChatNickName := EnvGet("USERNAME")
        try IniWrite(ChatNickName, ChatConfigFile, "UserInfo", "Nickname")
    }

    try {
        ChatHistoryFile := FileOpen(ChatLogFile, "a", "UTF-8")
    } catch {
        MsgBox("无法打开聊天历史：" ChatLogFile, "错误")
        return
    }

    LoadChatHistory()
    CreateChatWindow()
    InitChatSocket()
    ChatIsReady := true
    RefreshWebChat()
}

InitChatSocket() {
    global ChatSocketDLL, ChatListenSocket, ChatPort

    ChatSocketDLL := DllCall("LoadLibrary", "Str", "Ws2_32.dll", "Ptr")
    WSAData := Buffer(400, 0)
    if DllCall("Ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", WSAData) {
        MsgBox("聊天网络初始化失败。", "错误")
        CleanUpChat(false)
        return
    }

    ChatListenSocket := DllCall("Ws2_32\socket", "Int", 2, "Int", 2, "Int", 17, "Ptr")
    if (ChatListenSocket = -1) {
        MsgBox("聊天端口创建失败。", "错误")
        CleanUpChat(false)
        return
    }

    optVal := Buffer(4, 0)
    NumPut("Int", 1, optVal, 0)
    DllCall("Ws2_32\setsockopt", "Ptr", ChatListenSocket, "Int", 0xffff, "Int", 0x0020, "Ptr", optVal, "Int", 4)

    addr := Buffer(16, 0)
    NumPut("UShort", 2, addr, 0)
    NumPut("UShort", DllCall("Ws2_32\htons", "UShort", ChatPort, "UShort"), addr, 2)
    if DllCall("Ws2_32\bind", "Ptr", ChatListenSocket, "Ptr", addr, "Int", 16) = -1 {
        MsgBox("聊天端口 " ChatPort " 已被占用。", "错误")
        CleanUpChat(false)
        return
    }

    OnMessage(0x4001, ReceiveChatData)
    DllCall("Ws2_32\WSAAsyncSelect", "Ptr", ChatListenSocket, "Ptr", ChatGui.Hwnd, "UInt", 0x4001, "Int", 1)
}

CreateChatWindow() {
    global ChatGui, ChatInput, ChatWeb, ChatWB, ChatSendBtn, ChatNickName

    ChatGui := Gui("+Resize", "内网拼音群聊")
    ChatGui.SetFont("s10.5", "Microsoft YaHei")
    ChatGui.Add("Text", "x15 y12 vChatNameText", "当前昵称: " ChatNickName)

    nameBtn := ChatGui.Add("Button", "x+10 y8 w75 h22", "修改名字")
    nameBtn.SetFont("s9", "Microsoft YaHei")
    nameBtn.OnEvent("Click", OnChangeChatNameClick)

    ChatWeb := ChatGui.Add("ActiveX", "x15 y38 w390 h324", "Shell.Explorer")
    ChatWB := ChatWeb.Value

    ChatInput := ChatGui.Add("Edit", "x15 y+12 w300 h100 +Multi")
    ChatInput.SetFont("s10", "Microsoft YaHei")
    ChatSendBtn := ChatGui.Add("Button", "x+8 yp w82 h100", "发送")
    ChatSendBtn.OnEvent("Click", OnSendChatMessage)

    ChatGui.OnEvent("Size", OnChatGuiResize)
    ChatGui.OnEvent("Close", (*) => CleanUpChat(false))
    ChatGui.Show("w420 h550")
    ChatInput.Focus()
}

OnChatGuiResize(GuiObj, MinMax, Width, Height) {
    global ChatInput, ChatWeb, ChatSendBtn
    if (MinMax = -1)
        return

    padding := 15
    gap := 8
    bottomReserve := 80
    webHeight := Max(120, Height - 38 - bottomReserve)
    ChatWeb.Move(padding, 38, Width - padding * 2, webHeight)
    ChatWeb.GetPos(&webX, &webY, &webW, &webH)

    inputY := webY + webH + gap
    inputHeight := Max(60, Height - inputY - padding)
    buttonHeight := inputHeight
    buttonWidth := Max(65, Min(90, Width - 2 * padding - 300))
    inputWidth := Width - buttonWidth - padding * 3

    ChatInput.Move(padding, inputY, inputWidth, inputHeight)
    ChatSendBtn.Move(Width - padding - buttonWidth, inputY, buttonWidth, buttonHeight)
}

#HotIf WinActive("内网拼音群聊")
$Enter:: {
    if (ChatIsReady && ChatInput != "") {
        if (IsChatIMEComposing())
            return
        OnSendChatMessage()
    }
}
#HotIf

OnSendChatMessage(*) {
    global ChatInput, ChatNickName, ChatLastSentText, ChatLastSentTick, ChatMessages

    text := Trim(ChatInput.Value, "`r`n ")
    if (text = "")
        return

    text := RegExReplace(text, "[\r\n]+", " ")
    ChatInput.Value := ""
    ChatInput.Focus()

    if !SendChatUdpMessage(ChatNickName, text) {
        ChatInput.Value := text
        ChatInput.Focus()
        MsgBox("消息发送失败，请检查局域网连接。", "发送失败")
        return
    }

    ChatLastSentText := text
    ChatLastSentTick := A_TickCount
    AddChatMessage(ChatNickName, text)
    SaveChatHistory()
    RefreshWebChat()
}

OnChangeChatNameClick(*) {
    global ChatNickName, ChatConfigFile, ChatGui

    modal := Gui("-MinimizeBox -MaximizeBox +Owner" ChatGui.Hwnd, "更换群聊昵称")
    modal.SetFont("s10", "Microsoft YaHei")
    modal.Add("Text", "x15 y15", "请输入新的群聊昵称：")
    input := modal.Add("Edit", "x15 y+8 w260", ChatNickName)
    btn := modal.Add("Button", "x175 y+12 w100 Default", "保存")
    btn.OnEvent("Click", (*) => SaveChatName(modal, input.Value))
    modal.Show("w290 h115")
}

SaveChatName(modal, value) {
    global ChatNickName, ChatConfigFile, ChatGui

    value := Trim(value)
    if (value = "") {
        MsgBox("昵称不能为空。", "提示")
        return
    }

    ChatNickName := value
    try IniWrite(ChatNickName, ChatConfigFile, "UserInfo", "Nickname")
    ChatGui["ChatNameText"].Value := "当前昵称: " ChatNickName
    modal.Destroy()
    RefreshWebChat()
}

ReceiveChatData(wParam, lParam, msg, hwnd) {
    global ChatListenSocket, ChatNickName, ChatLastSentText, ChatLastSentTick

    event := lParam & 0xFFFF
    error := (lParam >> 16) & 0xFFFF
    if (error != 0 || event != 1)
        return

    buf := Buffer(65536, 0)
    addr := Buffer(16, 0)
    addrLen := Buffer(4, 0)
    NumPut("Int", 16, addrLen, 0)

    bytes := DllCall("Ws2_32\recvfrom", "Ptr", ChatListenSocket, "Ptr", buf, "Int", 65536, "Int", 0, "Ptr", addr, "Ptr", addrLen, "Int")
    if (bytes <= 0)
        return

    data := StrGet(buf, bytes, "UTF-8")
    parts := StrSplit(data, "|||", , 2)
    if (parts.Length != 2 || parts[1] = "" || parts[2] = "")
        return
    if (parts[1] = ChatNickName && parts[2] = ChatLastSentText && (A_TickCount - ChatLastSentTick) < 3000)
        return

    AddChatMessage(parts[1], parts[2])
    SaveChatHistory()
    RefreshWebChat()
}

SendChatUdpMessage(sender, text) {
    global ChatListenSocket, ChatPort
    data := sender "|||" text
    addr := Buffer(16, 0)
    NumPut("UShort", 2, addr, 0)
    NumPut("UShort", DllCall("Ws2_32\htons", "UShort", ChatPort, "UShort"), addr, 2)
    NumPut("UInt", DllCall("Ws2_32\inet_addr", "AStr", "255.255.255.255"), addr, 4)

    buf := Buffer(StrPut(data, "UTF-8"), 0)
    size := StrPut(data, buf, "UTF-8") - 1

    Loop 3 {
        sent := DllCall("Ws2_32\sendto", "Ptr", ChatListenSocket, "Ptr", buf, "Int", size, "Int", 0, "Ptr", addr, "Int", 16)
        if (sent = size)
            return true
        Sleep(50)
    }
    return false
}

AddChatMessage(sender, text) {
    global ChatMessages

    sender := StrReplace(sender, "`r", "")
    sender := StrReplace(sender, "`n", " ")
    text := StrReplace(text, "`r", "")
    text := StrReplace(text, "`n", " ")
    if (text = "")
        return

    ChatMessages.Push({sender: sender, text: text, html: BuildChatPinyinHtml(text), translated: true})
    if (ChatMessages.Length > ChatHistoryLimit)
        ChatMessages.RemoveAt(1, ChatMessages.Length - ChatHistoryLimit)
}

LoadChatHistory() {
    global ChatMessages, ChatLogFile, ChatHistoryLimit

    if !FileExist(ChatLogFile)
        return

    try content := FileRead(ChatLogFile, "UTF-8")
    catch
        return

    for line in StrSplit(content, "`n", "`r") {
        if (Trim(line) = "")
            continue
        parts := StrSplit(line, "`t", , 3)
        if (parts.Length = 2 && parts[1] != "" && parts[2] != "") {
            ChatMessages.Push({sender: parts[1], text: parts[2], html: BuildChatPinyinHtml(parts[2]), translated: true})
            continue
        }
        if (parts.Length = 3 && parts[1] != "" && parts[2] != "" && parts[3] != "")
            ChatMessages.Push({sender: parts[1], text: parts[2], html: parts[3], translated: true})
    }
    if (ChatMessages.Length > ChatHistoryLimit)
        ChatMessages.RemoveAt(1, ChatMessages.Length - ChatHistoryLimit)
}

SaveChatHistory() {
    global ChatMessages, ChatHistoryFile, ChatLogFile

    if (ChatHistoryFile = "" || ChatMessages.Length = 0)
        return

    ChatHistoryFile.Close()
    try ChatHistoryFile := FileOpen(ChatLogFile, "w", "UTF-8")
    catch
        return

    for message in ChatMessages {
        if (IsObject(message) && message.text != "")
            ChatHistoryFile.WriteLine(message.sender "`t" message.text "`t" message.html)
    }
    ChatHistoryFile.Close()
    ChatHistoryFile := FileOpen(ChatLogFile, "a", "UTF-8")
}

BuildChatPinyinHtml(text) {
    global InputTemp, OutputTemp, PyScript, PyExe, DictFile, ChatMessages

    if (text = "")
        return ""

    try {
        FileOpen(InputTemp, "w", "UTF-8").Write(text)
        FileOpen(OutputTemp, "w", "UTF-8").Write("")
         if FileExist(PyExe)
            RunWait('"' PyExe '"', A_ScriptDir, "Hide")
        else if FileExist(PyScript)
            RunWait(A_ComSpec ' /c python "' PyScript '"', A_ScriptDir, "Hide")
        else {
            MsgBox("未找到 Python 转译引擎，请确保 dist 文件夹存在或安装了 Python。", "转译失败")
            return
        }

        if !FileExist(OutputTemp)
            throw Error("拼音引擎未生成结果")

        result := FileRead(OutputTemp, "UTF-8")
        chars := []
        pinyins := []
        pos := 1
        while RegExMatch(result, "m)^([^\t\r\n]+)\t([^\t\r\n]*)", &m, pos) {
            pos := m.Pos + m.Len
            chars.Push(m[1])
            pinyins.Push(m[2] = "" ? m[1] : m[2])
        }
        if (chars.Length = 0)
            return BuildChatPlainHtml(text)

        ApplyCustomPinyinDict(chars, pinyins)
        html := ""
        for i, ch in chars {
            if (ch = " ")
                html .= "<span class='word-box'><span class='py-cell'>&nbsp;</span><span class='ch-cell'>&nbsp;</span></span>"
            else
                html .= "<span class='word-box'><span class='py-cell'>" HtmlEncode(pinyins[i]) "</span><span class='ch-cell'>" HtmlEncode(ch) "</span></span>"
        }
        return html
    } catch {
        return BuildChatPlainHtml(text, "拼音处理错误")
    }
}

BuildChatPlainHtml(text, error := "") {
    html := "<span class='plain-text'>" HtmlEncode(text) "</span>"
    if (error != "")
        html .= "<div style='color:#B00020;font-size:11px'>" error "</div>"
    return html
}

RefreshWebChat() {
    global ChatMessages, ChatWB, ChatNickName, ChatLastRenderHtml

    if (ChatWB = "")
        return

    body := ""
    for message in ChatMessages {
        name := HtmlEncode(message.sender)
        if (message.sender = ChatNickName)
            name .= " (我)"
        htmlText := message.html
        if (htmlText = "")
            htmlText := BuildChatPlainHtml(message.text)
        body .= "<div class='msg-row'><div class='sender-name'>" name "</div><div class='msg-bubble'>" htmlText "</div></div>"
    }

    html := "<!DOCTYPE html><html><head><meta http-equiv='X-UA-Compatible' content='IE=edge'><meta charset='utf-8'><style>"
    html .= "html,body{margin:0;padding:0;background:#F5F7FA;font-family:'Microsoft YaHei',sans-serif;font-size:14px;overflow-x:hidden;}body{box-sizing:border-box;padding:10px;}"
    html .= ".msg-row{display:flex;flex-direction:column;margin-bottom:14px;width:100%;}.sender-name{font-size:1rem;color:#777;margin-bottom:4px;padding:0 4px;font-weight:bold;}.msg-bubble{display:inline-block;max-width:92%;padding:7px;border-radius:8px;box-shadow:0 1px 2px rgba(0,0,0,.04);word-wrap:break-word;align-self:flex-start;background:#FFF;border:1px solid #E4E7ED;color:#333;border-top-left-radius:2px;}.word-box{display:inline-flex;flex-direction:column;vertical-align:bottom;text-align:center;margin:2px 4px 4px;min-width:24px;line-height:1;}.py-cell{display:block;font-size:1.1rem;color:#0066CC;font-family:'Courier New',sans-serif;font-weight:bold;line-height:1.1;height:1.1em;white-space:nowrap;}.ch-cell{display:block;font-size:1.2rem;color:#2C3E50;line-height:1.15;font-weight:500;white-space:nowrap;}.plain-text{font-size:1.45rem;line-height:1.4;white-space:pre-wrap;}</style></head><body>" body
    html .= "<script>window.onload=function(){window.scrollTo(0,document.body.scrollHeight);};</script></body></html>"

    if (html != ChatLastRenderHtml) {
        ChatLastRenderHtml := html
        file := A_ScriptDir "\chat_layout_temp.html"
        try {
            FileOpen(file, "w", "UTF-8").Write(html)
            ChatWB.Navigate(file)
        } catch {
            try {
                ChatWB.Navigate("about:blank")
                ChatWB.Document.Write(html)
                ChatWB.Document.Close()
            }
        }
    }
}

IsChatIMEComposing() {
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

CleanUpChat(quitApp := true) {
    global ChatHistoryFile, ChatListenSocket, ChatSocketDLL, ChatGui, ChatIsReady

    if (ChatHistoryFile != "") {
        ChatHistoryFile.Close()
        ChatHistoryFile := ""
    }
    if (ChatListenSocket != 0) {
        DllCall("Ws2_32\closesocket", "Ptr", ChatListenSocket, "Ptr")
        ChatListenSocket := 0
    }
    if (ChatSocketDLL != 0) {
        DllCall("FreeLibrary", "Ptr", ChatSocketDLL)
        ChatSocketDLL := 0
    }
    if (ChatGui != "") {
        ChatGui.Destroy()
        ChatGui := ""
    }
    ChatIsReady := false
    if (quitApp)
        ExitApp()
}

HtmlEncode(text) {
    text := StrReplace(text, "&", "&amp;")
    text := StrReplace(text, "<", "&lt;")
    text := StrReplace(text, ">", "&gt;")
    text := StrReplace(text, '"', "&quot;")
    text := StrReplace(text, "'", "&#39;")
    return text
}
