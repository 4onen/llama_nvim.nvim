-- Copyright © 2024 Matthew Dupree
-- This file is part of llama_nvim

local M = {}

local name = "llama_nvim"
local min_curl_version = "7.81.0"

M.check = function()
    vim.health.start(name .. " core")
    -- First, check the neovim version is at least 0.10.0
    -- This is necessary for vim.system() to work, which
    -- is used to check the curl version
    if vim.version().major < 1 and vim.version().minor < 10 then
        vim.health.error(name .. " requires neovim 0.10.0 or later!")
        return
    else
        vim.health.ok("Neovim version: " .. tostring(vim.version()) .. " (>= 0.10.0)")
    end

    -- Second, check that curl is installed and at least min_curl_version
    local success, res = pcall(function() return vim.system({'curl','--version'},{text=true}):wait().stdout end)
    if not success then
        vim.health.error("curl not found! Please install curl to use "..name)
    else
        local version = res:match('curl (%d+%.%d+%.%d+)')
        if version and version >= min_curl_version then
            vim.health.ok(string.format(
                'curl version: %s (>= %s)',
                version,
                min_curl_version
            ))
        elseif version then
            -- Yes, I'm too lazy to check the version number properly
            vim.health.warn(string.format(
                'curl version: %s (>= %s recommended)',
                version,
                min_curl_version
            ))
        else
            vim.health.warn('Curl version not found! (>= '..min_curl_version..' recommended)')
        end
    end

    -- Third, check that the plugin itself is installed
    local success, res = pcall(require, name)
    if not success then
        vim.health.error(string.format("%s not found! Please install %s to use %s.", name, name, name))
        return
    else
        vim.health.ok(name .." loaded.")
    end
    local mod = res

    -- Finally, check that the plugin has been set up
    if mod.config and mod.config.is_setup then
        vim.health.ok(name.." is setup")
    else
        vim.health.warn(name.." has not had setup() called.\nKeybindings and commands will not be available.")
    end
end
return M

