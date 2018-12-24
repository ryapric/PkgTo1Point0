"""
    GroupedDataFrame

The result of a `groupby` operation on an AbstractDataFrame; a
view into the AbstractDataFrame grouped by rows.

Not meant to be constructed directly, see `groupby`.
"""
struct GroupedDataFrame{T<:AbstractDataFrame}
    parent::T
    cols::Vector{Int}    # columns used for grouping
    idx::Vector{Int}     # indexing vector when grouped by the given columns
    starts::Vector{Int}  # starts of groups
    ends::Vector{Int}    # ends of groups
end

#
# Split
#

"""
A view of an AbstractDataFrame split into row groups

```julia
groupby(d::AbstractDataFrame, cols; sort = false, skipmissing = false)
groupby(cols; sort = false, skipmissing = false)
```

### Arguments

* `d` : an AbstractDataFrame to split (optional, see [Returns](#returns))
* `cols` : data table columns to group by
* `sort`: whether to sort rows according to the values of the grouping columns `cols`
* `skipmissing`: whether to skip rows with `missing` values in one of the grouping columns `cols`

### Returns

A `GroupedDataFrame` : a grouped view into `d`

### Details

An iterator over a `GroupedDataFrame` returns a `SubDataFrame` view
for each grouping into `d`. A `GroupedDataFrame` also supports
indexing by groups, `map` (which applies a function to each group)
and `combine` (which applies a function to each group
and combines the result into a data frame).

See the following for additional split-apply-combine operations:

* `by` : split-apply-combine using functions
* `aggregate` : split-apply-combine; applies functions in the form of a cross product
* `colwise` : apply a function to each column in an `AbstractDataFrame` or `GroupedDataFrame`
* `map` : apply a function to each group of a `GroupedDataFrame` (without combining)
* `combine` : combine a `GroupedDataFrame`, optionally applying a function to each group

### Examples

```julia
df = DataFrame(a = repeat([1, 2, 3, 4], outer=[2]),
               b = repeat([2, 1], outer=[4]),
               c = randn(8))
gd = groupby(df, :a)
gd[1]
last(gd)
vcat([g[:b] for g in gd]...)
for g in gd
    println(g)
end
```

"""
function groupby(df::AbstractDataFrame, cols::AbstractVector;
                 sort::Bool = false, skipmissing::Bool = false)
    intcols = index(df)[cols]
    sdf = df[intcols]
    df_groups = group_rows(sdf, false, sort, skipmissing)
    GroupedDataFrame(df, intcols, df_groups.rperm,
                     df_groups.starts, df_groups.stops)
end
groupby(d::AbstractDataFrame, cols;
        sort::Bool = false, skipmissing::Bool = false) =
    groupby(d, [cols], sort = sort, skipmissing = skipmissing)

function Base.iterate(gd::GroupedDataFrame, i=1)
    if i > length(gd.starts)
        nothing
    else
        (view(gd.parent, gd.idx[gd.starts[i]:gd.ends[i]], :), i+1)
    end
end

Base.length(gd::GroupedDataFrame) = length(gd.starts)
Compat.lastindex(gd::GroupedDataFrame) = length(gd.starts)
Base.first(gd::GroupedDataFrame) = gd[1]
Base.last(gd::GroupedDataFrame) = gd[end]

Base.getindex(gd::GroupedDataFrame, idx::Integer) =
    view(gd.parent, gd.idx[gd.starts[idx]:gd.ends[idx]], :)
Base.getindex(gd::GroupedDataFrame, idxs::AbstractArray) =
    GroupedDataFrame(gd.parent, gd.cols, gd.idx, gd.starts[idxs], gd.ends[idxs])
Base.getindex(gd::GroupedDataFrame, idxs::Colon) =
    GroupedDataFrame(gd.parent, gd.cols, gd.idx, gd.starts, gd.ends)

function Base.:(==)(gd1::GroupedDataFrame, gd2::GroupedDataFrame)
    gd1.cols == gd2.cols &&
        length(gd1) == length(gd2) &&
        all(x -> ==(x...), zip(gd1, gd2))
end

function Base.isequal(gd1::GroupedDataFrame, gd2::GroupedDataFrame)
    isequal(gd1.cols, gd2.cols) &&
        isequal(length(gd1), length(gd2)) &&
        all(x -> isequal(x...), zip(gd1, gd2))
end

Base.names(gd::GroupedDataFrame) = names(gd.parent)
_names(gd::GroupedDataFrame) = _names(gd.parent)

"""
    map(cols => f, gd::GroupedDataFrame)
    map(f, gd::GroupedDataFrame)

Apply a function to each group of rows and return a `GroupedDataFrame`.

If the first argument is a `cols => f` pair, `cols` must be a column name or index, or
a vector or tuple thereof, and `f` must be a callable. If `cols` is a single column index,
`f` is called with a `SubArray` view into that column for each group; else, `f` is called
with a named tuple holding `SubArray` views into these columns.

If the first argument is a vector, tuple or named tuple of such pairs, each pair is
handled as described above. If a named tuple, field names are used to name
each generated column.

If the first argument is a callable, it is passed a `SubDataFrame` view for each group,
and the returned `DataFrame` then consists of the returned rows plus the grouping columns.
Note that this second form is much slower than the first one due to type instability.

`f` can return a single value, a row or multiple rows. The type of the returned value
determines the shape of the resulting data frame:
- A single value gives a data frame with a single column and one row per group.
- A named tuple of single values or a `DataFrameRow` gives a data frame with one column
  for each field and one row per group.
- A vector gives a data frame with a single column and as many rows
  for each group as the length of the returned vector for that group.
- A data frame, a named tuple of vectors or a matrix gives a data frame
  with the same columns and as many rows for each group as the rows returned for that group.

As a special case, if a tuple or vector of pairs is passed as the first argument, each function
is required to return a single value or vector, which will produce each a separate column.

In all cases, the resulting `GroupedDataFrame` contains all the grouping columns in addition
to those listed above. Column names are automatically generated when necessary: for functions
operating on a single column and returning a single value or vector, the function name is
appended to the input column name; for other functions, columns are called `x1`, `x2`
and so on.

Note that `f` must always return the same type of object for
all groups, and (if a named tuple or data frame) with the same fields or columns.
Due to type instability, returning a single value or a named tuple is dramatically
faster than returning a data frame.

### Examples

```jldoctest
julia> df = DataFrame(a = repeat([1, 2, 3, 4], outer=[2]),
                      b = repeat([2, 1], outer=[4]),
                      c = 1:8);

julia> gd = groupby(df, :a);

julia> map(:c => sum, gd)
GroupedDataFrame{DataFrame} with 4 groups based on key: :a
First Group: 1 row
│ Row │ a     │ c_sum │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 1     │ 6     │
⋮
Last Group: 1 row
│ Row │ a     │ c_sum │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 4     │ 12    │

julia> map(df -> sum(df.c), gd) # Slower variant
GroupedDataFrame{DataFrame} with 4 groups based on key: :a
First Group: 1 row
│ Row │ a     │ x1    │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 1     │ 6     │
⋮
Last Group: 1 row
│ Row │ a     │ x1    │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 4     │ 12    │
```

See [`by`](@ref) for more examples.

### See also

`combine(f, gd)` returns a `DataFrame` rather than a `GroupedDataFrame`

"""
function Base.map(f::Any, gd::GroupedDataFrame)
    if length(gd) > 0
        idx, valscat = _combine(f, gd)
        parent = hcat!(gd.parent[idx, gd.cols], valscat, makeunique=true)
        starts = Vector{Int}(undef, length(gd))
        ends = Vector{Int}(undef, length(gd))
        starts[1] = 1
        j = 2
        @inbounds for i in 2:length(idx)
            if idx[i] != idx[i-1]
                starts[j] = i
                ends[j-1] = i - 1
                j += 1
            end
        end
        # In case some groups have to be dropped
        resize!(starts, j-1)
        resize!(ends, j-1)
        ends[end] = length(idx)
        return GroupedDataFrame(parent, gd.cols, collect(1:length(idx)), starts, ends)
    else
        return GroupedDataFrame(parent, gd.cols, Int[], Int[], Int[])
    end
end

"""
    combine(gd::GroupedDataFrame)
    combine(gd::GroupedDataFrame, cols => f...)
    combine(gd::GroupedDataFrame; (colname = cols => f)...)
    combine(gd::GroupedDataFrame, f)
    combine(f, gd::GroupedDataFrame)

Transform a `GroupedDataFrame` into a `DataFrame`.

If the last argument(s) consist(s) in one or more `cols => f` pair(s), or if
`colname = cols => f` keyword arguments are provided, `cols` must be
a column name or index, or a vector or tuple thereof, and `f` must be a callable.
A pair or a (named) tuple of pairs can also be provided as the first or last argument.
If `cols` is a single column index, `f` is called with a `SubArray` view into that
column for each group; else, `f` is called with a named tuple holding `SubArray`
views into these columns.

If the last argument is a callable `f`, it is passed a `SubDataFrame` view for each group,
and the returned `DataFrame` then consists of the returned rows plus the grouping columns.
Note that this second form is much slower than the first one due to type instability.
A method is defined with `f` as the first argument, so do-block
notation can be used.

`f` can return a single value, a row or multiple rows. The type of the returned value
determines the shape of the resulting data frame:
- A single value gives a data frame with a single column and one row per group.
- A named tuple of single values or a `DataFrameRow` gives a data frame with one column
  for each field and one row per group.
- A vector gives a data frame with a single column and as many rows
  for each group as the length of the returned vector for that group.
- A data frame, a named tuple of vectors or a matrix gives a data frame
  with the same columns and as many rows for each group as the rows returned for that group.

As a special case, if a tuple or vector of pairs is passed as the first argument, each function
is required to return a single value or vector, which will produce each a separate column.

In all cases, the resulting data frame contains all the grouping columns in addition
to those listed above. Column names are automatically generated when necessary: for functions
operating on a single column and returning a single value or vector, the function name is
appended to the input column name; for other functions, columns are called `x1`, `x2`
and so on.

Note that `f` must always return the same type of object for
all groups, and (if a named tuple or data frame) with the same fields or columns.
Due to type instability, returning a single value or a named tuple is dramatically
faster than returning a data frame.

The resulting data frame will be sorted if `sort=true` was passed to the [`groupby`](@ref)
call from which `gd` was constructed. Otherwise, ordering of rows is undefined.

### Examples

```jldoctest
julia> df = DataFrame(a = repeat([1, 2, 3, 4], outer=[2]),
                      b = repeat([2, 1], outer=[4]),
                      c = 1:8);

julia> gd = groupby(df, :a);

julia> combine(gd, :c => sum)
4×2 DataFrame
│ Row │ a     │ c_sum │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 1     │ 6     │
│ 2   │ 2     │ 8     │
│ 3   │ 3     │ 10    │
│ 4   │ 4     │ 12    │

julia> combine(:c => sum, gd)
4×2 DataFrame
│ Row │ a     │ c_sum │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 1     │ 6     │
│ 2   │ 2     │ 8     │
│ 3   │ 3     │ 10    │
│ 4   │ 4     │ 12    │

julia> combine(df -> sum(df.c), gd) # Slower variant
4×2 DataFrame
│ Row │ a     │ x1    │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 1     │ 6     │
│ 2   │ 2     │ 8     │
│ 3   │ 3     │ 10    │
│ 4   │ 4     │ 12    │
```

See [`by`](@ref) for more examples.

### See also

[`by(f, df, cols)`](@ref) is a shorthand for `combine(f, groupby(df, cols))`.

[`map`](@ref): `combine(f, groupby(df, cols))` is a more efficient equivalent
of `combine(map(f, groupby(df, cols)))`.

"""
function combine(f::Any, gd::GroupedDataFrame)
    if length(gd) > 0
        idx, valscat = _combine(f, gd)
        return hcat!(gd.parent[idx, gd.cols], valscat, makeunique=true)
    else
        return similar(gd.parent[gd.cols], 0)
    end
end
combine(gd::GroupedDataFrame, f::Any) = combine(f, gd)
combine(gd::GroupedDataFrame, f::Pair...) = combine(f, gd)
combine(gd::GroupedDataFrame; f...) =
    isempty(f) ? combine(identity, gd) : combine(values(f), gd)

# Wrapping automatically adds column names when the value returned
# by the user-provided function lacks them
wrap(x::Union{AbstractDataFrame, NamedTuple, DataFrameRow}) = x
wrap(x::AbstractMatrix) =
    NamedTuple{Tuple(gennames(size(x, 2)))}(Tuple(view(x, :, i) for i in 1:size(x, 2)))
wrap(x::Any) = (x1=x,)

function do_call(f::Any, gd::GroupedDataFrame, incols::AbstractVector, i::Integer)
    idx = gd.idx[gd.starts[i]:gd.ends[i]]
    f(view(incols, idx))
end
function do_call(f::Any, gd::GroupedDataFrame, incols::NamedTuple, i::Integer)
    idx = gd.idx[gd.starts[i]:gd.ends[i]]
    f(map(c -> view(c, idx), incols))
end
do_call(f::Any, gd::GroupedDataFrame, incols::Nothing, i::Integer) =
    f(gd[i])

_nrow(df::AbstractDataFrame) = nrow(df)
_nrow(x::NamedTuple{<:Any, <:Tuple{Vararg{AbstractVector}}}) =
    isempty(x) ? 0 : length(x[1])
_ncol(df::AbstractDataFrame) = ncol(df)
_ncol(x::Union{NamedTuple, DataFrameRow}) = length(x)

function gen_fun(::Type{NT}, f2) where NT
    get_val(::Val{T}) where {T} = T

    function(incols)
        tup = map(f2) do p
            nms = get_val(first(p))
            if nms isa Tuple
                res = last(p)(NamedTuple{nms}(map(c -> incols[c], nms)))
            else
                res = last(p)(incols[nms])
            end
            if res isa Union{AbstractDataFrame, NamedTuple, DataFrameRow, AbstractMatrix}
                throw(ArgumentError("a single value or vector result is required when passing " *
                                    "a vector or tuple of functions (got $(typeof(res)))"))
            end
            res
        end
        NT(tup)
    end
end

function _combine(f::Union{AbstractVector{<:Pair}, Tuple{Vararg{Pair}},
                           NamedTuple{<:Any, <:Tuple{Vararg{Pair}}}},
                  gd::GroupedDataFrame)
    idxs = (first(p) isa Union{Integer, Symbol} ?
            index(gd.parent)[first(p)] :
            index(gd.parent)[collect(first(p))] for p in f)
    incols = [names(gd.parent)[idx] for idx in idxs]
    allcols = collect(reduce(union, (nam isa Symbol ? (nam,) : nam for nam in incols)))
    f2 = ntuple(length(f)) do i
        nms = incols[i]
        (nms isa AbstractArray ? Val(Tuple(nms)) : Val(nms)) => last(f[i])
    end
    # Use temporary names for columns, and rename after the fact where appropriate
    NT = NamedTuple{Tuple(gennames(length(f2)))}
    fun = gen_fun(NT, f2)
    idx, valscat = _combine(allcols => fun, gd)
    if f isa NamedTuple
        nams = collect(propertynames(f))
    else
        nams = names(valscat)
        for i in 1:ncol(valscat)
            if f[i] isa Pair{<:Union{Symbol,Integer}}
                 nams[i] = Symbol(names(gd.parent)[index(gd.parent)[first(f[i])]],
                                  '_', funname(last(f[i])))
            end
        end
    end
    names!(valscat, nams)
    idx, valscat
end

function _combine(f::Any, gd::GroupedDataFrame)
    if f isa Pair{<:Union{Symbol,Integer}}
        incols = gd.parent[first(f)]
        fun = last(f)
    elseif f isa Pair
        df = gd.parent[collect(first(f))]
        incols = NamedTuple{Tuple(names(df))}(columns(df))
        fun = last(f)
    else
        incols = nothing
        fun = f
    end
    firstres = do_call(fun, gd, incols, 1)
    idx, valscat = _combine(wrap(firstres), fun, gd, incols)
    if f isa Pair{<:Union{Symbol,Integer}} &&
       !isa(firstres, Union{AbstractDataFrame, NamedTuple, DataFrameRow, AbstractMatrix})
        nam = Symbol(names(gd.parent)[index(gd.parent)[first(f)]],
                     '_', funname(fun))
        names!(valscat, [nam])
    end
    return idx, valscat
end

function _combine(first::Union{NamedTuple, DataFrameRow, AbstractDataFrame},
                  f::Any, gd::GroupedDataFrame,
                  incols::Union{Nothing, AbstractVector, NamedTuple})
    if first isa AbstractDataFrame
        n = 0
        eltys = eltypes(first)
    elseif first isa NamedTuple{<:Any, <:Tuple{Vararg{AbstractVector}}}
        n = 0
        eltys = map(eltype, first)
    elseif first isa DataFrameRow
        n = length(gd)
        eltys = eltypes(parent(first))
    else # NamedTuple giving a single row
        n = length(gd)
        eltys = map(typeof, first)
        if any(x -> x <: AbstractVector, eltys)
            throw(ArgumentError("mixing single values and vectors in a (named) tuple is not allowed"))
        end
    end
    idx = Vector{Int}(undef, n)
    initialcols = ntuple(i -> Tables.allocatecolumn(eltys[i], n), _ncol(first))
    outcols = _combine!(first, initialcols, idx, 1, 1, f, gd, incols,
                        tuple(propertynames(first)...))
    valscat = DataFrame(collect(outcols), collect(Symbol, propertynames(first)))
    idx, valscat
end

function fill_row!(row, outcols::NTuple{N, AbstractVector},
                   i::Integer, colstart::Integer,
                   colnames::NTuple{N, Symbol}) where N
    if !isa(row, Union{NamedTuple, DataFrameRow})
        throw(ArgumentError("return value must not change its kind " *
                            "(single row or variable number of rows) across groups"))
    elseif _ncol(row) != N
        throw(ArgumentError("return value must have the same number of columns " *
                            "for all groups (got $N and $(length(row)))"))
    end
    @inbounds for j in colstart:length(outcols)
        col = outcols[j]
        cn = colnames[j]
        local val
        try
            val = row[cn]
        catch
            throw(ArgumentError("return value must have the same column names " *
                                "for all groups (got $colnames and $(propertynames(row)))"))
        end
        S = typeof(val)
        T = eltype(col)
        if S <: T || promote_type(S, T) <: T
            col[i] = val
        else
            return j
        end
    end
    return nothing
end

function _combine!(first::Union{NamedTuple, DataFrameRow}, outcols::NTuple{N, AbstractVector},
                   idx::Vector{Int}, rowstart::Integer, colstart::Integer,
                   f::Any, gd::GroupedDataFrame,
                   incols::Union{Nothing, AbstractVector, NamedTuple},
                   colnames::NTuple{N, Symbol}) where N
    len = length(gd)
    # Handle first group
    j = fill_row!(first, outcols, rowstart, colstart, colnames)
    @assert j === nothing # eltype is guaranteed to match
    idx[rowstart] = gd.idx[gd.starts[rowstart]]
    # Handle remaining groups
    @inbounds for i in rowstart+1:len
        row = wrap(do_call(f, gd, incols, i))
        j = fill_row!(row, outcols, i, 1, colnames)
        if j !== nothing # Need to widen column type
            local newcols
            let i = i, j = j, outcols=outcols, row=row # Workaround for julia#15276
                newcols = ntuple(length(outcols)) do k
                    S = typeof(row[k])
                    T = eltype(outcols[k])
                    U = promote_type(S, T)
                    if S <: T || U <: T
                        outcols[k]
                    else
                        copyto!(Tables.allocatecolumn(U, length(outcols[k])),
                                1, outcols[k], 1, k >= j ? i-1 : i)
                    end
                end
            end
            return _combine!(row, newcols, idx, i, j, f, gd, incols, colnames)
        end
        idx[i] = gd.idx[gd.starts[i]]
    end
    outcols
end

# This needs to be in a separate function
# to work around a crash due to JuliaLang/julia#29430
if VERSION >= v"1.1.0-DEV.723"
    @inline function do_append!(do_it, col, vals)
        do_it && append!(col, vals)
        return do_it
    end
else
    @noinline function do_append!(do_it, col, vals)
        do_it && append!(col, vals)
        return do_it
    end
end

function append_rows!(rows, outcols::NTuple{N, AbstractVector},
                      colstart::Integer, colnames::NTuple{N, Symbol}) where N
    if !isa(rows, Union{AbstractDataFrame, NamedTuple{<:Any, <:Tuple{Vararg{AbstractVector}}}})
        throw(ArgumentError("return value must not change its kind " *
                            "(single row or variable number of rows) across groups"))
    elseif _ncol(rows) != N
        throw(ArgumentError("return value must have the same number of columns " *
                            "for all groups (got $N and $(_ncol(rows)))"))
    end
    @inbounds for j in colstart:length(outcols)
        col = outcols[j]
        cn = colnames[j]
        local vals
        try
            vals = rows[cn]
        catch
            throw(ArgumentError("return value must have the same column names " *
                                "for all groups (got $(Tuple(colnames)) and $(Tuple(names(rows))))"))
        end
        S = eltype(vals)
        T = eltype(col)
        if !do_append!(S <: T || promote_type(S, T) <: T, col, vals)
            return j
        end
    end
    return nothing
end

function _combine!(first::Union{AbstractDataFrame,
                                NamedTuple{<:Any, <:Tuple{Vararg{AbstractVector}}}},
                   outcols::NTuple{N, AbstractVector},
                   idx::Vector{Int}, rowstart::Integer, colstart::Integer,
                   f::Any, gd::GroupedDataFrame,
                   incols::Union{Nothing, AbstractVector, NamedTuple},
                   colnames::NTuple{N, Symbol}) where N
    len = length(gd)
    # Handle first group
    j = append_rows!(first, outcols, colstart, colnames)
    @assert j === nothing # eltype is guaranteed to match
    append!(idx, Iterators.repeated(gd.idx[gd.starts[rowstart]], _nrow(first)))
    # Handle remaining groups
    @inbounds for i in rowstart+1:len
        rows = wrap(do_call(f, gd, incols, i))
        j = append_rows!(rows, outcols, 1, colnames)
        if j !== nothing # Need to widen column type
            local newcols
            let i = i, j = j, outcols=outcols, rows=rows # Workaround for julia#15276
                newcols = ntuple(length(outcols)) do k
                    S = eltype(rows[k])
                    T = eltype(outcols[k])
                    U = promote_type(S, T)
                    if S <: T || U <: T
                        outcols[k]
                    else
                        copyto!(Tables.allocatecolumn(U, length(outcols[k])), outcols[k])
                    end
                end
            end
            return _combine!(rows, newcols, idx, i, j, f, gd, incols, colnames)
        end
        append!(idx, Iterators.repeated(gd.idx[gd.starts[i]], _nrow(rows)))
    end
    outcols
end

"""
Apply a function to each column in an AbstractDataFrame or
GroupedDataFrame

```julia
colwise(f, d)
```

### Arguments

* `f` : a function or vector of functions
* `d` : an AbstractDataFrame of GroupedDataFrame

### Returns

* various, depending on the call

### Examples

```julia
df = DataFrame(a = repeat([1, 2, 3, 4], outer=[2]),
               b = repeat([2, 1], outer=[4]),
               c = randn(8))
colwise(sum, df)
colwise([sum, length], df)
colwise((minimum, maximum), df)
colwise(sum, groupby(df, :a))
```

"""
colwise(f, d::AbstractDataFrame) = [f(d[i]) for i in 1:ncol(d)]

# apply several functions to each column in a data frame
colwise(fns::Union{AbstractVector, Tuple}, d::AbstractDataFrame) = [f(d[i]) for f in fns, i in 1:ncol(d)]
colwise(f, gd::GroupedDataFrame) = [colwise(f, g) for g in gd]

"""
    by(d::AbstractDataFrame, keys, cols => f...; sort::Bool = false)
    by(d::AbstractDataFrame, keys; (colname = cols => f)..., sort::Bool = false)
    by(d::AbstractDataFrame, keys, f; sort::Bool = false)
    by(f, d::AbstractDataFrame, keys; sort::Bool = false)

Split-apply-combine in one step: apply `f` to each grouping in `d`
based on grouping columns `keys`, and return a `DataFrame`.

`keys` can be either a single column index, or a vector thereof.

If the last argument(s) consist(s) in one or more `cols => f` pair(s), or if
`colname = cols => f` keyword arguments are provided, `cols` must be
a column name or index, or a vector or tuple thereof, and `f` must be a callable.
A pair or a (named) tuple of pairs can also be provided as the first or last argument.
If `cols` is a single column index, `f` is called with a `SubArray` view into that
column for each group; else, `f` is called with a named tuple holding `SubArray`
views into these columns.

If the last argument is a callable `f`, it is passed a `SubDataFrame` view for each group,
and the returned `DataFrame` then consists of the returned rows plus the grouping columns.
Note that this second form is much slower than the first one due to type instability.
A method is defined with `f` as the first argument, so do-block
notation can be used.

`f` can return a single value, a row or multiple rows. The type of the returned value
determines the shape of the resulting data frame:
- A single value gives a data frame with a single column and one row per group.
- A named tuple of single values or a `DataFrameRow` gives a data frame with one column
  for each field and one row per group.
- A vector gives a data frame with a single column and as many rows
  for each group as the length of the returned vector for that group.
- A data frame, a named tuple of vectors or a matrix gives a data frame
  with the same columns and as many rows for each group as the rows returned for that group.

As a special case, if multiple pairs are passed as last arguments, each function
is required to return a single value or vector, which will produce each a separate column.

In all cases, the resulting data frame contains all the grouping columns in addition
to those listed above. Column names are automatically generated when necessary: for functions
operating on a single column and returning a single value or vector, the function name is
appended to the input colummn name; for other functions, columns are called `x1`, `x2`
and so on.

Note that `f` must always return the same type of object for
all groups, and (if a named tuple or data frame) with the same fields or columns.
Due to type instability, returning a single value or a named tuple is dramatically
faster than returning a data frame.

The resulting data frame will be sorted on `keys` if `sort=true`.
Otherwise, ordering of rows is undefined.

`by(d, cols, f)` is equivalent to `combine(f, groupby(d, cols))` and to the
less efficient `combine(map(f, groupby(d, cols)))`.

### Examples

```jldoctest
julia> df = DataFrame(a = repeat([1, 2, 3, 4], outer=[2]),
                      b = repeat([2, 1], outer=[4]),
                      c = 1:8);

julia> by(df, :a, :c => sum)
4×2 DataFrame
│ Row │ a     │ c_sum │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 1     │ 6     │
│ 2   │ 2     │ 8     │
│ 3   │ 3     │ 10    │
│ 4   │ 4     │ 12    │

julia> by(df, :a, d -> sum(d.c)) # Slower variant
4×2 DataFrame
│ Row │ a     │ x1    │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 1     │ 6     │
│ 2   │ 2     │ 8     │
│ 3   │ 3     │ 10    │
│ 4   │ 4     │ 12    │

julia> by(df, :a) do d # do syntax for the slower variant
           sum(d.c)
       end
4×2 DataFrame
│ Row │ a     │ x1    │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 1     │ 6     │
│ 2   │ 2     │ 8     │
│ 3   │ 3     │ 10    │
│ 4   │ 4     │ 12    │

julia> by(df, :a, :c => x -> 2 .* x)
8×2 DataFrame
│ Row │ a     │ c_function │
│     │ Int64 │ Int64      │
├─────┼───────┼────────────┤
│ 1   │ 1     │ 2          │
│ 2   │ 1     │ 10         │
│ 3   │ 2     │ 4          │
│ 4   │ 2     │ 12         │
│ 5   │ 3     │ 6          │
│ 6   │ 3     │ 14         │
│ 7   │ 4     │ 8          │
│ 8   │ 4     │ 16         │

julia> by(df, :a, c_sum = :c => sum, c_sum2 = :c => x -> sum(x.^2))
4×3 DataFrame
│ Row │ a     │ c_sum │ c_sum2 │
│     │ Int64 │ Int64 │ Int64  │
├─────┼───────┼───────┼────────┤
│ 1   │ 1     │ 6     │ 26     │
│ 2   │ 2     │ 8     │ 40     │
│ 3   │ 3     │ 10    │ 58     │
│ 4   │ 4     │ 12    │ 80     │

julia> by(df, :a, (:b, :c) => x -> (minb = minimum(x.b), sumc = sum(x.c)))
4×3 DataFrame
│ Row │ a     │ minb  │ sumc  │
│     │ Int64 │ Int64 │ Int64 │
├─────┼───────┼───────┼───────┤
│ 1   │ 1     │ 2     │ 6     │
│ 2   │ 2     │ 1     │ 8     │
│ 3   │ 3     │ 2     │ 10    │
│ 4   │ 4     │ 1     │ 12    │
```

"""
by(d::AbstractDataFrame, cols::Any, f::Any; sort::Bool = false) =
    combine(f, groupby(d, cols, sort = sort))
by(f::Any, d::AbstractDataFrame, cols::Any; sort::Bool = false) =
    by(d, cols, f, sort = sort)
by(d::AbstractDataFrame, cols::Any, f::Pair; sort::Bool = false) =
    combine(f, groupby(d, cols, sort = sort))
by(d::AbstractDataFrame, cols::Any, f::Pair...; sort::Bool = false) =
    combine(f, groupby(d, cols, sort = sort))
by(d::AbstractDataFrame, cols::Any; sort::Bool = false, f...) =
    combine(values(f), groupby(d, cols, sort = sort))

#
# Aggregate convenience functions
#

# Applies a set of functions over a DataFrame, in the from of a cross-product
"""
Split-apply-combine that applies a set of functions over columns of an
AbstractDataFrame or GroupedDataFrame

```julia
aggregate(d::AbstractDataFrame, cols, fs)
aggregate(gd::GroupedDataFrame, fs)
```

### Arguments

* `d` : an AbstractDataFrame
* `gd` : a GroupedDataFrame
* `cols` : a column indicator (Symbol, Int, Vector{Symbol}, etc.)
* `fs` : a function or vector of functions to be applied to vectors
  within groups; expects each argument to be a column vector

Each `fs` should return a value or vector. All returns must be the
same length.

### Returns

* `::DataFrame`

### Examples

```julia
using Statistics
df = DataFrame(a = repeat([1, 2, 3, 4], outer=[2]),
               b = repeat([2, 1], outer=[4]),
               c = randn(8))
aggregate(df, :a, sum)
aggregate(df, :a, [sum, x->mean(skipmissing(x))])
aggregate(groupby(df, :a), [sum, x->mean(skipmissing(x))])
```

"""
aggregate(d::AbstractDataFrame, fs::Any; sort::Bool=false) =
    aggregate(d, [fs], sort=sort)
function aggregate(d::AbstractDataFrame, fs::AbstractVector; sort::Bool=false)
    headers = _makeheaders(fs, _names(d))
    _aggregate(d, fs, headers, sort)
end

# Applies aggregate to non-key cols of each SubDataFrame of a GroupedDataFrame
aggregate(gd::GroupedDataFrame, f::Any; sort::Bool=false) = aggregate(gd, [f], sort=sort)
function aggregate(gd::GroupedDataFrame, fs::AbstractVector; sort::Bool=false)
    headers = _makeheaders(fs, setdiff(_names(gd), _names(gd.parent[gd.cols])))
    res = combine(x -> _aggregate(without(x, gd.cols), fs, headers), gd)
    sort && sort!(res, headers)
    res
end

# Groups DataFrame by cols before applying aggregate
function aggregate(d::AbstractDataFrame,
                   cols::Union{S, AbstractVector{S}},
                   fs::Any;
                   sort::Bool=false) where {S<:ColumnIndex}
    aggregate(groupby(d, cols, sort=sort), fs)
end

function funname(f)
    n = nameof(f)
    String(n)[1] == '#' ? :function : n
end

_makeheaders(fs::AbstractVector, cn::AbstractVector{Symbol}) =
    [Symbol(colname, '_', funname(f)) for f in fs for colname in cn]

function _aggregate(d::AbstractDataFrame, fs::AbstractVector,
                    headers::AbstractVector{Symbol}, sort::Bool=false)
    res = DataFrame(AbstractVector[vcat(f(d[i])) for f in fs for i in 1:size(d, 2)], headers, makeunique=true)
    sort && sort!(res, headers)
    res
end
