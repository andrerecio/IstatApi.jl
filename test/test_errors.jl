@testset "error hierarchy" begin
    @test IstatError <: Exception
    for E in (OfflineError, BudgetExhaustedError, RateLimitError, BannedError,
              NoDataError, RequestFailed)
        @test E <: IstatError
    end

    # The messages must name the way out.
    msg = sprint(showerror, BannedError(DateTime(2026, 8, 12)))
    @test occursin("clear_ban!", msg)
    @test occursin("2026-08-12", msg)

    msg = sprint(showerror, NoDataError("https://example.invalid/data/X/A.B"))
    @test occursin("available(", msg)

    msg = sprint(showerror, OfflineError("GET /dataflow/IT1"))
    @test occursin("online!", msg)

    @test occursin("Retry-After: 60", sprint(showerror, RateLimitError(60)))
    @test !occursin("Retry-After", sprint(showerror, RateLimitError(nothing)))

    @test occursin("HTTP 500", sprint(showerror, RequestFailed(500, "https://example.invalid")))
    @test occursin("budget of 3", sprint(showerror, BudgetExhaustedError(3)))
end
