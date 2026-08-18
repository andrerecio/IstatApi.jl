@testset "SDMX-CSV" begin
    csv = """
    DATAFLOW,FREQ,REF_AREA,DATA_TYPE,ADJUSTMENT,ECON_ACTIVITY_NACE_2007,TIME_PERIOD,OBS_VALUE,OBS_STATUS,NOTE_IT,UNIT_MULT
    IT1:115_333(1.0),M,IT,IND_PROD_21,Y,0020,2026-05,94.4,A,,0
    IT1:115_333(1.0),M,IT,IND_PROD_21,Y,0020,2026-06,93.5,A,"provvisorio, rivisto",0
    IT1:115_333(1.0),M,IT,IND_PROD_21,Y,0020,2026-07,,M,,0
    """

    df = read_sdmx_csv(csv)

    @testset "shape and provenance" begin
        @test nrow(df) == 3
        @test names(df)[1] == "DATAFLOW"
        @test df.DATAFLOW[1] == "IT1:115_333(1.0)"   # round-trips into get_dataflow
        # period/freq sit right after TIME_PERIOD
        i = findfirst(==("TIME_PERIOD"), names(df))
        @test names(df)[i+1] == "period" && names(df)[i+2] == "freq"
    end

    @testset "codes stay Strings — the highest-value regression test" begin
        @test df.ECON_ACTIVITY_NACE_2007 isa AbstractVector{<:AbstractString}
        @test df.ECON_ACTIVITY_NACE_2007[1] == "0020"
        @test df.UNIT_MULT[1] == "0"
    end

    @testset "OBS_VALUE: Float64 with missing, never NaN" begin
        @test eltype(df.OBS_VALUE) == Union{Float64,Missing}
        @test df.OBS_VALUE[1] == 94.4
        @test df.OBS_VALUE[3] === missing
        @test !any(v -> v isa Float64 && isnan(v), df.OBS_VALUE)
    end

    @testset "quoted commas in NOTE_* survive" begin
        @test df.NOTE_IT[2] == "provvisorio, rivisto"
        @test df.NOTE_IT[1] === missing
    end

    @testset "period start + freq alongside" begin
        @test df.period == [Date(2026, 5, 1), Date(2026, 6, 1), Date(2026, 7, 1)]
        @test all(==("M"), df.freq)
    end

    @testset "sources: IO, bytes, path, content string" begin
        @test read_sdmx_csv(IOBuffer(csv)).OBS_VALUE[1] == 94.4
        path = joinpath(mktempdir(), "slice.csv")
        write(path, csv)
        @test nrow(read_sdmx_csv(path)) == 3
    end

    @testset "malformed input" begin
        @test_throws ArgumentError read_sdmx_csv("a,b\n1,2\n")
    end

    @testset "server labels (;labels=both) normalise to code + _label columns" begin
        lab = read_sdmx_csv("""
        DATAFLOW,FREQ: Frequency,REF_AREA: Territory,TIME_PERIOD: Time,OBS_VALUE,OBS_STATUS: Status,NOTE_DS: Dataset note
        IT1:X(1.0),M: monthly,IT: Italy,2026-05,94.4,,"TD1: note, with: colons"
        IT1:X(1.0),M: monthly,IT: Italy,2026-06,93.5,A: normal value,
        """)
        @test names(lab) == ["DATAFLOW", "FREQ", "FREQ_label", "REF_AREA", "REF_AREA_label",
                             "TIME_PERIOD", "period", "freq", "OBS_VALUE",
                             "OBS_STATUS", "OBS_STATUS_label", "NOTE_DS", "NOTE_DS_label"]
        @test lab.FREQ == ["M", "M"] && lab.FREQ_label == ["monthly", "monthly"]
        @test lab.REF_AREA_label == ["Italy", "Italy"]
        @test lab.TIME_PERIOD == ["2026-05", "2026-06"]        # plain cells: renamed only
        @test lab.OBS_STATUS[1] === missing && lab.OBS_STATUS[2] == "A"
        @test lab.OBS_STATUS_label == ["", "normal value"]
        # split on the first ": " only — labels may contain colons
        @test lab.NOTE_DS[1] == "TD1" && lab.NOTE_DS_label[1] == "note, with: colons"
        @test lab.freq == ["M", "M"]
    end
end
