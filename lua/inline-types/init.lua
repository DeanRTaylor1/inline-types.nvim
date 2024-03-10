local M = {}

M.tsQuery = [[(call_expression
  function: (identifier) @function-name)

; Match a method or namespaced function call
(call_expression
  function: (selector_expression
    field: (field_identifier) @method-name))
]]

M.method_names = vim.treesitter.query.parse("go", M.tsQuery)

M.get_root = function(bufnr)
	local parser = vim.treesitter.get_parser(bufnr, "go", {})
	local tree = parser:parse()[1]
	return tree:root()
end

M.return_type_cache = {}

M.getRetTypes = function(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	--
	-- Initialize cache for the buffer if it doesn't exist
	M.return_type_cache[bufnr] = M.return_type_cache[bufnr] or {}

	if vim.bo[bufnr].filetype ~= "go" then
		vim.notify("can only be used in Go")
		return
	end

	local root = M.get_root(bufnr)

	-- Create or get an existing namespace for our virtual text annotations.
	local ns_id = vim.api.nvim_create_namespace("inline_types")
	vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

	for id, node in M.method_names:iter_captures(root, bufnr, 0, -1) do
		local name = M.method_names.captures[id]
		if name == "method-name" or name == "function-name" then
			local uri = vim.uri_from_bufnr(0)
			local start_line, start_char = node:start()

			if M.return_type_cache[bufnr][start_line] then
				local virt_text = " " .. M.return_type_cache[bufnr][start_line]
				vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_line, 0, {
					virt_text = { { virt_text, "Comment" } },
					virt_text_pos = "eol",
				})
			else
				local params = {
					textDocument = { uri = uri },
					position = { line = start_line, character = start_char },
				}
				M.getData(params, function(rt)
					if rt then
						local virt_text = " " .. rt
						vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_line, 0, {
							virt_text = { { virt_text, "Comment" } },
							virt_text_pos = "eol",
						})
					end
				end)
			end
		end
	end
end

M.extract_return_type = function(hover_response)
	-- Extract the content value which is the markdown string
	if
		not (
			hover_response
			and hover_response[1]
			and hover_response[1].result
			and hover_response[1].result.contents
			and hover_response[1].result.contents.value
		)
	then
		return nil -- Or return early if the expected hover response structure isn't present
	end

	local value = hover_response[1].result.contents.value

	-- Pattern explanation:
	-- %f[%S]: frontier pattern, matches an empty string at the beginning of a non-space character.
	-- [^\n]+: matches one or more non-newline characters (greedy), capturing the return type.
	-- %f[%s]: frontier pattern, matches an empty string at the end of a non-space character.
	local pattern = "%f[%S]([^\n]+)%f[%s]"

	-- Find and capture the return type which appears after 'func (...) '
	local _, _, return_type = string.find(value, pattern)

	-- Check if the return type was successfully captured and return it
	if return_type then
		-- Clean up the return type by trimming any potential leading/trailing spaces
		return_type = return_type:match("^%s*(.-)%s*$")
		return return_type
	else
		return "Return type not found"
	end
end

M.cleanSignature = function(signature)
	-- First, find the closing parenthesis of the receiver if it exists.
	local receiverEnd = 0
	if signature:sub(1, 4) == "func" and signature:find("%(") then
		receiverEnd = signature:find("%)") or 0
	end

	-- Now find the end of the function parameters to identify the return type start.
	-- If receiverEnd is 0, it means there's no receiver, so start from the beginning.
	local paramsStart = signature:find("%(", receiverEnd) or 0
	local paramsEnd = signature:find("%)", paramsStart) or 0

	-- If there is no return type, return the original signature.
	local hasReturnType = signature:find("[^%s]", paramsEnd + 1)
	if not hasReturnType then
		return signature
	end

	-- Extract the parts of the signature.
	local beforeReturnType = signature:sub(1, paramsEnd)
	local returnType = signature:sub(paramsEnd + 1)

	-- Trim spaces from the return type's start.
	returnType = returnType:match("^%s*(.*)")

	-- Decide how to add the arrow based on the return type's first character.
	if returnType:sub(1, 1) == "(" or returnType:sub(1, 1) == "*" then
		return beforeReturnType .. " -> " .. returnType
	else
		return beforeReturnType .. " -> (" .. returnType .. ")"
	end
end

M.getData = function(params, callback)
	local params = params or vim.lsp.util.make_position_params()
	local result = vim.lsp.buf_request_sync(0, "textDocument/hover", params, 2000)
	-- print(vim.inspect(result))
	local signature = M.extract_return_type(result)

	if not signature then
		return
	end

	local rt = M.cleanSignature(signature)

	callback(rt)
end

function M.setup()
	vim.api.nvim_create_user_command("AutoRun", function()
		M.getRetTypes()
	end, {})

	M.augroup = vim.api.nvim_create_augroup("GoInlineTypes", { clear = true })

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufRead" }, {
		group = M.augroup,
		pattern = { "*.go" },
		callback = function()
			M.getRetTypes()
		end,
	})
end

return M
