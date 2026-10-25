-- moves through the file while the editor has the focus, the way holding a key does: a line forty times a second,
-- and every 2 seconds a jump to another part of the file. Stops once the file DEV_QUIET names is there
local step, focused, quiet = 0, true, os.getenv("DEV_QUIET")
vim.api.nvim_create_autocmd("FocusGained", { callback = function() focused = true end })
vim.api.nvim_create_autocmd("FocusLost", { callback = function() focused = false end })
vim.uv.new_timer():start(1000, 25, vim.schedule_wrap(function()
    if not focused or (quiet and vim.uv.fs_stat(quiet)) then
        return
    end
    step = step + 1
    if step % 80 == 0 then
        vim.cmd("normal! " .. (step * 7919 % vim.fn.line("$") + 1) .. "Gzz")
    else
        vim.cmd("normal! \5")
    end
end))
