# DotEnv.jl

[![Build Status](https://travis-ci.org/vmari/DotEnv.jl.svg?branch=master)](https://travis-ci.org/vmari/DotEnv.jl)
[![Coverage Status](https://coveralls.io/repos/github/vmari/DotEnv.jl/badge.svg?branch=master)](https://coveralls.io/github/vmari/DotEnv.jl?branch=master)

DotEnv.jl is a zero-dependency package that loads environment variables from a `.env` file into [`ENV`](https://docs.julialang.org/en/latest/manual/environment-variables/). Storing configuration in the environment is based on [The Twelve-Factor App](http://12factor.net/config) methodology.

## Install

```julia
Pkg.add("DotEnv")
```

## Usage

```julia
using DotEnv
DotEnv.config()
```

Create a `.env` file in your project. You can add environment-specific variables using the rule `NAME=VALUE`.
For example:

```dosini
#.env file
DB_HOST=127.0.0.1
DB_USER=john
DB_PASS=42
```

In this way, `ENV` obtain both, the keys and the values you set in your `.env` file.

```julia
ENV["DB_PASS"]
"42"
```

## Config

`config` reads your .env file, parse the content, stores it to 
[`ENV`](https://docs.julialang.org/en/latest/manual/environment-variables/),
and finally return a Dict with the content.  

```julia
import DotEnv

cfg = DotEnv.config()

println(cfg)
```

### Options

#### Path

Default: `.env`

You can specify a custom path for your .env file.

```julia
using DotEnv
DotEnv.config(path = "custom.env")
```

## Manual Parsing

`DotEnv.parse` accepts a String or an IOBuffer (Any value that can be converted into String), and it will return
a Dict with the parsed keys and values.

```julia
import DotEnv
buff = IOBuffer("BASIC=basic")
cfg = DotEnv.parse(buff) # will return a Dict
println(config) # Dict("BASIC"=>"basic")
```

### Rules

You can write your `.env` file using the following rules:

- `BASIC=basic` becomes `Dict("BASIC"=>"basic")`
- empty lines are skipped
- `#` are comments
- empty content is treated as an empty string (`EMPTY=` -> `Dict("EMPTY"=>"")`)
- external single and double quotes are removed (`SINGLE_QUOTE='quoted'` -> `Dict("SINGLE_QUOTE"=>"quoted")`)
- inside double quotes, new lines are expanded (`MULTILINE="new\nline"` ->
```
Dict("MULTILINE"=>"new
line")
```
- inner quotes are maintained (like JSON) (`JSON={"foo": "bar"}` -> `Dict("JSON"=>"{\"foo\": \"bar\"}")"`)
- extra spaces are removed from both ends of the value (`FOO="  some value  "` -> `Dict("FOO"=>"some value")`)
- previous `ENV` environment variables are not replaced. If you want to override `ENV` try:

```julia
using DotEnv

cfg = DotEnv.parse(read(".env.override"))

for (k, v) in cfg
    ENV[k] = v
end
```

## Note about credits

We want to thank @motdotla. Our code is mostly based on [his repo](https://github.com/motdotla/dotenv)
