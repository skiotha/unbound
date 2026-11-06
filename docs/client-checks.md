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

## 8. Many full-length chunks from one key press

Unbound's plan is to send every chunk of a message on the same Enter. This checks
whether the server takes several 255-byte messages in a row without dropping or
reordering them. Party and whisper can also be sent from a timer, so Unbound can space
those out; this check is about say and emote. It posts long filler text, so pick a
quiet spot.

1. `/reload`, then start the watcher, once. For each of your own test messages it prints
   the chat type, the chunk number, its length in bytes and the time it came back:

   ```
   /run local f=CreateFrame"Frame"f:RegisterEvent"CHAT_MSG_SAY"f:RegisterEvent"CHAT_MSG_EMOTE"f:SetScript("OnEvent",function(_,e,t)local i=t:match"^ub(%d+)/"if i then print(e:sub(10),i,#t,GetTime())end end)
   ```

2. Six chunks in Say, each 255 bytes and numbered (`ub1/6`, `ub2/6`, …):

   ```
   /run local n,c=6,"SAY"for i=1,n do C_ChatInfo.SendChatMessage(("ub"..i.."/"..n.." "..("lorem ipsum dolor "):rep(15)):sub(1,255),c)end
   ```

   Do all six appear in chat, in order? Does the watcher print 1 to 6, each `255`? Note
   any system message or red error text, and how far apart the times are.

3. Wait about a minute, then the same line with `n,c=10,"SAY"`.
4. Wait again, then repeat 2–3 with `"EMOTE"` in place of `"SAY"`.
5. Optional, only if both runs of 10 arrived complete: wait, then `n,c=15,"SAY"`, to see
   where the limit is. Stop at the first run that loses or reorders a message.

Answers: how many full-length chunks one Enter can send in say and emote, and whether
the server slows them down.

## 9. How fast the chat limit recovers

In check 8, 15 of 20 say messages from one key press arrived. The server refused the
other five: "The number of messages that can be sent is limited, please wait to send
another message." This check measures that limit:

- how many messages it allows after a rest, and how fast it recovers;
- whether refused messages count against you;
- which chat types share it, and whether it counts messages or bytes.

Unbound needs these numbers to cap how many chunks one Enter sends, and to tell you how
long to wait for the rest. The check posts a lot of filler text in say and emote, so
pick a quiet spot and stay out of a group. If the server says you're silenced or
disconnects you, stop there.

**Rest** means sending no chat at all, typed or from code, for 3 minutes; after a burst,
the clock below shows it as `ub +180 s`. `/run`, `/dump` and other slash commands don't
count: they never reach the server. If step 4 shows the limit takes longer than 3
minutes to recover, rest that long instead.

1. `/dump ERR_CHAT_THROTTLED`. Does it print the limit message? `nil` means Forever
   names it differently.
2. `/reload` (it stops the watcher from check 8), then paste these five lines, in order.
   They're separate from Unbound. Paste them once per session, and again after any
   `/reload`; pasted twice in one session, the watcher counts everything twice.

   A watcher that counts your test messages as they come back, and the limit messages:

   ```
   /run local u={p=0,d=0}UBT=u u.w=NameUtil.GetUnmodifiedUnitFullName"player"u.f=CreateFrame"Frame"u.f:SetScript("OnEvent",function(_,e,m)if m:find"^ub%d+/"then u.p=u.p+1 elseif m:find"is limited"then u.d=u.d+1 u.e=e end end)
   ```

   The chat events it listens to, and the test message (numbered, then filler):

   ```
   /run local u=UBT for e in("SAY EMOTE WHISPER_INFORM SYSTEM"):gmatch"%S+"do u.f:RegisterEvent("CHAT_MSG_"..e)end u.m=function(i,n,L)return(("ub%d/%d"):format(i,n)..(" lorem ipsum dolor"):rep(15*L)):sub(1,255)end
   ```

   The sender:

   ```
   /run local u=UBT u.go=function(n,L,a,b)local t=GetTime()u.g=u.t and floor(t-u.t+.5).." s"or"-"u.t,u.p,u.d,u.e=t,0,0 for i=1,n do local c=b and i>n/2 and b or a C_ChatInfo.SendChatMessage(u.m(i,n,L),c,nil,c=="WHISPER"and u.w or nil)end u.r(n,a,b,t)end
   ```

   The summary, and a clock that counts from the last burst:

   ```
   /run local u=UBT u.r=function(n,a,b,t)C_Timer.After(3,function()if u.t~=t then return end print(("ub %d %s%s: %d ok, %d limited, gap %s %s"):format(n,a,b and"+"..b or"",u.p,u.d,u.g,u.e or""))end)u.k(t)end
   ```

   ```
   /run local u=UBT u.k=function(t)for _,s in ipairs{5,10,20,30,60,90,120,180}do C_Timer.After(s,function()if u.t==t then print("ub +"..s.." s")end end)end end
   ```

   From then on, `/run UBT.go(20,1,"SAY")` sends 20 numbered messages (`ub1/20`,
   `ub2/20`, …) on one key press. The second number sets the length: `1` for 255 bytes,
   `0` for the number alone. A second chat type splits the burst in half:
   `/run UBT.go(20,1,"SAY","EMOTE")` sends 10 says, then 10 emotes. Whispers go to
   yourself.

   Three seconds after each burst a snapshot appears, for example
   `ub 20 SAY: 15 ok, 5 limited, gap 12 s CHAT_MSG_SYSTEM`:
   - **ok**: messages that came back;
   - **limited**: limit messages. If ok and limited don't add up to the number sent,
     messages may still be pending or an outcome may be missing; don't assume refusal.
   - **gap**: time since the previous burst (`-` for the first);
   - the last word: the event that carried the limit message.

   Then the clock prints `ub +5 s`, `ub +10 s`, … up to `ub +180 s`. A new burst restarts
   it and suppresses an older scheduled snapshot. Don't start another burst while
   messages remain unaccounted for: delayed events could be counted against the new
   burst. Check 10 provides a manual snapshot for following delayed outcomes.

3. After a rest: `/run UBT.go(20,1,"SAY")`. Is it 15 ok again? If all 20 arrived, rest
   and send 30 instead.
4. Recovery. Don't rest after 3. When the clock shows `ub +10 s`, send
   `/run UBT.go(20,1,"SAY")` again. Send the same line at the next `ub +30 s`, then
   `ub +60 s`, then `ub +120 s`. If the last one still got fewer through than step 3,
   send it once more at `ub +180 s`.
5. Do refused messages count? Rest, then send exactly as many as got through in step 3,
   for example `/run UBT.go(15,1,"SAY")`. All should arrive, none limited. At
   `ub +10 s`, send `/run UBT.go(20,1,"SAY")`. Step 4's first burst had the same gap
   but came after refused messages. Compare the two.
6. Say and emote together. Rest, then `/run UBT.go(20,1,"SAY","EMOTE")`. 15 ok in total
   means they share one limit; 20 means each has its own.
7. Short messages. Rest, then `/run UBT.go(20,0,"SAY")`. 15 ok means the limit counts
   messages, whatever their length. If all 20 arrived, rest and send 40.
8. Optional, whispers. Rest, then `/run UBT.go(20,1,"SAY","WHISPER")`: 10 says, then 10
   whispers to yourself. Compare completed outcomes with say alone; neither 15 nor 20
   arrivals by itself establishes how the limits interact over time.

Answers: how many messages Unbound may send at once, how long the rest has to wait, and
whether Unbound can work out that wait from the messages it sees.

## 10. Say recovery and whisper limit

This round checks say recovery and whisper throttling. It does not need a group.
Results are recorded in [forever-api.md](forever-api.md#sending-chat). Party-chat testing
is deferred until a group is available.

**Helper correction:** the original immediate totals ran before chat events arrived.
Those `0 ok, 0 limited` lines are not results. The helpers below now announce submission
and report outcomes only when requested. A snapshot can still be incomplete.

Use the `UBT` setup from 9.2. If you have reloaded since then, paste its five setup
lines again. Then paste these three overrides. The first records the burst size and
type, announces submission and starts the clock; it does not claim delivery:

```
/run local u=UBT u.r=function(n,a,b,t)u.n=n u.a=a u.b=b print("ub",n,a,b or"","submitted; gap",u.g)u.k(t)end
```

The manual snapshot, including elapsed time and unaccounted messages:

```
/run local u=UBT u.report=function()print(("ub +%.1f s %s%s: %d ok, %d limited, %d unaccounted %s"):format(GetTime()-u.t,u.a,u.b and"+"..u.b or"",u.p,u.d,u.n-u.p-u.d,u.e or""))end
```

The clock prints through `ub +11 s`:

```
/run local u=UBT u.k=function(t)for s=1,11 do C_Timer.After(s,function()if u.t==t then print("ub +"..s.." s")end end)end end
```

### Say recovery

For each trial, rest for 30 seconds with no chat, then send 15 says as a baseline.
Confirm all 15 numbered echoes arrive before the trial's target. If they don't, stop
that trial rather than overlap unresolved bursts. At the target, send 15 more says.
Use a separate rested trial for each target: `+2 s`, `+5 s`, `+8 s`, and `+10 s`.

For example:

```
/run UBT.go(15,0,"SAY")
```

Then at `ub +2 s`:

```
/run UBT.go(15,0,"SAY")
```

After the echoes or limit messages appear, take a snapshot:

```
/run UBT.report()
```

Repeat from a fresh 30-second rest for the other targets, only once the previous burst
is accounted for. `/run` itself does not count as chat. Note the reported gap and any
delay before you could press Enter: the timing is approximate. Stop if the client
reports an error or unexpected delayed messages; keep the screenshots.

### Self-whisper limit

After another 30-second rest, send 20 short whispers to yourself:

```
/run UBT.go(20,0,"WHISPER")
```

Take snapshots at roughly 3, 12 and 30 seconds, without sending another burst:

```
/run UBT.report()
```

`unaccounted` means neither an outgoing echo nor a refusal has been counted yet.
Don't resend that text: it might still arrive. Each self-whisper shows both received
and sent lines, but the watcher counts only the outgoing echo. Save the numbered
messages, snapshot lines and any throttle messages. If all 20 are accounted for, no
later snapshot is needed. If any remain unaccounted for at 30 s, report that rather
than treating them as refused. Do not escalate to a larger burst.

### Deferred: party chat

TODO: when a group is available, prepare a party-aware watcher and test party pacing
and its interaction with say/emote. The current watcher does not register party echo
events. No group testing is needed for round 10.

Answers: recovery at the sampled SAY intervals, and the observed delivery and refusal
timing of one self-whisper burst. These checks do not prove an exact reset mechanism
or which component delays whispers.

## 11. Sending from the pre-send event

Stage 0.3 sends every chunk from inside Blizzard's pre-send event (check 5), on the
Enter that sends the post. Then it empties the box, so Blizzard sends nothing. A post
that isn't sent in full goes into the chat box history, and Alt+Up brings it back.
This check tests those steps outdoors before any code relies on them. Pick a quiet
spot, and `/reload` first so a block would be recorded.

1. Register the test. Any message starting with `ubh` is sent three times from the
   event (`ubh 1`, `ubh 2`, `ubh 3`), in the box's chat type and language. Then the box
   is emptied:

   ```
   /run EventRegistry:RegisterCallback("ChatFrame.OnEditBoxPreSendText",function(_,e)local t=e:GetText()if t:find"^ubh"then for i=1,3 do C_ChatInfo.SendChatMessage(t.." "..i,e:GetChatType(),e.languageID)end e:SetText""end end,"UBTEST")
   ```

2. `/s ubh`. Do `ubh 1`, `ubh 2` and `ubh 3` arrive, in order, and nothing else (no
   plain `ubh`)? Any error or "Interface action failed"? Then `/reload`, register again
   and send `/e ubh`.
3. Language. Pick your other language in the chat box's language menu, then `/s ubh`.
   Do all three show that language? Switch back afterwards.
4. History. Open the box and press Alt+Up. Expect the `/run` line from step 1, not
   `/s ubh`: an emptied box adds nothing to the history. Press Escape.
5. Remove the test (or `/reload`):

   ```
   /run EventRegistry:UnregisterCallback("ChatFrame.OnEditBoxPreSendText","UBTEST")
   ```

6. A long post in the history. Lift the limits as in 2.2, then add a say of about 730
   characters to the history. The line is added one frame later, from a timer. Added
   straight from `/run`, it would sit behind the `/run` line, because Blizzard adds a
   typed command to the history after running it (that's how the first round of this
   step went wrong).

   ```
   /run local e=ChatFrame1EditBox e:SetMaxBytes(0)e:SetMaxLetters(0)e:SetVisibleTextByteLimit(0)
   ```

   ```
   /run C_Timer.After(0,function()ChatFrame1EditBox:AddHistoryLine("/s ub kept "..("lorem ipsum dolor "):rep(40))end)
   ```

   Open the box and press Alt+Up once. Is the box in Say mode, with the text starting
   `ub kept` and ending in `dolor`? **Press Escape; don't send.** Repeat with `/e` in
   place of `/s`: does the box switch to Emote? Then `/reload`, which restores the
   limits, and lift them again with the first line. Press Alt+Up a few times (the lift
   line and `/reload` come first, if the history survived): does the `/e ub kept` line
   come back, whole? Escape again.

Answers: whether one Enter can send every chunk from the pre-send event, and whether
the history can keep a post Unbound didn't send, and for how long. If step 2 is
blocked, 0.3 falls back to one chunk per Enter.

## 12. Long say and emote

The gate for stage 0.3: Unbound 0.3.0 sends a long say or emote on one Enter,
outdoors. Play as usual: Total RP 3 loaded, BugSack on, `taintLog` on (see "Before you
start"). Pick a quiet spot outdoors, out of combat. Wait about 15 s between posts: say
and emote share a limit of 15 messages in about 12 s, and the posts below add up.

The posts come from this line. It builds `n` numbered pieces of exactly 255 bytes
(`ub1/5 lorem ipsum …`), so the post splits into exactly `n` messages. A second later
it opens the chat box with the post. `c` is the chat command in front of it:

```
/run local n,c=2,"/s "local t={}for i=1,n do t[i]=("ub"..i.."/"..n.." "..("lorem ipsum dolor "):rep(15)):sub(1,255)end C_Timer.After(1,function()ChatFrameUtil.OpenChat(c..table.concat(t," "))end)
```

To change the post, edit only the values after `local n,c=`. `n=5` means
`local n,c=5,"/s "`, and `c="/e "` means `local n,c=2,"/e "`. Keep the comma and the
quotes.

1. `/reload`. `/ub` shows `v0.3.0`. Start the watcher from 8.1: it prints the chat type,
   the piece number and the bytes of every `ub…` message that comes back. Then open the
   box and `/dump` its limits with the line from 2.1: expect `0`, `0`, `0`.
2. Say. Run the line above (`n,c=2,"/s "`). The box opens in Say mode with the post.
   Press Enter. Do `ub1/2` and `ub2/2` arrive, in order? Does the watcher print `SAY`,
   `1`, `255` and then `2`? Unbound itself prints nothing. Open the box and press Alt+Up:
   is the post back, in Say mode? Press Escape. Then the same with `n=5` and `n=8` (the
   cap, 2,047 bytes).
3. Emote. The same with `c="/e "`: `n=2`, `5` and `8`. How do the emotes read with
   your name before each piece? Good enough for roleplay?
4. Language. Pick your other language in the box's language menu, then a say with
   `n=2`. Do both pieces show that language? Switch back afterwards.
5. Typographic characters and links. This opens a say of about 400 bytes with em
   dashes, curly quotes and ellipses:

   ```
   /run C_Timer.After(1,function()ChatFrameUtil.OpenChat("/s "..("ub \226\128\148 \226\128\156typographic\226\128\157 lorem\226\128\166 "):rep(12))end)
   ```

   The links come from your bags. **Open your bags first** (the bag button, or B
   before you open the chat box: with the box open, B types a letter). Then run the
   line. When the box opens with the post, hold Shift and click an item in your bags,
   such as your Hearthstone: its link appears in the text where the cursor is (at the
   end). Click inside the text to move the cursor, then Shift-click another item. Two
   or three links in different places, then Enter. Do the dashes, quotes and ellipses
   arrive intact? Are the links whole, coloured and clickable? Any error?

6. Over the cap: `n=9` (2,303 bytes). Press Enter. Nothing is sent, and Unbound says
   the post needs 9 messages. Open the box and press Alt+Up, then Enter: does Unbound
   say 9 again? If it sends anything, the history cut the line at 1,280 bytes.
7. A refusal. Run this line **once**, after a 15 s rest. It sends 14 short says
   (`ub fill 1` to `14`), and a second later opens the box with a 3-piece say. It
   replaces the post line for this step:

   ```
   /run for i=1,14 do C_ChatInfo.SendChatMessage("ub fill "..i,"SAY")end local t={}for i=1,3 do t[i]=("ub"..i.."/3 "..("lorem ipsum dolor "):rep(15)):sub(1,255)end C_Timer.After(1,function()ChatFrameUtil.OpenChat("/s "..table.concat(t," "))end)
   ```

   Press Enter as soon as the box opens. 14 + 3 is over 15, so expect `ub1/3` to arrive
   and two yellow system lines. About 3 s later, does Unbound say `The server refused 2
of 3 messages`? Does the watcher print only piece `1`? Alt+Up brings the whole post
   back. Escape.

   If Unbound says nothing, wait 15 s and run this probe. It sends 17 says and prints
   one line per system message: `during` or `after` the sends, whether the text
   equals `ERR_CHAT_THROTTLED`, and both lengths in bytes. `/reload` afterwards to
   remove it.

   ```
   /run local f,s=CreateFrame"Frame",1 f:RegisterEvent"CHAT_MSG_SYSTEM"f:SetScript("OnEvent",function(_,_,m)print(s and"during"or"after",m==ERR_CHAT_THROTTLED,#m,#ERR_CHAT_THROTTLED)end)for i=1,17 do C_ChatInfo.SendChatMessage("ub p"..i,"SAY")end s=nil
   ```

8. Other chat types. Whisper yourself: the post line with `n,c=2,"/w First Surname "`
   (your full name). Press Enter: nothing is sent, Unbound says long text is only split
   in say and emote, and there's no Lua error. Alt+Up: does it come back whole, as a
   whisper to you? Escape. If you're in a group, the same with `c="/p "`.
9. Everyday chat. `/s ub short` arrives as usual. Open the box and press Enter on
   nothing. `/ub`, and a mistyped command such as `/ubx`. Then `/reload` and post
   `n=2` in say once more. No errors anywhere.
10. Optional, other windows. If whispers open in their own chat window, click into
    its box and paste about 600 characters. Does it take all of them? Escape.
11. Optional, combat. During a fight with a low-level mob, post `n=2` in say. Does it
    arrive, or is it blocked ("Interface action failed", an error)? Either way, Alt+Up
    has the post.
12. Optional, a dungeon, out of combat. Open the box and `/dump` its limits: expect
    `1280`, `0`, `255`. Unbound stays off there: `/s ub short` goes out as usual.

Check BugSack. Then quit the game: the client writes `_forever_\Logs\taint.log` at
logout. Search it for `Unbound`. If there's no file, nothing was logged: level 1
records only blocked actions.

Answers: whether 0.3 passes its gate, whether the history keeps a line over 1,280
bytes, and whether Unbound can send in combat outdoors.

## Afterwards

- Note the client build from `/dump GetBuildInfo()` next to the results.
- Quit the game, which writes `taint.log` and BugGrabber's file to disk. `taintLog`
  isn't saved, so it's off next time. To keep playing instead: `/console taintLog 0`,
  then `/reload`.
