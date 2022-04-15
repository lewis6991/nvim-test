### ARCHIVED: Please use https://github.com/neovim/nvimdev.nvim instead.

#Run Neovim tests inside Neovim

<video src="https://user-images.githubusercontent.com/7904185/154276858-f72d92b8-c7d9-4716-9516-7814f81d0304.mp4" width="100%" autoplay muted></video>
      
* Add virtual text for test results
* Add virtual lines for failed test output immediately above the test.

## Requirements

plenary.nvim

## Commands

`RunTest [all]`: Run the test in the buffer the cursor is inside. Works for `it` and `describe` blocks.

`RunTestClear`: Clear test result decorations in buffer

## TODO

* Generalise for any busted testsuite
