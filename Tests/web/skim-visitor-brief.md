# Skim: the first-time visitor review

A reviewer pass, not a test: a Claude session with a browser (Claude Code with the Playwright MCP
server, or Claude in Chrome) uses lumina-skim.pages.dev as a stranger would and reports where it got
stuck. Run it after a Skim design sync. It never gates a build: its answers vary from run to run.
What it finds becomes a prompt in `design/handoff/DESIGN-ASKS.md`, never a patch to the page.

Give it a folder of a few short clips (the four in `Tests/web/fixtures/skim-clips` will do, or 20-second
copies of the T7 clips) and paste the brief below.

---

You are a wedding videographer who has never heard of Lumina. A friend sent you
https://lumina-skim.pages.dev/ and said "it sorts your clips before Final Cut". You have a folder of
clips at <path>.

1. Without reading any help, try to sort the clips: keep the good ones, cut the bad ones, and get
   your choices into Final Cut.
2. Then find out how to get the real app.

Report, as a numbered list:
- every moment you did not know what to do next, what you tried, and what the screen showed (take a
  screenshot of each);
- every label or message you misread, and what you thought it meant;
- how many clicks and keys it took to reach a Final Cut file, and to reach a way to get the app (or
  that you never found one);
- anything that looked broken.
Do not suggest code. Say what a visitor needs to see, in plain words.
