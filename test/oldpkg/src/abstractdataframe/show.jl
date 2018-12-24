function Base.summary(df::AbstractDataFrame) # -> String
    nrows, ncols = size(df)
    return @sprintf("%d×%d %s", nrows, ncols, typeof(df))
end

let
    local io = IOBuffer(Vector{UInt8}(undef, 80), read=true, write=true)
    global ourstrwidth

    """
        DataFrames.ourstrwidth(x::Any)

    Determine the number of characters that would be used to print a value.
    """
    function ourstrwidth(x::Any) # -> Int
        truncate(io, 0)
        ourshowcompact(io, x)
        textwidth(String(take!(io)))
    end
end

"""
    DataFrames.ourshowcompact(io::IO, x::Any)

Render a value to an IO object in a compact format. Unlike
`show`, render strings without surrounding quote marks.
"""
ourshowcompact(io::IO, x::Any) =
    show(IOContext(io, :compact=>true, :typeinfo=>typeof(x)), x) # -> Void
ourshowcompact(io::IO, x::AbstractString) = escape_string(io, x, "") # -> Void
ourshowcompact(io::IO, x::Symbol) = ourshowcompact(io, string(x)) # -> Void
ourshowcompact(io::IO, x::Nothing) = nothing

"""Return compact string representation of type T"""
function compacttype(T::Type, maxwidth::Int=8)
    T === Any && return "Any"
    T === Missing && return "Missing"
    sT = string(T)
    length(sT) ≤ maxwidth && return sT
    if T >: Missing
        T = Base.nonmissingtype(T)
        sT = string(T)
        suffix = "⍰"
        # handle the case when after removing Missing union type name is short
        length(sT) ≤ 8 && return sT * suffix
    else
        suffix = ""
    end
    T <: Union{CategoricalString, CategoricalValue} && return "Categorical…"*suffix
    # we abbreviate consistently to total of 8 characters
    match(Regex("^.\\w{0,$(7-length(suffix))}"), sT).match * "…"*suffix
end

"""
    DataFrames.getmaxwidths(df::AbstractDataFrame,
                            rowindices1::AbstractVector{Int},
                            rowindices2::AbstractVector{Int},
                            rowlabel::Symbol)

Calculate, for each column of an AbstractDataFrame, the maximum
string width used to render the name of that column, its type, and the
longest entry in that column -- among the rows of the data frame
will be rendered to IO. The widths for all columns are returned as a
vector.

Return a `Vector{Int}` giving the maximum string widths required to render
each column, including that column's name and type.

NOTE: The last entry of the result vector is the string width of the
implicit row ID column contained in every `AbstractDataFrame`.

# Arguments
- `df::AbstractDataFrame`: The data frame whose columns will be printed.
- `rowindices1::AbstractVector{Int}: A set of indices of the first
  chunk of the AbstractDataFrame that would be rendered to IO.
- `rowindices2::AbstractVector{Int}: A set of indices of the second
  chunk of the AbstractDataFrame that would be rendered to IO. Can
  be empty if the AbstractDataFrame would be printed without any
  ellipses.
- `rowlabel::AbstractString`: The label that will be used when rendered the
  numeric ID's of each row. Typically, this will be set to "Row".

# Examples
```jldoctest
julia> using DataFrames

julia> df = DataFrame(A = 1:3, B = ["x", "yy", "z"]);

julia> DataFrames.getmaxwidths(df, 1:1, 3:3, :Row)
3-element Array{Int64,1}:
 1
 1
 3
```
"""
function getmaxwidths(df::AbstractDataFrame,
                      rowindices1::AbstractVector{Int},
                      rowindices2::AbstractVector{Int},
                      rowlabel::Symbol) # -> Vector{Int}
    maxwidths = Vector{Int}(undef, size(df, 2) + 1)

    undefstrwidth = ourstrwidth(Base.undef_ref_str)

    j = 1
    for (name, col) in eachcol(df, true)
        # (1) Consider length of column name
        maxwidth = ourstrwidth(name)

        # (2) Consider length of longest entry in that column
        for indices in (rowindices1, rowindices2), i in indices
            if isassigned(col, i)
                maxwidth = max(maxwidth, ourstrwidth(col[i]))
            else
                maxwidth = max(maxwidth, undefstrwidth)
            end
        end
        maxwidths[j] = max(maxwidth, ourstrwidth(compacttype(eltype(col))))
        j += 1
    end

    rowmaxwidth1 = isempty(rowindices1) ? 0 : ndigits(maximum(rowindices1))
    rowmaxwidth2 = isempty(rowindices2) ? 0 : ndigits(maximum(rowindices2))
    maxwidths[j] = max(max(rowmaxwidth1, rowmaxwidth2), ourstrwidth(rowlabel))

    return maxwidths
end

"""
    DataFrames.getprintedwidth(maxwidths::Vector{Int})

Given the maximum widths required to render each column of an
`AbstractDataFrame`, return the total number of characters
that would be required to render an entire row to an I/O stream.

NOTE: This width includes the whitespace and special characters used to
pretty print the `AbstractDataFrame`.

# Arguments
- `maxwidths::Vector{Int}`: The maximum width needed to render each
  column of an `AbstractDataFrame`.

# Examples
```jldoctest
julia> using DataFrames

julia> df = DataFrame(A = 1:3, B = ["x", "yy", "z"]);

julia> maxwidths = DataFrames.getmaxwidths(df, 1:1, 3:3, :Row)
3-element Array{Int64,1}:
 1
 1
 3

julia> DataFrames.getprintedwidth(maxwidths)
15
```
"""
function getprintedwidth(maxwidths::Vector{Int}) # -> Int
    # Include length of line-initial |
    totalwidth = 1
    for i in 1:length(maxwidths)
        # Include length of field + 2 spaces + trailing |
        totalwidth += maxwidths[i] + 3
    end
    return totalwidth
end

"""
    getchunkbounds(maxwidths::Vector{Int},
                   splitcols::Bool,
                   availablewidth::Int)

When rendering an `AbstractDataFrame` to a REPL window in chunks, each of
which will fit within the width of the REPL window, this function will
return the indices of the columns that should be included in each chunk.

NOTE: The resulting bounds should be interpreted as follows: the
i-th chunk bound is the index MINUS 1 of the first column in the
i-th chunk. The (i + 1)-th chunk bound is the EXACT index of the
last column in the i-th chunk. For example, the bounds [0, 3, 5]
imply that the first chunk contains columns 1-3 and the second chunk
contains columns 4-5.

# Arguments
- `maxwidths::Vector{Int}`: The maximum width needed to render each
  column of an AbstractDataFrame.
- `splitcols::Bool`: Whether to split printing in chunks of columns
  fitting the screen width rather than printing all columns in the same block.
- `availablewidth::Int`: The available width in the REPL.

# Examples
```jldoctest
julia> using DataFrames

julia> df = DataFrame(A = 1:3, B = ["x", "yy", "z"]);

julia> maxwidths = DataFrames.getmaxwidths(df, 1:1, 3:3, :Row)
3-element Array{Int64,1}:
 1
 1
 3

julia> DataFrames.getchunkbounds(maxwidths, true, displaysize()[2])
2-element Array{Int64,1}:
 0
 2
```
"""
function getchunkbounds(maxwidths::Vector{Int},
                        splitcols::Bool,
                        availablewidth::Int) # -> Vector{Int}
    ncols = length(maxwidths) - 1
    rowmaxwidth = maxwidths[ncols + 1]
    if splitcols
        chunkbounds = [0]
        # Include 2 spaces + 2 | characters for row/col label
        totalwidth = rowmaxwidth + 4
        for j in 1:ncols
            # Include 2 spaces + | character in per-column character count
            totalwidth += maxwidths[j] + 3
            if totalwidth > availablewidth
                push!(chunkbounds, j - 1)
                totalwidth = rowmaxwidth + 4 + maxwidths[j] + 3
            end
        end
        push!(chunkbounds, ncols)
    else
        chunkbounds = [0, ncols]
    end
    return chunkbounds
end

"""
    showrowindices(io::IO,
                   df::AbstractDataFrame,
                   rowindices::AbstractVector{Int},
                   maxwidths::Vector{Int},
                   leftcol::Int,
                   rightcol::Int)

Render a subset of rows and columns of an `AbstractDataFrame` to an
I/O stream. For chunked printing, this function is used to print a
single chunk, starting from the first indicated column and ending with
the last indicated column. Assumes that the maximum string widths
required for printing have been precomputed.

# Arguments
- `io::IO`: The I/O stream to which `df` will be printed.
- `df::AbstractDataFrame`: An AbstractDataFrame.
- `rowindices::AbstractVector{Int}`: The indices of the subset of rows
  that will be rendered to `io`.
- `maxwidths::Vector{Int}`: The pre-computed maximum string width
  required to render each column.
- `leftcol::Int`: The index of the first column in a chunk to be rendered.
- `rightcol::Int`: The index of the last column in a chunk to be rendered.

# Examples
```jldoctest
julia> using DataFrames

julia> df = DataFrame(A = 1:3, B = ["x", "y", "z"]);

julia> DataFrames.showrowindices(stdout, df, 1:2, [1, 1, 5], 1, 2)
│ 1     │ 1 │ x │
│ 2     │ 2 │ y │
```
"""
function showrowindices(io::IO,
                        df::AbstractDataFrame,
                        rowindices::AbstractVector{Int},
                        maxwidths::Vector{Int},
                        leftcol::Int,
                        rightcol::Int) # -> Void
    rowmaxwidth = maxwidths[end]

    for i in rowindices
        # Print row ID
        @printf io "│ %d" i
        padding = rowmaxwidth - ndigits(i)
        for _ in 1:padding
            write(io, ' ')
        end
        print(io, " │ ")
        # Print DataFrame entry
        for j in leftcol:rightcol
            strlen = 0
            if isassigned(df[j], i)
                s = df[i, j]
                strlen = ourstrwidth(s)
                if ismissing(s)
                    printstyled(io, s, color=:light_black)
                elseif s === nothing
                    strlen = 0
                else
                    ourshowcompact(io, s)
                end
            else
                strlen = ourstrwidth(Base.undef_ref_str)
                ourshowcompact(io, Base.undef_ref_str)
            end
            padding = maxwidths[j] - strlen
            for _ in 1:padding
                write(io, ' ')
            end
            if j == rightcol
                if i == rowindices[end]
                    print(io, " │")
                else
                    print(io, " │\n")
                end
            else
                print(io, " │ ")
            end
        end
    end
    return
end

"""
    showrows(io::IO,
             df::AbstractDataFrame,
             rowindices1::AbstractVector{Int},
             rowindices2::AbstractVector{Int},
             maxwidths::Vector{Int},
             splitcols::Bool = false,
             allcols::Bool = false,
             rowlabel::Symbol = :Row,
             displaysummary::Bool = true)

Render a subset of rows (possibly in chunks) of an `AbstractDataFrame` to an
I/O stream.

NOTE: The value of `maxwidths[end]` must be the string width of
`rowlabel`.

# Arguments
- `io::IO`: The I/O stream to which `df` will be printed.
- `df::AbstractDataFrame`: An AbstractDataFrame.
- `rowindices1::AbstractVector{Int}`: The indices of the first subset
  of rows to be rendered.
- `rowindices2::AbstractVector{Int}`: The indices of the second subset
  of rows to be rendered. An ellipsis will be printed before
  rendering this second subset of rows.
- `maxwidths::Vector{Int}`: The pre-computed maximum string width
  required to render each column.
- `allcols::Bool = false`: Whether to print all columns, rather than
  a subset that fits the device width.
- `splitcols::Bool`: Whether to split printing in chunks of columns fitting the screen width
  rather than printing all columns in the same block.
- `rowlabel::Symbol`: What label should be printed when rendering the
  numeric ID's of each row? Defaults to `:Row`.
- `displaysummary::Bool`: Should a brief string summary of the
  AbstractDataFrame be rendered to the I/O stream before printing the
  contents of the renderable rows? Defaults to `true`.

# Examples
julia> using DataFrames

julia> df = DataFrame(A = 1:3, B = ["x", "y", "z"]);

julia> DataFrames.showrows(stdout, df, 1:2, 3:3, [5, 6, 3], false, true, :Row, true)
3×2 DataFrame
│ Row │ A     │ B      │
│     │ Int64 │ String │
├─────┼───────┼────────┤
│ 1   │ 1     │ x      │
│ 2   │ 2     │ y      │
⋮
│ 3   │ 3     │ z      │
```
"""
function showrows(io::IO,
                  df::AbstractDataFrame,
                  rowindices1::AbstractVector{Int},
                  rowindices2::AbstractVector{Int},
                  maxwidths::Vector{Int},
                  splitcols::Bool = false,
                  allcols::Bool = false,
                  rowlabel::Symbol = :Row,
                  displaysummary::Bool = true) # -> Void
    ncols = size(df, 2)

    if isempty(rowindices1)
        if displaysummary
            println(io, summary(df))
        end
        return
    end

    rowmaxwidth = maxwidths[ncols + 1]
    chunkbounds = getchunkbounds(maxwidths, splitcols, displaysize(io)[2])
    nchunks = allcols ? length(chunkbounds) - 1 : min(length(chunkbounds) - 1, 1)

    header = displaysummary ? summary(df) : ""
    if !allcols && length(chunkbounds) > 2
        header *= ". Omitted printing of $(chunkbounds[end] - chunkbounds[2]) columns"
    end
    println(io, header)

    for chunkindex in 1:nchunks
        leftcol = chunkbounds[chunkindex] + 1
        rightcol = chunkbounds[chunkindex + 1]

        # Print column names
        @printf io "│ %s" rowlabel
        padding = rowmaxwidth - ourstrwidth(rowlabel)
        for itr in 1:padding
            write(io, ' ')
        end
        print(io, " │ ")
        for j in leftcol:rightcol
            s = _names(df)[j]
            ourshowcompact(io, s)
            padding = maxwidths[j] - ourstrwidth(s)
            for itr in 1:padding
                write(io, ' ')
            end
            if j == rightcol
                print(io, " │\n")
            else
                print(io, " │ ")
            end
        end

        # Print column types
        print(io, "│ ")
        padding = rowmaxwidth
        for itr in 1:padding
            write(io, ' ')
        end
        print(io, " │ ")
        for j in leftcol:rightcol
            s = compacttype(eltype(df[j]), maxwidths[j])
            printstyled(io, s, color=:light_black)
            padding = maxwidths[j] - ourstrwidth(s)
            for itr in 1:padding
                write(io, ' ')
            end
            if j == rightcol
                print(io, " │\n")
            else
                print(io, " │ ")
            end
        end

        # Print table bounding line
        write(io, '├')
        for itr in 1:(rowmaxwidth + 2)
            write(io, '─')
        end
        write(io, '┼')
        for j in leftcol:rightcol
            for itr in 1:(maxwidths[j] + 2)
                write(io, '─')
            end
            if j < rightcol
                write(io, '┼')
            else
                write(io, '┤')
            end
        end
        write(io, '\n')

        # Print main table body, potentially in two abbreviated sections
        showrowindices(io,
                       df,
                       rowindices1,
                       maxwidths,
                       leftcol,
                       rightcol)

        if !isempty(rowindices2)
            print(io, "\n⋮\n")
            showrowindices(io,
                           df,
                           rowindices2,
                           maxwidths,
                           leftcol,
                           rightcol)
        end

        # Print newlines to separate chunks
        if chunkindex < nchunks
            print(io, "\n\n")
        end
    end

    return
end

"""
    show([io::IO,] df::AbstractDataFrame;
         allrows::Bool = !get(io, :limit, false),
         allcols::Bool = !get(io, :limit, false),
         allgroups::Bool = !get(io, :limit, false),
         splitcols::Bool = get(io, :limit, false),
         rowlabel::Symbol = :Row,
         summary::Bool = true)

Render a data frame to an I/O stream. The specific visual
representation chosen depends on the width of the display.

If `io` is omitted, the result is printed to `stdout`,
and `allrows`, `allcols` and `allgroups` default to `false`
while `splitcols` defaults to `true`.

# Arguments
- `io::IO`: The I/O stream to which `df` will be printed.
- `df::AbstractDataFrame`: The data frame to print.
- `allrows::Bool `: Whether to print all rows, rather than
  a subset that fits the device height. By default this is the case only if
  `io` does not have the `IOContext` property `limit` set.
- `allcols::Bool`: Whether to print all columns, rather than
  a subset that fits the device width. By default this is the case only if
  `io` does not have the `IOContext` property `limit` set.
- `allgroups::Bool`: Whether to print all groups rather than
  the first and last, when `df` is a `GroupedDataFrame`.
  By default this is the case only if `io` does not have the `IOContext` property
  `limit` set.
- `splitcols::Bool`: Whether to split printing in chunks of columns fitting the screen width
  rather than printing all columns in the same block. Only applies if `allcols` is `true`.
  By default this is the case only if `io` has the `IOContext` property `limit` set.
- `rowlabel::Symbol = :Row`: The label to use for the column containing row numbers.
- `summary::Bool = true`: Whether to print a brief string summary of the data frame.

# Examples
```jldoctest
julia> using DataFrames

julia> df = DataFrame(A = 1:3, B = ["x", "y", "z"]);

julia> show(df, allcols=true)
3×2 DataFrame
│ Row │ A     │ B      │
│     │ Int64 │ String │
├─────┼───────┼────────┤
│ 1   │ 1     │ x      │
│ 2   │ 2     │ y      │
│ 3   │ 3     │ z      │
```
"""
function Base.show(io::IO,
                   df::AbstractDataFrame;
                   allrows::Bool = !get(io, :limit, false),
                   allcols::Bool = !get(io, :limit, false),
                   splitcols = get(io, :limit, false),
                   rowlabel::Symbol = :Row,
                   summary::Bool = true) # -> Nothing
    nrows = size(df, 1)
    dsize = displaysize(io)
    availableheight = dsize[1] - 7
    nrowssubset = fld(availableheight, 2)
    bound = min(nrowssubset - 1, nrows)
    if allrows || nrows <= availableheight
        rowindices1 = 1:nrows
        rowindices2 = 1:0
    else
        rowindices1 = 1:bound
        rowindices2 = max(bound + 1, nrows - nrowssubset + 1):nrows
    end
    maxwidths = getmaxwidths(df, rowindices1, rowindices2, rowlabel)
    width = getprintedwidth(maxwidths)
    showrows(io,
             df,
             rowindices1,
             rowindices2,
             maxwidths,
             splitcols,
             allcols,
             rowlabel,
             summary)
    return
end

function Base.show(df::AbstractDataFrame;
                   allrows::Bool = !get(stdout, :limit, true),
                   allcols::Bool = !get(stdout, :limit, true),
                   splitcols = get(stdout, :limit, true),
                   rowlabel::Symbol = :Row,
                   summary::Bool = true) # -> Nothing
    return show(stdout, df,
                allrows=allrows, allcols=allcols, splitcols=splitcols,
                rowlabel=rowlabel, summary=summary)
end
