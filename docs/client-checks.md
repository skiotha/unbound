# In-game checks

> Manual checks for the Forever client. They confirm the facts marked **verify** in
> [forever-api.md](forever-api.md) and test what Unbound will rely on. Run them once the
> client is playable, and again after a Forever patch. Results go into forever-api.md;
> this file only holds the steps.

## Before you start

- Type or paste each line into the chat box and press Enter. Every line fits the
  255-byte chat limit.
- If the client asks whether to allow scripts, allow it.
- Show Lua errors on screen: `/console scriptErrors 1`.
- Log taint to `_forever_\Logs\taint.log`: `/console taintLog 1`. If
  `/dump GetCVar("taintLog")` prints `nil`, the setting no longer exists; skip it. It
  isn't saved, so set it again after every restart.
- Optional: BugGrabber + BugSack. They keep every error in their SavedVariables, which
  can be read from disk after you log out. BugGrabber shows only the **first** blocked
  action per session, so `/reload` before each check that might be blocked.
- Screenshots (Print Screen) land in `_forever_\Screenshots\`. That's the easiest way
  to hand over `/dump` output.
- Some checks post to `/say`, `/emote` or `/party`; use a quiet spot. Whispers go to
  yourself, by full name: Forever names have two parts, so type `/w First Surname`.
  The `/run` lines use `NameUtil.GetUnmodifiedUnitFullName("player")`.

## 1. Client and loading

1. `/dump GetBuildInfo()`: version `1.60.x`. The 4th value is the interface number,
   expected `16001`.
2. `/dump _VERSION`: `"Lua 5.1"`.
3. `/ub`: Unbound prints its help. The AddOns list doesn't mark it out of date.
4. SavedVariables survive a reload and a restart:
   - `/run UnboundDB.probe=date("%H:%M:%S")`, `/reload`, then `/dump UnboundDB.probe`
     shows the same time.
   - Quit the game, start it again: `/dump UnboundDB.probe` still shows that time.
   - Clean up: `/run UnboundDB.probe=nil`.

## 2. Chat box limits

1. Current limits. Blizzard's XML says 1280 bytes in total, 255 of them visible:

   ```
   /dump ChatFrame1EditBox:GetMaxBytes(),ChatFrame1EditBox:GetMaxLetters(),ChatFrame1EditBox:GetVisibleTextByteLimit()
   ```

2. Lift the limits, then paste about 600 characters into the chat box. Does it take all
   of them? **Press Escape; don't send.** `/reload` restores the limits.

   ```
   /run local e=ChatFrame1EditBox e:SetMaxBytes(0)e:SetMaxLetters(0)e:SetVisibleTextByteLimit(0)
   ```

3. Message limit: bytes or characters? Each line says one message straight from your
   key press. Note what happens: the message in chat, or the error
   `Chat message limits exceeded`.
   - 255 × `x` (255 bytes), then the same with `256`:

     ```
     /run C_ChatInfo.SendChatMessage(("x"):rep(255),"SAY")
     ```

   - 85 em dashes (255 bytes), then the same with `86` (258 bytes, but only 86
     characters). If 86 arrives, the limit counts characters, not bytes.

     ```
     /run C_ChatInfo.SendChatMessage(("\226\128\148"):rep(85),"SAY")
     ```

## 3. Sending from code, without a key press

Each line sends one second later from a timer, so no key press is involved.

1. Whisper to yourself. First check your full name as the client builds it:
   `/dump NameUtil.GetUnmodifiedUnitFullName("player")`. Note the character between the
   two names. Then, does this arrive?

   ```
   /run local t=NameUtil.GetUnmodifiedUnitFullName("player")C_Timer.After(1,function()C_ChatInfo.SendChatMessage("ub timer","WHISPER",nil,t)end)
   ```

2. Emote. Does it arrive?

   ```
   /run C_Timer.After(1,function()C_ChatInfo.SendChatMessage("ub timer","EMOTE")end)
   ```

3. Say, outdoors. Expected to be blocked. Note what happens: nothing, an error, or a
   message in chat.

   ```
   /run C_Timer.After(1,function()C_ChatInfo.SendChatMessage("ub timer","SAY")end)
   ```

4. Party, in a group. Does it arrive?

   ```
   /run C_Timer.After(1,function()C_ChatInfo.SendChatMessage("ub timer","PARTY")end)
   ```

5. One emote straight from your key press, no timer. `/reload` first. Does it arrive?

   ```
   /run C_ChatInfo.SendChatMessage("ub key","EMOTE")
   ```

6. Several messages from one key press, outdoors. Do all three arrive, in order? Then
   `/reload` and repeat with `"EMOTE"` in place of `"SAY"`.

   ```
   /run for i=1,3 do C_ChatInfo.SendChatMessage("ub multi "..i,"SAY")end
   ```

7. Repeat 1–4 inside a dungeon, out of combat.

Answers: which chat types Unbound can send automatically, and whether one key press can
send several chunks.

## 4. Echo of your own messages

1. Start a watcher; it runs until `/reload`. It prints the event and the text, or
   `SECRET` when the text is hidden from addons:

   ```
   /run local f=CreateFrame"Frame"for _,e in ipairs{"SAY","EMOTE","PARTY","PARTY_LEADER","WHISPER_INFORM"}do f:RegisterEvent("CHAT_MSG_"..e)end f:SetScript("OnEvent",function(_,e,t)print(e,issecretvalue(t)and"SECRET"or t)end)
   ```

2. Send a `/s`, `/e`, `/p` and a whisper to yourself by hand. Expect one printed line
   per message, showing your text.
3. Repeat in a dungeon out of combat and, if convenient, during a boss fight.

Answers: whether Unbound can see that a chunk arrived before sending the next one, and
where secret values start.

## 5. Blizzard's pre-send hook

Blizzard's chat box fires `ChatFrame.OnEditBoxPreSendText` just before it sends, so
addons can edit the text. This test adds ` [ub]` to every message you type.

1. Register the test:

   ```
   /run EventRegistry:RegisterCallback("ChatFrame.OnEditBoxPreSendText",function(_,e)local t=e:GetText()if t:find("%S")then e:SetText(t.." [ub]")end end,"UBTEST")
   ```

2. Whisper yourself: `/w First Surname hello`. It arrives as `hello [ub]`.
3. `/e`, `/s` outdoors, `/p` in a group: each gets ` [ub]`, with no error and no
   "Interface action failed" message. `/reload` and register again before `/e`, so a
   block would be recorded.
4. Repeat 2–3 in a dungeon out of combat and, if convenient, during a boss fight.
5. Remove the test (or `/reload`):

   ```
   /run EventRegistry:UnregisterCallback("ChatFrame.OnEditBoxPreSendText","UBTEST")
   ```

Answers: whether Unbound can work inside Blizzard's own chat box without the taint that
broke UnlimitedChatMessage (see forever-api.md → Prior art).

## 6. Chat lockdown

1. `/dump IsInInstance(),C_ChatInfo.InChatMessagingLockdown()` in the open world, in a
   dungeon out of combat and during a boss fight.

Answers: where Unbound has to step aside.

## 7. Reopening the chat box from code

If each chunk needs its own Enter, Unbound would put the next chunk back into the chat
box after each send. This checks whether that works and whether it harms later sends.
`/reload` before each step.

1. Say mode. Send any `/s` by hand first, so the box is in Say mode. Then:

   ```
   /run C_Timer.After(1,function()ChatFrameUtil.OpenChat("ub reopened")end)
   ```

   The box opens in Say mode with `ub reopened`. Press Enter: does it arrive, with no
   error?
2. Emote mode. The box doesn't stay in Emote mode after a send, so the text starts with
   `/e`:

   ```
   /run C_Timer.After(1,function()ChatFrameUtil.OpenChat("/e ub reopened")end)
   ```

   Does the box switch to Emote with `ub reopened`? Press Enter: does it arrive, or is
   it blocked?
3. Right after 2, without a reload: type `/e ub after` and send it, then `/s ub after`.
   Both should arrive with no error. A block here means reopening left taint in the chat
   box.

Answers: whether Unbound can hand you the next chunk in the chat box, and for which chat
types.

## Afterwards

- `/console taintLog 0`, then `/reload`.
- Note the client build from `/dump GetBuildInfo()` next to the results.
