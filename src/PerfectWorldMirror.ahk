#NoEnv
#InstallMouseHook
#SingleInstance, force
#Persistent
SetBatchLines, -1
ListLines, Off

; =============================
; Globals
; =============================

mirrorEnabled := False
isMirroring := False
mainHwnd := ""
targetHwnd := ""
windowFilter := "Perfect World"
mirrorIntervalSec := 0
mirrorIntervalMs := 0
mirrorQueue := []
logMessages := []
maxLogEntries := 12
sessionHasFocus := False
sessionOrigX := 0
sessionOrigY := 0

batchActive := False
batchEvents := []
batchStartTick := 0
batchTimeoutMs := 800
nextGroupId := 1

SetTimer, ProcessMirrorQueue, 30

; =============================
; GUI Setup
; =============================

Gui, New, +AlwaysOnTop +Resize +MinSize420x440, Perfect World Click Mirror
Gui, Color, 1b1f24, 111418
Gui, Font, cF1F1F1 s10, Segoe UI

Gui, Add, Text, x16 y16, Window filter
Gui, Add, Edit, x16 y36 w250 vWindowFilter gOnFilterEdit, %windowFilter%
Gui, Add, Button, x276 y34 w110 h28 gRefreshWindowList, Refresh

Gui, Add, Text, x16 y80, Source (primary) window
Gui, Add, DropDownList, x16 y100 w370 vSourceWindow gOnSelectSource

Gui, Add, Text, x16 y144, Mirror (secondary) window
Gui, Add, DropDownList, x16 y164 w370 vTargetWindow gOnSelectTarget

Gui, Add, Text, x16 y210, Delay (seconds)
Gui, Add, Edit, x16 y230 w90 vDelaySeconds gOnDelayChange, %mirrorIntervalSec%
Gui, Add, Button, x116 y226 w140 h34 vToggleButton gToggleMirroring, Start mirroring
Gui, Add, Button, x266 y226 w120 h34 gSwapWindows, Swap windows

Gui, Font, cA5D6FF s9, Consolas
Gui, Add, Text, x16 y280, Queue pending
Gui, Add, Text, x120 y280 w80 vQueueLine, 0
Gui, Font, cF1F1F1 s9, Segoe UI
Gui, Add, Edit, x16 y304 w370 h130 vLogBox +ReadOnly -Wrap -VScroll

Gui, Show, w410 h470

Gosub, RefreshWindowList
AppendLog("Ready.")
return

; =============================
; GUI Handlers
; =============================

OnFilterEdit:
    GuiControlGet, windowFilter,, WindowFilter
return

RefreshWindowList:
    GuiControlGet, windowFilter,, WindowFilter

    GuiControl,, SourceWindow, |
    GuiControl,, TargetWindow, |

    options := ""
    WinGet, winList, List
    Loop, %winList%
    {
        thisHwnd := winList%A_Index%
        if !DllCall("IsWindowVisible", "ptr", thisHwnd)
            continue
        WinGetTitle, thisTitle, ahk_id %thisHwnd%
        if (thisTitle = "")
            continue
        cleanedTitle := StrReplace(thisTitle, "|", "/")
        if (windowFilter != "" && !InStr(cleanedTitle, windowFilter))
            continue
        display := Format("{1} [{2}]", cleanedTitle, Format("0x{:X}", thisHwnd))
        if (options = "")
            options := display
        else
            options .= "|" display
    }

    if (options = "")
        options := "<no matching windows>"

    GuiControl,, SourceWindow, %options%
    GuiControl,, TargetWindow, %options%

    label := GetWindowLabel(mainHwnd)
    if (label != "")
        GuiControl, ChooseString, SourceWindow, %label%

    label := GetWindowLabel(targetHwnd)
    if (label != "")
        GuiControl, ChooseString, TargetWindow, %label%

    AppendLog("Window list refreshed.")
return

OnSelectSource:
    GuiControlGet, choice,, SourceWindow
    mainHwnd := ExtractHwnd(choice)
    if (mainHwnd = "")
    {
        AppendLog("No valid source window selected.")
        return
    }
    AppendLog("Source set to " choice)
return

OnSelectTarget:
    GuiControlGet, choice,, TargetWindow
    targetHwnd := ExtractHwnd(choice)
    if (targetHwnd = "")
    {
        AppendLog("No valid mirror window selected.")
        return
    }
    AppendLog("Mirror set to " choice)
return

OnDelayChange:
    GuiControlGet, rawDelay,, DelaySeconds
    rawDelay := Trim(rawDelay)
    if (rawDelay = "")
        rawDelay := 0
    if rawDelay is not number
    {
        mirrorIntervalSec := 0
        mirrorIntervalMs := 0
        GuiControl,, DelaySeconds, 0
        AppendLog("Delay must be numeric; reset to 0.")
        return
    }
    if (rawDelay < 0)
        rawDelay := 0
    mirrorIntervalSec := rawDelay
    mirrorIntervalMs := Round(mirrorIntervalSec * 1000)
    AppendLog(Format("Delay set to {1} second(s).", mirrorIntervalSec))
return

ToggleMirroring:
    if (!mirrorEnabled)
    {
        if (mainHwnd = "" || targetHwnd = "")
        {
            AppendLog("Select both windows before starting.")
            return
        }
        if (mainHwnd = targetHwnd)
        {
            AppendLog("Source and mirror must be different.")
            return
        }
        mirrorEnabled := True
        GuiControl,, ToggleButton, Stop mirroring
        AppendLog("Mirroring enabled.")
    }
    else
    {
        mirrorEnabled := False
        mirrorQueue := []
        UpdateQueueIndicator()
        GuiControl,, ToggleButton, Start mirroring
        AppendLog("Mirroring paused and queue cleared.")
        ResetBatchState()
    }
return

SwapWindows:
    if (mainHwnd = "" && targetHwnd = "")
        return

    temp := mainHwnd
    mainHwnd := targetHwnd
    targetHwnd := temp

    srcLabel := GetWindowLabel(mainHwnd)
    tgtLabel := GetWindowLabel(targetHwnd)
    if (srcLabel != "")
        GuiControl, ChooseString, SourceWindow, %srcLabel%
    if (tgtLabel != "")
        GuiControl, ChooseString, TargetWindow, %tgtLabel%

    AppendLog("Source and mirror swapped.")
return

GuiClose:
GuiEscape:
    ExitApp
return

; =============================
; Mouse / Key hooks
; =============================

~LButton Up::
    if (!mirrorEnabled || isMirroring)
        return
    if (mainHwnd = "" || targetHwnd = "")
        return
    if !WinActive("ahk_id " mainHwnd)
        return
    QueueClickEvent()
return

~Space::
    if (!mirrorEnabled || isMirroring)
        return
    if (mainHwnd = "" || targetHwnd = "")
        return
    if !WinActive("ahk_id " mainHwnd)
        return
    QueueKeyEvent("Space")
return

; =============================
; Queue management
; =============================

ProcessMirrorQueue:
    global mirrorQueue, mirrorEnabled, isMirroring
    if (isMirroring)
        return
    if (!mirrorEnabled)
    {
        if (QueueCount() > 0)
        {
            mirrorQueue := []
            UpdateQueueIndicator()
        }
        return
    }
    if (QueueCount() = 0)
        return

    now := A_TickCount
    nextEvent := mirrorQueue[1]
    if (nextEvent.time > now)
        return

    groupId := nextEvent.group
    events := []
    while (QueueCount() > 0 && mirrorQueue[1].group = groupId)
    {
        events.Push(mirrorQueue[1])
        mirrorQueue.RemoveAt(1)
    }

    if (events.MaxIndex())
    {
        ExecuteMirrorGroup(events)
        UpdateQueueIndicator()
    }
return

QueueClickEvent()
{
    global mainHwnd
    CoordMode, Mouse, Screen
    MouseGetPos, mouseX, mouseY
    VarSetCapacity(pt, 8, 0)
    NumPut(mouseX, pt, 0, "int")
    NumPut(mouseY, pt, 4, "int")
    DllCall("ScreenToClient", "ptr", mainHwnd, "ptr", &pt)
    relX := NumGet(pt, 0, "int")
    relY := NumGet(pt, 4, "int")
    CaptureEvent("click", relX, relY)
    AppendLog("Captured click " relX "," relY)
}

QueueKeyEvent(keyName)
{
    CaptureEvent("key", keyName)
    AppendLog("Captured key " keyName)
}

CaptureEvent(eventType, param1 := "", param2 := "")
{
    global batchActive, batchEvents, batchStartTick
    now := A_TickCount
    if (!batchActive)
    {
        batchActive := True
        batchStartTick := now
        batchEvents := []
    }
    event := {"type": eventType, "param1": param1, "param2": param2, "offset": now - batchStartTick}
    batchEvents.Push(event)
    ResetBatchTimer()
}

ResetBatchTimer()
{
    global batchTimeoutMs
    SetTimer, FinalizeBatch, Off
    delay := batchTimeoutMs * -1
    SetTimer, FinalizeBatch, %delay%
}

FinalizeBatch:
    ProcessBatch()
return

ProcessBatch()
{
    global batchActive, batchEvents, nextGroupId, mirrorQueue, mirrorIntervalMs
    if (!batchActive)
        return
    if !(batchEvents.MaxIndex())
        return
    groupId := nextGroupId
    nextGroupId++
    dueTime := A_TickCount + mirrorIntervalMs
    for index, ev in batchEvents
    {
        event := {"group": groupId, "time": dueTime, "offset": ev.offset, "type": ev.type, "param1": ev.param1, "param2": ev.param2}
        mirrorQueue.Push(event)
    }
    UpdateQueueIndicator()
    AppendLog(Format("Queued batch (%d event(s)).", batchEvents.MaxIndex()))
    batchEvents := []
    batchActive := False
}

ResetBatchState()
{
    global batchActive, batchEvents
    SetTimer, FinalizeBatch, Off
    batchActive := False
    batchEvents := []
}

; =============================
; Mirror execution
; =============================

ExecuteMirrorGroup(events)
{
    global isMirroring
    if (!BeginMirrorSession())
    {
        AppendLog("Could not activate mirror window.")
        return
    }

    isMirroring := True
    prevOffset := 0
    for index, ev in events
    {
        delay := ev.offset - prevOffset
        if (delay > 0)
            Sleep, delay
        if (ev.type = "click")
            MirrorClickAction(ev.param1, ev.param2)
        else if (ev.type = "key")
            MirrorKeyAction(ev.param1)
        prevOffset := ev.offset
    }
    EndMirrorSession()
    isMirroring := False

    AppendLog(Format("Replayed %d event(s).", events.MaxIndex()))
}

BeginMirrorSession()
{
    global sessionHasFocus, sessionOrigX, sessionOrigY, targetHwnd
    if (sessionHasFocus)
        return True
    CoordMode, Mouse, Screen
    MouseGetPos, sessionOrigX, sessionOrigY
    WinActivate, ahk_id %targetHwnd%
    WinWaitActive, ahk_id %targetHwnd%,, 0.3
    if (ErrorLevel)
        return False
    sessionHasFocus := True
    Sleep, 50
    return True
}

EndMirrorSession()
{
    global sessionHasFocus, sessionOrigX, sessionOrigY, mainHwnd
    if (!sessionHasFocus)
        return
    WinActivate, ahk_id %mainHwnd%
    WinWaitActive, ahk_id %mainHwnd%,, 0.3
    DllCall("SetCursorPos", "int", sessionOrigX, "int", sessionOrigY)
    sessionHasFocus := False
}

MirrorClickAction(relX, relY)
{
    global targetHwnd
    VarSetCapacity(ptTarget, 8, 0)
    NumPut(relX, ptTarget, 0, "int")
    NumPut(relY, ptTarget, 4, "int")
    DllCall("ClientToScreen", "ptr", targetHwnd, "ptr", &ptTarget)
    targetX := NumGet(ptTarget, 0, "int")
    targetY := NumGet(ptTarget, 4, "int")
    DllCall("SetCursorPos", "int", targetX, "int", targetY)
    Sleep, 15
    Click, down
    Sleep, 15
    Click, up
    AppendLog("Mirrored click at " relX "," relY)
}

MirrorKeyAction(keyName)
{
    SendInput, {%keyName%}
    AppendLog("Mirrored key " keyName)
}

; =============================
; Helper functions
; =============================

ExtractHwnd(choice)
{
    local match, match1
    if (choice = "" || choice = "<no matching windows>")
        return ""
    RegExMatch(choice, "\[(0x[0-9A-Fa-f]+)\]", match)
    return match1
}

GetWindowLabel(hwnd)
{
    if (hwnd = "")
        return ""
    WinGetTitle, title, ahk_id %hwnd%
    if (title = "")
        return ""
    title := StrReplace(title, "|", "/")
    return Format("{1} [{2}]", title, Format("0x{:X}", hwnd))
}

UpdateQueueIndicator()
{
    pending := QueueCount()
    GuiControl,, QueueLine, %pending%
}

QueueCount()
{
    global mirrorQueue
    maxIdx := mirrorQueue.MaxIndex()
    if (!maxIdx)
        return 0
    return maxIdx
}

AppendLog(msg)
{
    global logMessages, maxLogEntries
    timestamp := SimpleFormatTime(A_Now, "HH:mm:ss")
    entry := "[" timestamp "] " msg
    logMessages.Push(entry)
    while (logMessages.MaxIndex() > maxLogEntries)
        logMessages.RemoveAt(1)
    text := ""
    for index, line in logMessages
        text .= (index = 1 ? "" : "`r`n") line
    GuiControl,, LogBox, %text%
}

SimpleFormatTime(timeValue, format)
{
    FormatTime, out, %timeValue%, %format%
    return out
}
