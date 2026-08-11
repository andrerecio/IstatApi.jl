@testset "periods" begin
    parse_period = IstatApi.parse_period
    period_frequency = IstatApi.period_frequency

    @testset "every TIME_PERIOD shape, both at values" begin
        # annual
        @test parse_period("2026") == Date(2026, 1, 1)
        @test parse_period("2026", at = :last) == Date(2026, 12, 31)
        # half-yearly
        @test parse_period("2026-S1") == Date(2026, 1, 1)
        @test parse_period("2026-S1", at = :last) == Date(2026, 6, 30)
        @test parse_period("2026-S2") == Date(2026, 7, 1)
        @test parse_period("2026-S2", at = :last) == Date(2026, 12, 31)
        # quarterly — period START, not the quarter's third month
        @test parse_period("2026-Q2") == Date(2026, 4, 1)
        @test parse_period("2026-Q2", at = :last) == Date(2026, 6, 30)
        @test parse_period("2026-Q1") == Date(2026, 1, 1)
        @test parse_period("2026-Q4", at = :last) == Date(2026, 12, 31)
        # monthly (leap-aware :last)
        @test parse_period("2026-06") == Date(2026, 6, 1)
        @test parse_period("2026-06", at = :last) == Date(2026, 6, 30)
        @test parse_period("2024-02", at = :last) == Date(2024, 2, 29)
        # daily
        @test parse_period("2026-06-15") == Date(2026, 6, 15)
        @test parse_period("2026-06-15", at = :last) == Date(2026, 6, 15)
        # the NowcastIT "third month of the quarter" convention is one line
        @test Dates.firstdayofmonth(parse_period("2026-Q2", at = :last)) == Date(2026, 6, 1)
    end

    @testset "frequencies" begin
        @test period_frequency("2026") == "A"
        @test period_frequency("2026-S1") == "S"
        @test period_frequency("2026-Q2") == "Q"
        @test period_frequency("2026-06") == "M"
        @test period_frequency("2026-06-15") == "D"
    end

    @testset "rejects garbage" begin
        @test_throws ArgumentError parse_period("Q2-2026")
        @test_throws ArgumentError parse_period("2026-13")
        @test_throws ArgumentError parse_period("2026-Q5")
        @test_throws ArgumentError parse_period("")
        @test_throws ArgumentError parse_period("2026-06", at = :middle)
        @test_throws ArgumentError period_frequency("banana")
    end
end
