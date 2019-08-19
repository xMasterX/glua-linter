glualint for macOS
==========

glualint - Linter and pretty printer for Garry's Mod's variant of Lua.

# Installing into system
1. Download the latest version of `glualint` from [the Releases page](https://github.com/xMasterX/glua-linter/releases)
2. Place the `glualint` executable inside some folder.
3. Add the folder you put `glualint` in to your `PATH`. How this is done differs per operating system. If you're not sure how to do this, please Google `"Add to PATH mac"`.
4. Make sure you restart any terminals or text editors you currently have open.

After performing these steps, you can run `glualint` from the terminal or let your text editor use it as your linter. **Failing to specifically perform the third step will make `glualint` very unlikely to work**.

# Command line parameters

Parameter | Description
----------|------------
`--version` | Returns the version of glualint
`--config` | Set to a `glualing.json` file for glualint configuration. See "Configuring glualint"
`--pretty-print` | Will pretty-print (re-structure/re-indent) all code given in stdin. When entering code in terminal, press Ctrl+D to finish the input.
`--indentation='something'` | For pretty-print: indents all pretty-printed code with the given string. Four spaces by default, should probably some amount of tabs or spaces.

# Changelog

Version | Changelog
----------|------------
1.11.2 | glualint now searches for glualint.json files from the current working directory when reading from stdin.

# Configuring glualint
Check out at [Falco's GLuaFixer](https://github.com/FPtje/GLuaFixer)
