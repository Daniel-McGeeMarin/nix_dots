require("llm").setup({
	model = "starcoder2:15b",
	backend = "ollama",
	url = "http://localhost:11434/api/generate", -- the http url of the backend
	tokens_to_clear = { "<|endoftext|>" }, -- tokens to remove from the model's output
	request_body = {
		parameters = {
			temperature = 0.2,
			top_p = 0.95,
		},
	},
	-- set this if the model supports fill in the middle
	fim = {
		enabled = true,
		prefix = "<fim_prefix>",
		middle = "<fim_middle>",
		suffix = "<fim_suffix>",
	},
	debounce_ms = 150,
	accept_keymap = "<Tab>",
	dismiss_keymap = "<S-Tab>",
	tls_skip_verify_insecure = false,
	lsp = {
		bin_path = vim.api.nvim_call_function("stdpath", { "data" }) .. "/mason/bin/llm-ls",
	},
	-- tokenizer = nil, -- cf Tokenizer paragraph
	-- context_window = 8192, -- max number of tokens for the context window
	enable_suggestions_on_startup = true,
	enable_suggestions_on_files = "*",
})
