local M = {}

local wrapReturnTypes = function(returnTypes)
	return " -> (" .. returnTypes .. ")"
end

local function debug_setup()
	local go_parser_loaded = pcall(vim.treesitter.language.require_language, "go")
	print("TreeSitter Go parser loaded:", go_parser_loaded)

	-- Check if LSP is running for Go
	local clients = vim.lsp.get_active_clients()
	local go_lsp_running = false
	for _, client in pairs(clients) do
		if client.name == "gopls" then
			go_lsp_running = true
			break
		end
	end
	print("Go LSP running:", go_lsp_running)

	-- Check if we can create namespace
	local ns_success = pcall(vim.api.nvim_create_namespace, "inline_types")
	print("Can create namespace:", ns_success)
end

local extractReturnTypes = function(signature)
	if signature:sub(-1) ~= ")" then
		local returnType = signature:match(".+%s(.+)$") or "No return type"
		return returnType
	else
		local depth = 0
		for i = #signature, 1, -1 do
			local char = signature:sub(i, i)
			if char == ")" then
				depth = depth + 1
			elseif char == "(" then
				depth = depth - 1
				if depth == 0 then
					if signature:sub(i - 1, i - 1) ~= " " then
						return "void"
					else
						local returnType = signature:sub(i + 1, #signature - 1)
						return returnType
					end
				end
			end
		end
	end

	return "void"
end

M.tsQuery = [[
(call_expression
  function: [
    (identifier) @function-name
    (selector_expression
      field: (field_identifier) @method-name)
  ])
]]

M._method_names = vim.treesitter.query.parse("go", M.tsQuery)

M._get_root = function(bufnr)
	local parser = vim.treesitter.get_parser(bufnr, "go", {})
	local tree = parser:parse()[1]
	return tree:root()
end

M._debounce_timers = {}
local function debounce(fn, delay)
	return function(...)
		local args = { ... }
		local bufnr = args[1]

		-- Cancel existing timer if any
		if M._debounce_timers[bufnr] then
			M._debounce_timers[bufnr]:stop()
			M._debounce_timers[bufnr] = nil
		end

		-- Create new timer
		local timer = vim.loop.new_timer()
		M._debounce_timers[bufnr] = timer

		timer:start(delay, 0, vim.schedule_wrap(function()
			M._debounce_timers[bufnr] = nil
			timer:close()
			-- Pass the stored args
			fn(args[1])
		end))
	end
end

-- Create debounced version of getRetTypes with explicit function reference
M._debouncedGetRetTypes = debounce(function(bufnr)
	return M._getRetTypes(bufnr)
end, 0)

M._getRetTypes = function(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	-- Initialize cache for the buffer if it doesn't exist
	M._return_type_cache[bufnr] = M._return_type_cache[bufnr] or {}

	if vim.bo[bufnr].filetype ~= "go" then
		vim.notify("can only be used in Go")
		return
	end

	local root = M._get_root(bufnr)
	local ns_id = vim.api.nvim_create_namespace("inline_types")

	-- Track existing and new extmarks
	local existing_marks = {}
	local new_marks = {}

	-- Get existing marks
	for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})) do
		local mark_id, line = mark[1], mark[2]
		existing_marks[line] = mark_id
	end

	local linesUpdated = {}
	for id, node in M._method_names:iter_captures(root, bufnr, 0, -1) do
		local name = M._method_names.captures[id]
		if name == "method-name" or name == "function-name" then
			local uri = vim.uri_from_bufnr(bufnr)
			local start_line, start_char, end_line, end_char = node:range()

			if linesUpdated[start_line] then
				goto continue
			end
			linesUpdated[start_line] = true

			-- Extracting the function name from the buffer
			local func_name = vim.api.nvim_buf_get_text(bufnr, start_line, start_char, end_line, end_char, {})[1]

			if func_name then
				if not M._return_type_cache[bufnr][func_name] then
					-- No cache exists, get new data
					local params = {
						textDocument = { uri = uri },
						position = { line = start_line, character = start_char },
					}
					M._getData(params, function(rt)
						if rt then
							M._return_type_cache[bufnr][func_name] = {
								type = rt,
								timestamp = vim.loop.now(),
							}
							local virt_text = wrapReturnTypes(rt)
							-- Update or create mark
							if existing_marks[start_line] then
								vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_line, 0, {
									id = existing_marks[start_line],
									virt_text = { { virt_text, "Comment" } },
									virt_text_pos = "eol",
								})
							else
								vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_line, 0, {
									virt_text = { { virt_text, "Comment" } },
									virt_text_pos = "eol",
								})
							end
							new_marks[start_line] = true
						end
					end)
				else
					-- Cache exists, check if valid
					local cache_entry = M._return_type_cache[bufnr][func_name]
					if cache_entry and cache_entry.timestamp then
						local cache_age = (vim.loop.now() - cache_entry.timestamp) / 1000 / 60 / 60
						if cache_age > 24 then -- Expire after 24 hours
							-- Cache expired, get new data
							M._return_type_cache[bufnr][func_name] = nil
							local params = {
								textDocument = { uri = uri },
								position = { line = start_line, character = start_char },
							}
							M._getData(params, function(rt)
								if rt then
									M._return_type_cache[bufnr][func_name] = {
										type = rt,
										timestamp = vim.loop.now(),
									}
									local virt_text = wrapReturnTypes(rt)
									-- Update or create mark
									if existing_marks[start_line] then
										vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_line, 0, {
											id = existing_marks[start_line],
											virt_text = { { virt_text, "Comment" } },
											virt_text_pos = "eol",
										})
									else
										vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_line, 0, {
											virt_text = { { virt_text, "Comment" } },
											virt_text_pos = "eol",
										})
									end
									new_marks[start_line] = true
								end
							end)
						else
							-- Cache is still valid
							local virt_text = wrapReturnTypes(cache_entry.type)
							-- Update or create mark
							if existing_marks[start_line] then
								vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_line, 0, {
									id = existing_marks[start_line],
									virt_text = { { virt_text, "Comment" } },
									virt_text_pos = "eol",
								})
							else
								vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_line, 0, {
									virt_text = { { virt_text, "Comment" } },
									virt_text_pos = "eol",
								})
							end
							new_marks[start_line] = true
						end
					end
				end
			end
		end
		::continue::
	end

	-- Clean up old marks that aren't needed anymore
	for line, mark_id in pairs(existing_marks) do
		if not new_marks[line] then
			vim.api.nvim_buf_del_extmark(bufnr, ns_id, mark_id)
		end
	end
end

M._return_type_cache = {}

M.extract_return_type = function(hover_response)
	if
		not (
			hover_response
			and hover_response[1]
			and hover_response[1].result
			and hover_response[1].result.contents
			and hover_response[1].result.contents.value
		)
	then
		return nil
	end

	local value = hover_response[1].result.contents.value

	local pattern = "%f[%S]([^\n]+)%f[%s]"

	local _, _, return_type = string.find(value, pattern)

	if return_type then
		return_type = return_type:match("^%s*(.-)%s*$")
		return return_type
	else
		return "Return type not found"
	end
end


M._getData = function(params, callback)
	local clients = vim.lsp.get_active_clients()
	local has_gopls = false
	for _, client in pairs(clients) do
		if client.name == "gopls" then
			has_gopls = true
			break
		end
	end

	if not has_gopls then
		vim.notify("Waiting for gopls to initialize...", vim.log.levels.INFO)
		return
	end

	local bufnr = vim.uri_to_bufnr(params.textDocument.uri)

	vim.lsp.buf_request(bufnr, "textDocument/hover", params, function(err, result, ctx)
		if err then
			vim.notify("LSP Error: " .. vim.inspect(err), vim.log.levels.ERROR)
			return
		end

		if not result then return end

		local hover_response = { { result = result } }
		local signature = M.extract_return_type(hover_response)

		if signature then
			local rt = extractReturnTypes(signature)
			vim.schedule(function()
				callback(rt)
			end)
		end
	end)
end

M._cleanup_cache = function()
	-- Get list of current buffers
	local current_buffers = {}
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		current_buffers[bufnr] = true
	end

	-- Remove cache entries for non-existent buffers
	for bufnr in pairs(M._return_type_cache) do
		if not current_buffers[bufnr] or not vim.api.nvim_buf_is_valid(bufnr) then
			M._return_type_cache[bufnr] = nil
		end
	end
end

M.clear_cache = function(bufnr)
	if bufnr then
		M._return_type_cache[bufnr] = nil
	else
		M._return_type_cache = {}
	end
	M._getRetTypes()
end

M.setup = function()
	vim.api.nvim_create_user_command("ShowReturnTypes", function()
		M._getRetTypes()
	end, {})

	M.augroup = vim.api.nvim_create_augroup("GoInlineTypes", { clear = true })

	vim.api.nvim_create_autocmd("BufDelete", {
		group = M.augroup,
		callback = function(args)
			if M._return_type_cache[args.buf] then
				M._return_type_cache[args.buf] = nil
			end
		end,
	})

	vim.api.nvim_create_user_command("ClearReturnTypesCache", function()
		M.clear_cache()
	end, {})

	vim.api.nvim_create_autocmd("LspAttach", {
		group = M.augroup,
		callback = function(args)
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			if client and client.name == "gopls" then
				vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
					group = M.augroup,
					buffer = args.buf,
					callback = function()
						M._debouncedGetRetTypes(args.buf)
					end,
				})

				M._getRetTypes(args.buf)
			end
		end,
	})

	vim.api.nvim_create_autocmd("BufDelete", {
		group = M.augroup,
		callback = function(args)
			if M._debounce_timers[args.buf] then
				vim.loop.timer_stop(M._debounce_timers[args.buf])
				M._debounce_timers[args.buf] = nil
			end
		end,
	})
end



return M
