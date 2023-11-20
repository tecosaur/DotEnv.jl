"""
    DotEnv

DotEnv.jl is a lightweight package that loads environment variables from `.env`
files into [`ENV`](@ref).  Storing configuration in the environment is based on
[The Twelve-Factor App](http://12factor.net/config) methodology.

Please don't store secrets in dotenv files, and if you must at least ensure the
dotenv file(s) are listed in `.gitignore`.

# Quickstart

Use `DotEnv.load!()` to load environment variables, `DotEnv.unload!()` to undo
the loading, and `DotEnv.config()` to fetch a dictionary representing the
modified environment without mutating it.

See the docstrings of these functions for more information.

# Automatically detected dotenv files

DotEnv matches the canonical behaviour of https://github.com/bkeepers/dotenv,
and will read the following filenames, with the most specific (last) taking
priority:
- `.env`
- `.env.production`
- `.env.test`
- `.env.development`
- `.env.local`
- `.env.production.local`
- `.env.test.local`
- `.env.development.local`

If there are no dotenv files in the current directory, `DotEnv.load!()` and
`DotEnv.unload!()` will look at the parent directory, recursively until dotenv
files are found or the root directory is reached.

# DotEnv format

The DotEnv format will likely be familiar.

```text
FOO=bar # inline comment
BAZ="\${FOO}bar"
```

For the sake of clarity though, the parsing rules are thus:

1. Leading whitespace is ignored
2. Empty lines, and lines starting with `#` are skipped
3. `export` prefixes are ignored (e.g. `export FOO=bar`)
4. Empty assignments are regarded as the empty string(`EMPTY=` becomes `"EMPTY" => ""`)
5. Keys and values are separated by `=` or `:`, and any amount of whitespace
6. All values are strings, but can be quoted with single (`'`) or double quotes (`"`)
7. Quotes of the same type may occur within quoted values, but must be escaped with `\\`
8. Inline comments are started with a `#` outside of a quoted value
9. Inside double quoted values, `\\n` newlines are expanded, allowing for multiline values
10. Extra spaces are removed from both ends of an unquoted value (e.g. `FOO` some
    value ` becomes `"FOO" => "some value"`)
11. Variable expansion occurs within unquoted and double-quoted values. `\$NAME`,
    `\${NAME}`, and `\${NAME:-default}` expansions are all supported.
12. Malformed lines are silently skipped
"""
module DotEnv

using PrecompileTools

include("types.jl")

const ENV_FILENAMES = # From <https://github.com/bkeepers/dotenv>, highest priority last
    [".env",       ".env.production",       ".env.test",       ".env.development",
     ".env.local", ".env.production.local", ".env.test.local", ".env.development.local"]

const ENV_STACKS = IdDict{AbstractDict{String, String}, Vector{EnvFile}}()
const ENV_ORIGINALS = IdDict{AbstractDict{String, String}, Dict{String, Union{String, Nothing}}}()

include("parser.jl")
include("loading.jl")

include("precompile.jl")

end
