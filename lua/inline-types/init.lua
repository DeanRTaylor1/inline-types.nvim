local M = {}

local wrapReturnTypes = function(returnTypes)
	return " -> (" .. returnTypes .. ")"
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

M.tsQuery = [[(call_expression
  function: (identifier) @function-name)

; Match a method or namespaced function call
(call_expression
  function: (selector_expression
    field: (field_identifier) @method-name))
]]

M._method_names = vim.treesitter.query.parse("go", M.tsQuery)

M._get_root = function(bufnr)
	local parser = vim.treesitter.get_parser(bufnr, "go", {})
	local tree = parser:parse()[1]
	return tree:root()
end

M._return_type_cache = {}

M._getRetTypes = function(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	--
	-- Initialize cache for the buffer if it doesn't exist
	M._return_type_cache[bufnr] = M._return_type_cache[bufnr] or {}

	if vim.bo[bufnr].filetype ~= "go" then
		vim.notify("can only be used in Go")
		return
	end

	local root = M._get_root(bufnr)

	-- Create or get an existing namespace for our virtual text annotations.
	local ns_id = vim.api.nvim_create_namespace("inline_types")
	vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

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

			if func_name and not M._return_type_cache[bufnr][func_name] then
				local params = {
					textDocument = { uri = uri },
					position = { line = start_line, character = start_char },
				}
				M._getData(params, function(rt)
					-- Check again in case it was set while waiting for getData
					if rt and not M._return_type_cache[bufnr][func_name] then
						M._return_type_cache[bufnr][func_name] = rt
						local virt_text = wrapReturnTypes(rt)
						vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_line, 0, {
							virt_text = { { virt_text, "Comment" } },
							virt_text_pos = "eol",
						})
					end
				end)
			elseif func_name and M._return_type_cache[bufnr][func_name] then
				local virt_text = wrapReturnTypes(M._return_type_cache[bufnr][func_name])
				vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_line, 0, {
					virt_text = { { virt_text, "Comment" } },
					virt_text_pos = "eol",
				})
			end
		end
		::continue::
	end
end

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
	local params = params or vim.lsp.util.make_position_params()
	local result = vim.lsp.buf_request_sync(0, "textDocument/hover", params, 2000)
	local signature = M.extract_return_type(result)

	if not signature then
		return
	end

	local rt = extractReturnTypes(signature)

	callback(rt)
end

function M.setup()
	vim.api.nvim_create_user_command("ShowReturnTypes", function()
		M._getRetTypes()
	end, {})

	M.augroup = vim.api.nvim_create_augroup("GoInlineTypes", { clear = true })

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = M.augroup,
		pattern = { "*.go" },
		callback = function()
			M._getRetTypes()
		end,
	})
end

return M

--Deprecated
-- local cleanSignature = function(signature)
-- 	-- First, find the closing parenthesis of the receiver if it exists.
-- 	local receiverEnd = 0
-- 	if signature:sub(1, 4) == "func" and signature:find("%(") then
-- 		receiverEnd = signature:find("%)") or 0
-- 	end

-- 	-- Now find the end of the function parameters to identify the return type start.
-- 	-- If receiverEnd is 0, it means there's no receiver, so start from the beginning.
-- 	local paramsStart = signature:find("%(", receiverEnd) or 0
-- 	local paramsEnd = signature:find("%)", paramsStart) or 0

-- 	-- If there is no return type, return the original signature.
-- 	local hasReturnType = signature:find("[^%s]", paramsEnd + 1)
-- 	if not hasReturnType then
-- 		return signature
-- 	end

-- 	-- Extract the parts of the signature.
-- 	local beforeReturnType = signature:sub(1, paramsEnd)
-- 	local returnType = signature:sub(paramsEnd + 1)

-- 	-- Trim spaces from the return type's start.
-- 	returnType = returnType:match("^%s*(.*)")

-- 	-- Decide how to add the arrow based on the return type's first character.
-- 	if returnType:sub(1, 1) == "(" or returnType:sub(1, 1) == "*" then
-- 		return beforeReturnType .. " -> " .. returnType
-- 	else
-- 		return beforeReturnType .. " -> (" .. returnType .. ")"
-- 	end
-- end
