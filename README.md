# Llama Nvim

This is a simple Neovim streaming client for the `llama-server` example in
llama.cpp.

Install it in the way you prefer to install plugins. Use `:checkhealth` to
ensure the plugin and all dependencies are correctly installed.

The plugin depends on `curl` to connect to the server and stream results. If
`curl` is not available, the plugin will not work.

If you set it up with default settings, it should add the following commands
and keybinds:

```vim
" Start generating text from the current cursor position
:LlamaStart
" Stop generating text
:LlamaKill
" Check if the server is reachable and running
:LlamaHealth

" Keybinds
" Start generating text from the current cursor position
" (Or stop if generation is ongoing)
nmap gg :LlamaStart<CR> " This is just an example -- the call is lua-based
" Stop generating text
nmap G :LlamaKill<CR>
```

The plugin will not install anything, will not download anything, and will not
collect any data. It will only connect to the server you specify (default:
`http://localhost:8080`) and send the current buffer to it to generate text.

The plugin will not work if the server is not running or if the server is not
reachable. If you have any issues, check the error message first, the
`:LlamaHealth` second, then the `:checkhealth` output.
