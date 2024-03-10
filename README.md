# Inline Types Plugin for Neovim - Beta

The Inline Types plugin enhances your Go development experience in Neovim by displaying function signatures and return types directly in your code, as virtual text. This plugin uses the power of Treesitter and Neovim's built-in LSP to provide you with inline annotations of function return types, so you don't have to jump back and forth between definitions.

## Features

- **Inline Function Signatures**: See at a glance what types your functions return without leaving your current cursor position.
- **Automatic Updates**: Annotations update as you type, keeping you informed of the latest return types.
- **Buffer Scoped**: Annotations are specific to each buffer, so they stay relevant and accurate per file.
- **Intelligent Caching**: Avoids unnecessary LSP requests by caching return types per buffer, optimizing performance.
- **Go Language Support**: Tailored specifically for Go, the plugin respects Go's syntax and tooling ecosystem.

## Usage

With Inline Types, your code gets annotated with the return types as shown in the screenshots:

![Code examples](/images/inline-types-ex-2.png)

Annotations are subtly displayed, ensuring they don't distract from the code's readability:

![Mock interface with annotated methods](/images/inline-types-ex.png)

## Installation

You can install the Inline Types plugin using your preferred Neovim package manager. For instance, with `lazy-nvim`, you can add the following line to your `init.lua`:

```lua
  { 'deanrtaylor1/inline-types.nvim', dependencies = { 'nvim-treesitter/nvim-treesitter' } },
```

## Configuration

After installation, the plugin requires no additional configuration and will work out of the box for Go files.

If you need to manually trigger the annotations, you can use the provided `AutoRun` command:

```vim
:ShowReturnTypes
```

## Developing and Contributing

The plugin is designed to be easy to extend. If you're a developer wanting to contribute or customize the plugin, clone the repository and dive into the code:

```bash
git clone https://github.com/deanrtaylor1/inline-types.nvim.git
```

Contributions to extend support beyond Go, improve performance, or add new features are always welcome. In future, I'd like to allow users to select more languages or register a custom language by passing a file type and a formatter function to parse the lsp return data
