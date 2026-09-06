-- Neovim runs LuaJIT, which is Lua 5.1 plus `vim`.
std = "lua51"
globals = { "vim" }

-- Wrapping is stylua's job, and it wraps at 120.
max_line_length = false
