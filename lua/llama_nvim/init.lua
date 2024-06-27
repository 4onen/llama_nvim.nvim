local M = {}

M.DEFAULTS = {
    commands = {
        start = "LlamaStart",
        kill = "LlamaKill",
        health = "LlamaHealth",
    },
    keymaps = {
        start = "gg", -- Doubles as kill if a job is running, think "toggle"
        kill = "G",
    },
    server = {
        host = "http://localhost",
        port = 8080,
    },
    is_setup = true, -- Don't change this
}

-- Metatable config setup thanks to
-- https://hiphish.github.io/blog/2022/03/15/lua-metatables-for-neovim-plugin-settings/
local config = {
    is_setup = false,
}

local construct_url = function(endpoint)
    return config.server.host .. ':' .. config.server.port .. '/' .. endpoint
end

local insert_text = function (text, win)
    -- Insert text at the current cursor position in a given window
    if not win then
        -- Error if no window is provided
        error("No window provided")
    end
    local buf = vim.api.nvim_win_get_buf(win)
    local row, pos = unpack(vim.api.nvim_win_get_cursor(win))
    pos = pos + 1

    local line = vim.api.nvim_buf_get_lines(buf, row-1, row, strict_indexing)[1]
    local after_insert_point = line:sub(pos+1)
    local nline = line:sub(0, pos) .. text .. after_insert_point
    local result = vim.split(nline, "\n", {plain=true})
    vim.api.nvim_buf_set_lines(buf, row-1, row, strict_indexing, result)
    local final_line = row + #result - 1
    local final_line_pos = result[#result]:len() - after_insert_point:len() - 1
    if final_line_pos < 0 then
        print("final_line_pos is negative: ", final_line_pos, "setting to 0")
        final_line_pos = 0
    end
    vim.api.nvim_win_set_cursor(win, {final_line, final_line_pos})
end

local current_jobs = {}

local wrapped_err_writeln = vim.schedule_wrap(vim.api.nvim_err_writeln)

local on_exit = function (win, res)
    current_jobs[win].finished = true
    if res.code == 0 then
        vim.print("Process exited successfully")
    else
        local userfriendly_error = ""
        if res.code == 7 then
            -- This is the code for when the server refuses to connect.
            userfriendly_error = string.format("cURL reports that the server %s refused to connect. Is it running?", construct_url(''))
        elseif res.code == 22 then
            userfriendly_error = stirng.format("cURL reports that the server %s returned an error code. Is this the right server?", construct_url(''))
        end
        local full_err = string.format(
            "%s\nFull stderr for process exit code %d:\n%s",
            userfriendly_error,
            res.code,
            res.stderr
        )
        wrapped_err_writeln(full_err)
    end
end

-- Function to kill the current job
M.kill = function(win, signal)
    if not signal then
        signal = 'sigterm'
    end
    if current_jobs[win] then
        current_jobs[win]:kill('sigterm')
    end
end

local process_line = function(win, line)
    -- Each event is JSON, so remove the "data: " prefix and parse it.
    local data = vim.fn.json_decode(line:sub(6))
    if data and data.content then
        -- Insert the completion text.
        insert_text(data.content, win)
    end
end

local process_lines = function(win)
    local data_so_far = current_jobs[win].data_so_far
    -- We're reading a SSE stream, so split on double newlines.
    local lines = vim.split(data_so_far, "\n\n", true)
    -- The last line may be incomplete, so keep it for next time.
    current_jobs[win].data_so_far = lines[#lines]
    -- Process all but the last line.
    for i = 1, #lines - 1 do
        process_line(win, lines[i])
    end
end

local on_stdout = function(win, err, data)
    if err then
        error(err)
    elseif data then
        local data_so_far = current_jobs[win].data_so_far or ""
        current_jobs[win].data_so_far = data_so_far .. data
        current_jobs[win].process_lines(win)
    end
end

local completion_curl_cmd = function(body)
    return {
        'curl',
        '--request',
        'POST',
        '--silent',
        '--fail',
        '--show-error',
        '--no-buffer',
        '--url',
        construct_url('completions'),
        '--header',
        'Content-Type: application/json',
        '--header',
        'Accept: text/event-stream',
        '--data-raw',
        vim.fn.json_encode(body)
    }
end

local get_window_generation_context = function(win)
    -- The context for the language model is all lines
    -- in the file up to the current cursor position.
    -- This includes text on the current line, but not
    -- after the cursor.
    local buf = vim.api.nvim_win_get_buf(win)
    local row, pos = unpack(vim.api.nvim_win_get_cursor(win))
    local lines = vim.api.nvim_buf_get_lines(buf, 0, row, strict_indexing)
    -- Now we take out the last line, trim it to the cursor position,
    -- then join all the lines together.
    lines[#lines] = lines[#lines]:sub(1, pos)
    return table.concat(lines, "\n")
end

M.start = function(win)
    local prompt = get_window_generation_context(win)
    local curl_body = { prompt = prompt, n_predict = 128, stream = true, cache_prompt = true }
    local res = vim.system(
        completion_curl_cmd(curl_body),
        {
            stdout = function(data, err) on_stdout(win,data,err) end,
            text = true,
        },
        function(res) on_exit(win, res) end
    )
    res.data_so_far = ""
    res.finished = false
    res.process_lines = vim.schedule_wrap(process_lines)
    current_jobs[win] = res
    return res
end

M.health = function()
    -- Ping the /health endpoint to check if the server is running.
    local url = construct_url('health')
    local res = vim.system({'curl','--silent','--show-error','--fail-with-body','--url',url}, {text=true}):wait()
    if res.code == 0 then
        return "Server is running: " .. res.stdout
    else
        return "Server is not running: " .. res.stderr
    end
end

M.setup = function(opts)
    if config.is_setup then
        error("Llama_nvim has already been set up. Reinitializing is not supported.")
    end

    config = vim.tbl_deep_extend('force', config, M.DEFAULTS, opts or {})

    local parse_window_number_or_give_current = function(maybe_win)
        if maybe_win then
            local win = tonumber(maybe_win)
            if not win then
                error("Invalid window number")
            end
            return win
        else
            return vim.api.nvim_get_current_win()
        end
    end

    local start_job_impl = function(args)
        local args = args or {}
        local win = parse_window_number_or_give_current(args[1])
        M.start(win)
    end
    local kill_job_impl = function(args)
        local args = args or {}
        local win = parse_window_number_or_give_current(args[1])
        M.kill(win)
    end
    local toggle_job_impl = function(args)
        local args = args or {}
        local win = parse_window_number_or_give_current(args[1])
        if current_jobs[win] and not current_jobs[win].finished then
            M.kill(win)
        else
            M.start(win)
        end
    end

    if type(config.commands) == 'table' then
        if config.commands.start then
            vim.api.nvim_create_user_command(config.commands.start, start_job_impl, { nargs = "?" })
        end
        if config.commands.kill then
            vim.api.nvim_create_user_command(config.commands.kill, kill_job_impl, { nargs = "?" })
        end
        if config.commands.health then
            vim.api.nvim_create_user_command(config.commands.health, function ()
                print(M.health())
            end, { nargs = 0 })
        end
    end

    if config.keymaps then
        if config.keymaps.start then
            -- Start job doubles as kill job if job is running
            vim.keymap.set('n', config.keymaps.start, toggle_job_impl, { silent = true, unique = true })
        end
        if config.keymaps.kill then
            -- Kill job
            vim.keymap.set('n', config.keymaps.kill, kill_job_impl, { silent = true, unique = true })
        end
    end

    return M
end

local config_copy_view_metatable = {
    __index = function(_, key)
        local res = config[key]
        if type(res) == 'table' then
            return vim.deepcopy(res)
        else
            return res
        end
    end,
}

M.config = setmetatable({}, config_copy_view_metatable)

return M

