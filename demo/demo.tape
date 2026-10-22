# The README's GIF: `mise run demo` records it into docs/demo.gif.
#
# demo/sandbox.sh builds a throwaway world - two projects, four stand-in
# agents (demo/bin/claude) and a tmux server of its own with the plugin -
# so the recording shows no real project and costs no usage. Its feat/checkout
# agent finishes 14 seconds after the sandbox starts, which is during the
# recording.

Output docs/demo.gif

Set Shell bash
Set FontFamily "FiraCode Nerd Font Mono"
Set FontSize 15
Set Width 1280
Set Height 720
Set Padding 12
Set Theme "Catppuccin Mocha"
Set TypingSpeed 90ms
Set Framerate 20
Set CursorBlink false

Hide
Type "demo/sandbox.sh && clear && tmux -L agent-sidebar-demo attach -t shop"
Enter
Sleep 2s
Show

# An agent that finished, full screen.
Sleep 1.5s

# M-2 (typed as Escape 2, see sandbox.sh): every agent in every tmux
# session, by project, most urgent first.
Escape
Type@10ms "2"
Sleep 4.5s

# Jump to the blocked one, and let it make its edit.
Type "k"
Sleep 1.2s
Enter
Sleep 2.5s
Type "1"
Sleep 7s

# Back in the sidebar, a new worktree with an agent in it.
Ctrl+B
Left
Sleep 0.6s
Type "n"
Sleep 1.5s
Type "feat/search"
Sleep 0.6s
Enter
Sleep 6s

Hide
Ctrl+B
Type "d"
Type "demo/sandbox.sh clean"
Enter
