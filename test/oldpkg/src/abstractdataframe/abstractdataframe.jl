"""
    AbstractDataFrame

An abstract type for which all concrete types expose an interface
for working with tabular data.

**Common methods**

An AbstractDataFrame is a two-dimensional table with Symbols for
column names. An AbstractDataFrame is also similar to an Associative
type in that it allows indexing by a key (the columns).

The following are normally implemented for AbstractDataFrames:

* [`describe`](@ref) : summarize columns
* [`dump`](@ref) : show structure
* `hcat` : horizontal concatenation
* `vcat` : vertical concatenation
* [`repeat`](@ref) : repeat rows
* `names` : columns names
* [`names!`](@ref) : set columns names
* [`rename!`](@ref) : rename columns names based on keyword arguments
* [`eltypes`](@ref) : `eltype` of each column
* `length` : number of columns
* `size` : (nrows, ncols)
* [`first`](@ref) : first `n` rows
* [`last`](@ref) : last `n` rows
* `convert` : convert to an array
* [`completecases`](@ref) : boolean vector of complete cases (rows with no missings)
* [`dropmissing`](@ref) : remove rows with missing values
* [`dropmissing!`](@ref) : remove rows with missing values in-place
* [`nonunique`](@ref) : indexes of duplicate rows
* [`unique!`](@ref) : remove duplicate rows
* `similar` : a DataFrame with similar columns as `d`
* `filter` : remove rows
* `filter!` : remove rows in-place

**Indexing**

Table columns are accessed (`getindex`) by a single index that can be
a symbol identifier, an integer, or a vector of each. If a single
column is selected, just the column object is returned. If multiple
columns are selected, some AbstractDataFrame is returned.

```julia
d[:colA]
d[3]
d[[:colA, :colB]]
d[[1:3; 5]]
```

Rows and columns can be indexed like a `Matrix` with the added feature
of indexing columns by name.

```julia
d[1:3, :colA]
d[3,3]
d[3,:]
d[3,[:colA, :colB]]
d[:, [:colA, :colB]]
d[[1:3; 5], :]
```

`setindex` works similarly.
"""
abstract type AbstractDataFrame end

##############################################################################
##
## Interface (not final)
##
##############################################################################

# index(df) => AbstractIndex
# nrow(df) => Int
# ncol(df) => Int
# getindex(...)
# setindex!(...) exclusive of methods that add new columns

##############################################################################
##
## Basic properties of a DataFrame
##
##############################################################################

Base.names(df::AbstractDataFrame) = names(index(df))
_names(df::AbstractDataFrame) = _names(index(df))

"""
Set column names


```julia
names!(df::AbstractDataFrame, vals)
```

**Arguments**

* `df` : the AbstractDataFrame
* `vals` : column names, normally a Vector{Symbol} the same length as
  the number of columns in `df`
* `makeunique` : if `false` (the default), an error will be raised
  if duplicate names are found; if `true`, duplicate names will be suffixed
  with `_i` (`i` starting at 1 for the first duplicate).

**Result**

* `::AbstractDataFrame` : the updated result


**Examples**

```julia
df = DataFrame(i = 1:10, x = rand(10), y = rand(["a", "b", "c"], 10))
names!(df, [:a, :b, :c])
names!(df, [:a, :b, :a])  # throws ArgumentError
names!(df, [:a, :b, :a], makeunique=true)  # renames second :a to :a_1
```

"""
function names!(df::AbstractDataFrame, vals; makeunique::Bool=false)
    names!(index(df), vals, makeunique=makeunique)
    return df
end

function rename!(df::AbstractDataFrame, args...)
    rename!(index(df), args...)
    return df
end
function rename!(f::Function, df::AbstractDataFrame)
    rename!(f, index(df))
    return df
end

rename(df::AbstractDataFrame, args...) = rename!(copy(df), args...)
rename(f::Function, df::AbstractDataFrame) = rename!(f, copy(df))

"""
Rename columns

```julia
rename!(df::AbstractDataFrame, (from => to)::Pair{Symbol, Symbol}...)
rename!(df::AbstractDataFrame, d::AbstractDict{Symbol,Symbol})
rename!(df::AbstractDataFrame, d::AbstractArray{Pair{Symbol,Symbol}})
rename!(f::Function, df::AbstractDataFrame)
rename(df::AbstractDataFrame, (from => to)::Pair{Symbol, Symbol}...)
rename(df::AbstractDataFrame, d::AbstractDict{Symbol,Symbol})
rename(df::AbstractDataFrame, d::AbstractArray{Pair{Symbol,Symbol}})
rename(f::Function, df::AbstractDataFrame)
```

**Arguments**

* `df` : the AbstractDataFrame
* `d` : an Associative type or an AbstractArray of pairs that maps
  the original names to new names
* `f` : a function which for each column takes the old name (a Symbol)
  and returns the new name (a Symbol)

**Result**

* `::AbstractDataFrame` : the updated result

New names are processed sequentially. A new name must not already exist in the `DataFrame`
at the moment an attempt to rename a column is performed.

**Examples**

```julia
df = DataFrame(i = 1:10, x = rand(10), y = rand(["a", "b", "c"], 10))
rename(df, :i => :A, :x => :X)
rename(df, [:i => :A, :x => :X])
rename(df, Dict(:i => :A, :x => :X))
rename(x -> Symbol(uppercase(string(x))), df)
rename(df) do x
    Symbol(uppercase(string(x)))
end
rename!(df, Dict(:i =>: A, :x => :X))
```

"""
(rename!, rename)

"""
Return element types of columns

```julia
eltypes(df::AbstractDataFrame)
```

**Arguments**

* `df` : the AbstractDataFrame

**Result**

* `::Vector{Type}` : the element type of each column

**Examples**

```julia
df = DataFrame(i = 1:10, x = rand(10), y = rand(["a", "b", "c"], 10))
eltypes(df)
```

"""
eltypes(df::AbstractDataFrame) = eltype.(columns(df))

Base.size(df::AbstractDataFrame) = (nrow(df), ncol(df))
function Base.size(df::AbstractDataFrame, i::Integer)
    if i == 1
        nrow(df)
    elseif i == 2
        ncol(df)
    else
        throw(ArgumentError("DataFrames only have two dimensions"))
    end
end

Base.lastindex(df::AbstractDataFrame) = ncol(df)
Base.lastindex(df::AbstractDataFrame, i::Integer) = last(axes(df, i))
Base.axes(df::AbstractDataFrame, i::Integer) = axes(df)[i]

Base.ndims(::AbstractDataFrame) = 2
Base.ndims(::Type{<:AbstractDataFrame}) = 2

Base.getproperty(df::AbstractDataFrame, col_ind::Symbol) = getindex(df, col_ind)
Base.setproperty!(df::AbstractDataFrame, col_ind::Symbol, x) = setindex!(df, x, col_ind)
# Private fields are never exposed since they can conflict with column names
Base.propertynames(df::AbstractDataFrame, private::Bool=false) = names(df)

##############################################################################
##
## Similar
##
##############################################################################

"""
    similar(df::DataFrame[, rows::Integer])

Create a new `DataFrame` with the same column names and column element types
as `df`. An optional second argument can be provided to request a number of rows
that is different than the number of rows present in `df`.
"""
function Base.similar(df::AbstractDataFrame, rows::Integer = size(df, 1))
    rows < 0 && throw(ArgumentError("the number of rows must be positive"))
    DataFrame(Any[similar(x, rows) for x in columns(df)], copy(index(df)))
end

##############################################################################
##
## Equality
##
##############################################################################

function Base.:(==)(df1::AbstractDataFrame, df2::AbstractDataFrame)
    size(df1, 2) == size(df2, 2) || return false
    isequal(index(df1), index(df2)) || return false
    eq = true
    for idx in 1:size(df1, 2)
        coleq = df1[idx] == df2[idx]
        # coleq could be missing
        !isequal(coleq, false) || return false
        eq &= coleq
    end
    return eq
end

function Base.isequal(df1::AbstractDataFrame, df2::AbstractDataFrame)
    size(df1, 2) == size(df2, 2) || return false
    isequal(index(df1), index(df2)) || return false
    for idx in 1:size(df1, 2)
        isequal(df1[idx], df2[idx]) || return false
    end
    return true
end

##############################################################################
##
## Associative methods
##
##############################################################################

Base.haskey(df::AbstractDataFrame, key::Any) = haskey(index(df), key)
Base.get(df::AbstractDataFrame, key::Any, default::Any) = haskey(df, key) ? df[key] : default
Base.isempty(df::AbstractDataFrame) = size(df, 1) == 0 || size(df, 2) == 0

##############################################################################
##
## Description
##
##############################################################################

"""
    first(df::AbstractDataFrame)

Get the first row of `df` as a `DataFrameRow`.
"""
Base.first(df::AbstractDataFrame) = df[1, :]

"""
    first(df::AbstractDataFrame, n::Integer)

Get a data frame with the `n` first rows of `df`.
"""
Base.first(df::AbstractDataFrame, n::Integer) = df[1:min(n,nrow(df)), :]

"""
    last(df::AbstractDataFrame)

Get the last row of `df` as a `DataFrameRow`.
"""
Base.last(df::AbstractDataFrame) = df[nrow(df), :]

"""
    last(df::AbstractDataFrame, n::Integer)

Get a data frame with the `n` last rows of `df`.
"""
Base.last(df::AbstractDataFrame, n::Integer) = df[max(1,nrow(df)-n+1):nrow(df), :]

# get the structure of a df
function Base.dump(io::IOContext, df::AbstractDataFrame, n::Int, indent)
    println(io, typeof(df), "  $(nrow(df)) observations of $(ncol(df)) variables")
    if n > 0
        for (name, col) in eachcol(df, true)
            println(io, indent, "  ", name, ": ", col)
        end
    end
end


"""
Report descriptive statistics for a data frame

```julia
describe(df::AbstractDataFrame; stats = [:mean, :min, :median, :max, :nmissing, :nunique, :eltype])
```

**Arguments**

* `df` : the AbstractDataFrame
* `stats::Union{Symbol,AbstractVector{Symbol}}` : the summary statistics to report. If
  a vector, allowed fields are `:mean`, `:std`, `:min`, `:q25`, `:median`,
  `:q75`, `:max`, `:eltype`, `:nunique`, `:first`, `:last`, and `:nmissing`. If set to
  `:all`, all summary statistics are reported.

**Result**

* A `DataFrame` where each row represents a variable and each column a summary statistic.

**Details**

For `Real` columns, compute the mean, standard deviation, minimum, first quantile, median,
third quantile, and maximum. If a column does not derive from `Real`, `describe` will
attempt to calculate all statistics, using `nothing` as a fall-back in the case of an error.

When `stats` contains `:nunique`, `describe` will report the
number of unique values in a column. If a column's base type derives from `Real`,
`:nunique` will return `nothing`s.

Missing values are filtered in the calculation of all statistics, however the column
`:nmissing` will report the number of missing values of that variable.
If the column does not allow missing values, `nothing` is returned.
Consequently, `nmissing = 0` indicates that the column allows
missing values, but does not currently contain any.

**Examples**

```julia
df = DataFrame(i = 1:10, x = rand(10), y = rand(["a", "b", "c"], 10))
describe(df)
describe(df, stats = :all)
describe(df, stats = [:min, :max])
```

"""
function StatsBase.describe(df::AbstractDataFrame; stats::Union{Symbol,AbstractVector{Symbol}} =
                            [:mean, :min, :median, :max, :nunique, :nmissing, :eltype])
    # Check that people don't specify the wrong fields.
    allowed_fields = [:mean, :std, :min, :q25, :median, :q75,
                      :max, :nunique, :nmissing, :first, :last, :eltype]
    if stats == :all
        stats = allowed_fields
    end

    if stats isa Symbol
        if !(stats in allowed_fields)
            allowed_msg = "\nAllowed fields are: :" * join(allowed_fields, ", :")
            throw(ArgumentError(":$stats not allowed." * allowed_msg))
        else
            stats = [stats]
        end
    end

    if !issubset(stats, allowed_fields)
        disallowed_fields = setdiff(stats, allowed_fields)
        allowed_msg = "\nAllowed fields are: :" * join(allowed_fields, ", :")
        not_allowed = "Field(s) not allowed: :" * join(disallowed_fields, ", :") * "."
        throw(ArgumentError(not_allowed * allowed_msg))
    end

    # Put the summary stats into the return data frame
    data = DataFrame()
    data[:variable] = names(df)

    # An array of Dicts for summary statistics
    column_stats_dicts = map(columns(df)) do col
        if eltype(col) >: Missing
            d = get_stats(collect(skipmissing(col)), stats)
        else
            d = get_stats(col, stats)
        end

        if :nmissing in stats 
            d[:nmissing] = eltype(col) >: Missing ? count(ismissing, col) : nothing
        end

        if :first in stats 
            d[:first] = isempty(col) ? nothing : first(col)
        end
        
        if :last in stats
            d[:last] = isempty(col) ? nothing : last(col)
        end

        return d             
    end

    for stat in stats
        # for each statistic, loop through the columns array to find values
        # letting the comprehension choose the appropriate type
        data[stat] = [column_stats_dict[stat] for column_stats_dict in column_stats_dicts]
    end
    return data
end

# Compute summary statistics
# use a dict because we dont know which measures the user wants
# Outside of the `describe` function due to something with 0.7
function get_stats(col::AbstractVector, stats::AbstractVector{Symbol})
    d = Dict{Symbol, Any}()

    if :q25 in stats || :median in stats || :q75 in stats 
        q = try quantile(col, [.25, .5, .75]) catch; (nothing, nothing, nothing) end
        d[:q25] = q[1]
        d[:median] = q[2]
        d[:q75] = q[3]
    end

    if :min in stats || :max in stats 
        ex = try extrema(col) catch; (nothing, nothing) end
        d[:min] = ex[1]
        d[:max] = ex[2]
    end

    if :mean in stats || :std in stats 
        m = try mean(col) catch end
        # we can add non-necessary things to d, because we choose what we need
        # in the main function
        d[:mean] = m
    end

    if :std in stats
        d[:std] = try std(col, mean = m) catch end
    end
    
    if :nunique in stats 
        if eltype(col) <: Real
            d[:nunique] = nothing
        else
            d[:nunique] = try length(unique(col)) catch end
        end
    end

    if :eltype in stats 
        d[:eltype] = eltype(col)
    end

    return d
end


##############################################################################
##
## Miscellaneous
##
##############################################################################

function _nonmissing!(res, col)
    @inbounds for (i, el) in enumerate(col)
        res[i] &= !ismissing(el)
    end
    return nothing
end

function _nonmissing!(res, col::CategoricalArray{>: Missing})
    for (i, el) in enumerate(col.refs)
        res[i] &= el > 0
    end
    return nothing
end


"""
    completecases(df::AbstractDataFrame)
    completecases(df::AbstractDataFrame, cols::AbstractVector)
    completecases(df::AbstractDataFrame, cols::Union{Integer, Symbol})

Return a Boolean vector with `true` entries indicating rows without missing values
(complete cases) in data frame `df`. If `cols` is provided, only missing values in
the corresponding columns are considered.

See also: [`dropmissing`](@ref) and [`dropmissing!`](@ref).
Use `findall(completecases(df))` to get the indices of the rows.

# Examples

```julia
julia> df = DataFrame(i = 1:5,
                      x = [missing, 4, missing, 2, 1],
                      y = [missing, missing, "c", "d", "e"])
5×3 DataFrame
│ Row │ i     │ x       │ y       │
│     │ Int64 │ Int64⍰  │ String⍰ │
├─────┼───────┼─────────┼─────────┤
│ 1   │ 1     │ missing │ missing │
│ 2   │ 2     │ 4       │ missing │
│ 3   │ 3     │ missing │ c       │
│ 4   │ 4     │ 2       │ d       │
│ 5   │ 5     │ 1       │ e       │

julia> completecases(df)
5-element BitArray{1}:
 false
 false
 false
  true
  true

julia> completecases(df, :x)
5-element BitArray{1}:
 false
  true
 false
  true
  true

julia> completecases(df, [:x, :y])
5-element BitArray{1}:
 false
 false
 false
  true
  true
```

"""
function completecases(df::AbstractDataFrame)
    res = trues(size(df, 1))
    for i in 1:size(df, 2)
        _nonmissing!(res, df[i])
    end
    res
end

function completecases(df::AbstractDataFrame, col::Union{Integer, Symbol})
    res = trues(size(df, 1))
    _nonmissing!(res, df[col])
    res
end

completecases(df::AbstractDataFrame, cols::AbstractVector) =
    completecases(df[cols])

# TODO: update docstrings after deprecation of disallowmissing
"""
    dropmissing(df::AbstractDataFrame; disallowmissing::Bool=false)
    dropmissing(df::AbstractDataFrame, cols::AbstractVector; disallowmissing::Bool=false)
    dropmissing(df::AbstractDataFrame, cols::Union{Integer, Symbol}; disallowmissing::Bool=false)

Return a copy of data frame `df` excluding rows with missing values.
If `cols` is provided, only missing values in the corresponding columns are considered.

In the future `disallowmissing` will be `true` by default.

See also: [`completecases`](@ref) and [`dropmissing!`](@ref).

# Examples

```julia
julia> df = DataFrame(i = 1:5,
                      x = [missing, 4, missing, 2, 1],
                      y = [missing, missing, "c", "d", "e"])
5×3 DataFrame
│ Row │ i     │ x       │ y       │
│     │ Int64 │ Int64⍰  │ String⍰ │
├─────┼───────┼─────────┼─────────┤
│ 1   │ 1     │ missing │ missing │
│ 2   │ 2     │ 4       │ missing │
│ 3   │ 3     │ missing │ c       │
│ 4   │ 4     │ 2       │ d       │
│ 5   │ 5     │ 1       │ e       │

julia> dropmissing(df)
2×3 DataFrame
│ Row │ i     │ x      │ y       │
│     │ Int64 │ Int64⍰ │ String⍰ │
├─────┼───────┼────────┼─────────┤
│ 1   │ 4     │ 2      │ d       │
│ 2   │ 5     │ 1      │ e       │

julia> dropmissing(df, disallowmissing=true)
2×3 DataFrame
│ Row │ i     │ x     │ y      │
│     │ Int64 │ Int64 │ String │
├─────┼───────┼───────┼────────┤
│ 1   │ 4     │ 2     │ d      │
│ 2   │ 5     │ 1     │ e      │

julia> dropmissing(df, :x)
3×3 DataFrame
│ Row │ i     │ x      │ y       │
│     │ Int64 │ Int64⍰ │ String⍰ │
├─────┼───────┼────────┼─────────┤
│ 1   │ 2     │ 4      │ missing │
│ 2   │ 4     │ 2      │ d       │
│ 3   │ 5     │ 1      │ e       │

julia> dropmissing(df, [:x, :y])
2×3 DataFrame
│ Row │ i     │ x      │ y       │
│     │ Int64 │ Int64⍰ │ String⍰ │
├─────┼───────┼────────┼─────────┤
│ 1   │ 4     │ 2      │ d       │
│ 2   │ 5     │ 1      │ e       │
```

"""
function dropmissing(df::AbstractDataFrame,
                     cols::Union{Integer, Symbol, AbstractVector}=1:size(df, 2);
                     disallowmissing::Bool=false)
    newdf = df[completecases(df, cols), :]
    if disallowmissing
        disallowmissing!(newdf, cols)
    else
        Base.depwarn("dropmissing will change eltype of cols to disallow missing by default. " *
                     "Use dropmissing(df, cols, disallowmissing=false) to allow for missing values.", :dropmissing)
    end
    newdf
end

"""
    dropmissing!(df::AbstractDataFrame; disallowmissing::Bool=false)
    dropmissing!(df::AbstractDataFrame, cols::AbstractVector; disallowmissing::Bool=false)
    dropmissing!(df::AbstractDataFrame, cols::Union{Integer, Symbol}; disallowmissing::Bool=false)

Remove rows with missing values from data frame `df` and return it.
If `cols` is provided, only missing values in the corresponding columns are considered.

In the future `disallowmissing` will be `true` by default.

See also: [`dropmissing`](@ref) and [`completecases`](@ref).

# Examples

```jldoctest
julia> df = DataFrame(i = 1:5,
                      x = [missing, 4, missing, 2, 1],
                      y = [missing, missing, "c", "d", "e"])
5×3 DataFrame
│ Row │ i     │ x       │ y       │
│     │ Int64 │ Int64⍰  │ String⍰ │
├─────┼───────┼─────────┼─────────┤
│ 1   │ 1     │ missing │ missing │
│ 2   │ 2     │ 4       │ missing │
│ 3   │ 3     │ missing │ c       │
│ 4   │ 4     │ 2       │ d       │
│ 5   │ 5     │ 1       │ e       │

julia> df1 = copy(df);

julia> dropmissing!(df1);

julia> df1
2×3 DataFrame
│ Row │ i     │ x      │ y       │
│     │ Int64 │ Int64⍰ │ String⍰ │
├─────┼───────┼────────┼─────────┤
│ 1   │ 4     │ 2      │ d       │
│ 2   │ 5     │ 1      │ e       │

julia> dropmissing!(df1, disallowmissing=true);
 julia> df1
2×3 DataFrame
│ Row │ i     │ x     │ y      │
│     │ Int64 │ Int64 │ String │
├─────┼───────┼───────┼────────┤
│ 1   │ 4     │ 2     │ d      │
│ 2   │ 5     │ 1     │ e      │

julia> df2 = copy(df);

julia> dropmissing!(df2, :x);

julia> df2
3×3 DataFrame
│ Row │ i     │ x      │ y       │
│     │ Int64 │ Int64⍰ │ String⍰ │
├─────┼───────┼────────┼─────────┤
│ 1   │ 2     │ 4      │ missing │
│ 2   │ 4     │ 2      │ d       │
│ 3   │ 5     │ 1      │ e       │

julia> df3 = copy(df);

julia> dropmissing!(df3, [:x, :y]);


julia> df3
2×3 DataFrame
│ Row │ i     │ x      │ y       │
│     │ Int64 │ Int64⍰ │ String⍰ │
├─────┼───────┼────────┼─────────┤
│ 1   │ 4     │ 2      │ d       │
│ 2   │ 5     │ 1      │ e       │
```

"""
function dropmissing!(df::AbstractDataFrame,
                      cols::Union{Integer, Symbol, AbstractVector}=1:size(df, 2);
                      disallowmissing::Bool=false)
    deleterows!(df, (!).(completecases(df, cols)))
    if disallowmissing
        disallowmissing!(df, cols)
    else
        Base.depwarn("dropmissing! will change eltype of cols to disallow missing by default. " *
                     "Use dropmissing!(df, cols, disallowmissing=false) to retain missing.", :dropmissing!)
    end
    df
end

"""
    filter(function, df::AbstractDataFrame)

Return a copy of data frame `df` containing only rows for which `function`
returns `true`. The function is passed a `DataFrameRow` as its only argument.

# Examples
```
julia> df = DataFrame(x = [3, 1, 2, 1], y = ["b", "c", "a", "b"])
4×2 DataFrame
│ Row │ x     │ y      │
│     │ Int64 │ String │
├─────┼───────┼────────┤
│ 1   │ 3     │ b      │
│ 2   │ 1     │ c      │
│ 3   │ 2     │ a      │
│ 4   │ 1     │ b      │

julia> filter(row -> row[:x] > 1, df)
2×2 DataFrame
│ Row │ x     │ y      │
│     │ Int64 │ String │
├─────┼───────┼────────┤
│ 1   │ 3     │ b      │
│ 2   │ 2     │ a      │
```
"""
Base.filter(f, df::AbstractDataFrame) = df[collect(f(r)::Bool for r in eachrow(df)), :]

"""
    filter!(function, df::AbstractDataFrame)

Remove rows from data frame `df` for which `function` returns `false`.
The function is passed a `DataFrameRow` as its only argument.

# Examples
```
julia> df = DataFrame(x = [3, 1, 2, 1], y = ["b", "c", "a", "b"])
4×2 DataFrame
│ Row │ x     │ y      │
│     │ Int64 │ String │
├─────┼───────┼────────┤
│ 1   │ 3     │ b      │
│ 2   │ 1     │ c      │
│ 3   │ 2     │ a      │
│ 4   │ 1     │ b      │

julia> filter!(row -> row[:x] > 1, df);

julia> df
2×2 DataFrame
│ Row │ x     │ y      │
│     │ Int64 │ String │
├─────┼───────┼────────┤
│ 1   │ 3     │ b      │
│ 2   │ 2     │ a      │
```
"""
Base.filter!(f, df::AbstractDataFrame) =
    deleterows!(df, findall(collect(!f(r)::Bool for r in eachrow(df))))

function Base.convert(::Type{Matrix}, df::AbstractDataFrame)
    T = reduce(promote_type, eltypes(df))
    convert(Matrix{T}, df)
end
function Base.convert(::Type{Matrix{T}}, df::AbstractDataFrame) where T
    n, p = size(df)
    res = Matrix{T}(undef, n, p)
    idx = 1
    for (name, col) in zip(names(df), columns(df))
        try
            copyto!(res, idx, col)
        catch err
            if err isa MethodError && err.f == convert &&
               !(T >: Missing) && any(ismissing, col)
                error("cannot convert a DataFrame containing missing values to Matrix{$T} (found for column $name)")
            else
                rethrow(err)
            end
        end
        idx += n
    end
    return res
end
Base.Matrix(df::AbstractDataFrame) = Base.convert(Matrix, df)
Base.Matrix{T}(df::AbstractDataFrame) where {T} = Base.convert(Matrix{T}, df)

"""
Indexes of duplicate rows (a row that is a duplicate of a prior row)

```julia
nonunique(df::AbstractDataFrame)
nonunique(df::AbstractDataFrame, cols)
```

**Arguments**

* `df` : the AbstractDataFrame
* `cols` : a column indicator (Symbol, Int, Vector{Symbol}, etc.) specifying the column(s) to compare

**Result**

* `::Vector{Bool}` : indicates whether the row is a duplicate of some
  prior row

See also [`unique`](@ref) and [`unique!`](@ref).

**Examples**

```julia
df = DataFrame(i = 1:10, x = rand(10), y = rand(["a", "b", "c"], 10))
df = vcat(df, df)
nonunique(df)
nonunique(df, 1)
```

"""
function nonunique(df::AbstractDataFrame)
    gslots = row_group_slots(ntuple(i -> df[i], ncol(df)), Val(true))[3]
    # unique rows are the first encountered group representatives,
    # nonunique are everything else
    res = fill(true, nrow(df))
    @inbounds for g_row in gslots
        (g_row > 0) && (res[g_row] = false)
    end
    return res
end

nonunique(df::AbstractDataFrame, cols::Union{Integer, Symbol}) = nonunique(df[[cols]])
nonunique(df::AbstractDataFrame, cols::Any) = nonunique(df[cols])

Base.unique!(df::AbstractDataFrame) = deleterows!(df, findall(nonunique(df)))
Base.unique!(df::AbstractDataFrame, cols::AbstractVector) =
    deleterows!(df, findall(nonunique(df, cols)))
Base.unique!(df::AbstractDataFrame, cols::Union{Integer, Symbol, Colon}) =
    deleterows!(df, findall(nonunique(df, cols)))

# Unique rows of an AbstractDataFrame.
Base.unique(df::AbstractDataFrame) = df[(!).(nonunique(df)), :]
Base.unique(df::AbstractDataFrame, cols::AbstractVector) =
    df[(!).(nonunique(df, cols)), :]
Base.unique(df::AbstractDataFrame, cols::Union{Integer, Symbol, Colon}) =
    df[(!).(nonunique(df, cols)), :]

"""
Delete duplicate rows

```julia
unique(df::AbstractDataFrame)
unique(df::AbstractDataFrame, cols)
unique!(df::AbstractDataFrame)
unique!(df::AbstractDataFrame, cols)
```

**Arguments**

* `df` : the AbstractDataFrame
* `cols` :  column indicator (Symbol, Int, Vector{Symbol}, etc.)
specifying the column(s) to compare.

**Result**

* `::AbstractDataFrame` : the updated version of `df` with unique rows.
When `cols` is specified, the return DataFrame contains complete rows,
retaining in each case the first instance for which `df[cols]` is unique.

See also [`nonunique`](@ref).

**Examples**

```julia
df = DataFrame(i = 1:10, x = rand(10), y = rand(["a", "b", "c"], 10))
df = vcat(df, df)
unique(df)   # doesn't modify df
unique(df, 1)
unique!(df)  # modifies df
```

"""
(unique, unique!)

function without(df::AbstractDataFrame, icols::Vector{<:Integer})
    newcols = setdiff(1:ncol(df), icols)
    df[newcols]
end
without(df::AbstractDataFrame, i::Int) = without(df, [i])
without(df::AbstractDataFrame, c::Any) = without(df, index(df)[c])

##############################################################################
##
## Hcat / vcat
##
##############################################################################

# hcat's first argument must be an AbstractDataFrame
# or AbstractVector if the second argument is AbstractDataFrame
# Trailing arguments (currently) may also be vectors.

# hcat! is defined in DataFrames/DataFrames.jl
# Its first argument (currently) must be a DataFrame.

# catch-all to cover cases where indexing returns a DataFrame and copy doesn't

Base.hcat(df::AbstractDataFrame, x; makeunique::Bool=false) =
    hcat!(copy(df), x, makeunique=makeunique)
Base.hcat(x, df::AbstractDataFrame; makeunique::Bool=false) =
    hcat!(x, df, makeunique=makeunique)
Base.hcat(df1::AbstractDataFrame, df2::AbstractDataFrame; makeunique::Bool=false) =
    hcat!(copy(df1), df2, makeunique=makeunique)
Base.hcat(df::AbstractDataFrame, x, y...; makeunique::Bool=false) =
    hcat!(hcat(df, x, makeunique=makeunique), y..., makeunique=makeunique)
Base.hcat(df1::AbstractDataFrame, df2::AbstractDataFrame, dfn::AbstractDataFrame...;
          makeunique::Bool=false) =
    hcat!(hcat(df1, df2, makeunique=makeunique), dfn..., makeunique=makeunique)

"""
    vcat(dfs::AbstractDataFrame...)

Vertically concatenate `AbstractDataFrames`.

Column names in all passed data frames must be the same, but they can have
different order. In such cases the order of names in the first passed
`DataFrame` is used.

# Example
```jldoctest
julia> df1 = DataFrame(A=1:3, B=1:3);

julia> df2 = DataFrame(A=4:6, B=4:6);

julia> vcat(df1, df2)
6×2 DataFrame
│ Row │ A     │ B     │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 1     │ 1     │
│ 2   │ 2     │ 2     │
│ 3   │ 3     │ 3     │
│ 4   │ 4     │ 4     │
│ 5   │ 5     │ 5     │
│ 6   │ 6     │ 6     │
```
"""
Base.vcat(df::AbstractDataFrame) = df
Base.vcat(dfs::AbstractDataFrame...) = _vcat(collect(dfs))
function _vcat(dfs::AbstractVector{<:AbstractDataFrame})
    isempty(dfs) && return DataFrame()
    allheaders = map(names, dfs)
    uniqueheaders = unique(allheaders)
    unionunique = union(uniqueheaders...)
    intersectunique = intersect(uniqueheaders...)
    coldiff = setdiff(unionunique, intersectunique)

    if !isempty(coldiff)
        # if any DataFrames are a full superset of names, skip them
        filter!(u -> Set(u) != Set(unionunique), uniqueheaders)
        estrings = Vector{String}(undef, length(uniqueheaders))
        for (i, u) in enumerate(uniqueheaders)
            matching = findall(h -> u == h, allheaders)
            headerdiff = setdiff(coldiff, u)
            cols = join(headerdiff, ", ", " and ")
            args = join(matching, ", ", " and ")
            estrings[i] = "column(s) $cols are missing from argument(s) $args"
        end
        throw(ArgumentError(join(estrings, ", ", ", and ")))
    end

    header = allheaders[1]
    length(header) == 0 && return DataFrame()
    cols = Vector{AbstractVector}(undef, length(header))
    for (i, name) in enumerate(header)
        data = [df[name] for df in dfs]
        lens = map(length, data)
        T = mapreduce(eltype, promote_type, data)
        cols[i] = Tables.allocatecolumn(T, sum(lens))
        offset = 1
        for j in 1:length(data)
            copyto!(cols[i], offset, data[j])
            offset += lens[j]
        end
    end
    return DataFrame(cols, header)
end

##############################################################################
##
## repeat
##
##############################################################################

"""
    repeat(df::AbstractDataFrame; inner::Integer = 1, outer::Integer = 1)

Construct a data frame by repeating rows in `df`. `inner` specifies how many
times each row is repeated, and `outer` specifies how many times the full set
of rows is repeated.

# Example
```jldoctest
julia> df = DataFrame(a = 1:2, b = 3:4)
2×2 DataFrame
│ Row │ a     │ b     │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 1     │ 3     │
│ 2   │ 2     │ 4     │

julia> repeat(df, inner = 2, outer = 3)
12×2 DataFrame
│ Row │ a     │ b     │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 1     │ 3     │
│ 2   │ 1     │ 3     │
│ 3   │ 2     │ 4     │
│ 4   │ 2     │ 4     │
│ 5   │ 1     │ 3     │
│ 6   │ 1     │ 3     │
│ 7   │ 2     │ 4     │
│ 8   │ 2     │ 4     │
│ 9   │ 1     │ 3     │
│ 10  │ 1     │ 3     │
│ 11  │ 2     │ 4     │
│ 12  │ 2     │ 4     │
```
"""
Base.repeat(df::AbstractDataFrame; inner::Integer = 1, outer::Integer = 1) =
    mapcols(x -> repeat(x, inner = inner, outer = outer), df)

"""
    repeat(df::AbstractDataFrame, count::Integer)

Construct a data frame by repeating each row in `df` the number of times
specified by `count`.

# Example
```jldoctest
julia> df = DataFrame(a = 1:2, b = 3:4)
2×2 DataFrame
│ Row │ a     │ b     │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 1     │ 3     │
│ 2   │ 2     │ 4     │

julia> repeat(df, 2)
4×2 DataFrame
│ Row │ a     │ b     │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 1     │ 3     │
│ 2   │ 2     │ 4     │
│ 3   │ 1     │ 3     │
│ 4   │ 2     │ 4     │
```
"""
Base.repeat(df::AbstractDataFrame, count::Integer) =
    mapcols(x -> repeat(x, count), df)

##############################################################################
##
## Hashing
##
##############################################################################

const hashdf_seed = UInt == UInt32 ? 0xfd8bb02e : 0x6215bada8c8c46de

function Base.hash(df::AbstractDataFrame, h::UInt)
    h += hashdf_seed
    h += hash(size(df))
    for i in 1:size(df, 2)
        h = hash(df[i], h)
    end
    return h
end

Base.parent(adf::AbstractDataFrame) = adf
Base.parentindices(adf::AbstractDataFrame) = axes(adf)

## Documentation for methods defined elsewhere

# nrow, ncol
"""
Number of rows or columns in an AbstractDataFrame

```julia
nrow(df::AbstractDataFrame)
ncol(df::AbstractDataFrame)
```

**Arguments**

* `df` : the AbstractDataFrame

**Result**

* `::AbstractDataFrame` : the updated version

See also [`size`](@ref).

NOTE: these functions may be depreciated for `size`.

**Examples**

```julia
df = DataFrame(i = 1:10, x = rand(10), y = rand(["a", "b", "c"], 10))
size(df)
nrow(df)
ncol(df)
```

"""
