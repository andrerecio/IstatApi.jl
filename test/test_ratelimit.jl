@testset "rate limiter" begin
    # The shipped default is load-bearing; assert it before anything mutates it.
    @test rate_limit() == (interval = 15.0, per_minute = 4)

    @test_throws ArgumentError set_rate_limit!(interval = -1.0)
    @test_throws ArgumentError set_rate_limit!(per_minute = 0)
    @test rate_limit() == (interval = 15.0, per_minute = 4)

    @testset "_wait_time is pure and exact" begin
        t = 1.0e9
        rate = (interval = 15.0, per_minute = 4)
        @test IstatApi._wait_time(Float64[], rate, t) == 0.0
        @test IstatApi._wait_time([t - 5.0], rate, t) ≈ 10.0
        @test IstatApi._wait_time([t - 20.0], rate, t) == 0.0
        # four in the window: the oldest of the newest four must age out
        @test IstatApi._wait_time([t - 59.0, t - 40.0, t - 30.0, t - 16.0], rate, t) ≈ 1.0
        # the interval gate can dominate the window gate
        @test IstatApi._wait_time([t - 59.0, t - 40.0, t - 30.0, t - 5.0], rate, t) ≈ 10.0
        # window gate alone: the oldest of the newest two (t - 40) ages out at t + 20
        @test IstatApi._wait_time([t - 40.0, t - 30.0], (interval = 0.0, per_minute = 2), t) ≈ 20.0
        # stamps older than the window never count
        @test IstatApi._wait_time([t - 70.0, t - 65.0], (interval = 0.0, per_minute = 2), t) == 0.0
    end

    @testset "the second request waits for the interval" begin
        responses = Dict(
            "https://example.invalid/a" => (200, [], "aaa"),
            "https://example.invalid/b" => (200, [], "bbb"),
        )
        log = String[]
        with_online() do
            with_transport(recording_transport(responses; log)) do
                set_rate_limit!(interval = 0.2, per_minute = 10_000)
                try
                    t0 = time()
                    IstatApi._fetch("https://example.invalid/a"; cache = false)
                    IstatApi._fetch("https://example.invalid/b"; cache = false)
                    @test time() - t0 >= 0.2
                finally
                    set_rate_limit!()
                end
            end
        end
        @test log == ["https://example.invalid/a", "https://example.invalid/b"]
        @test rate_limit() == (interval = 15.0, per_minute = 4)
    end

    @testset "with_budget caps network requests" begin
        responses = Dict(
            ("https://example.invalid/budget/$i" => (200, [], "x$i") for i in 1:4)...,
        )
        log = String[]
        with_online() do
            with_transport(recording_transport(responses; log)) do
                with_fast_limit() do
                    used0 = requests_used()
                    run_over_budget() = with_budget(3) do
                        for i in 1:4
                            IstatApi._fetch("https://example.invalid/budget/$i"; cache = false)
                        end
                    end
                    @test_throws BudgetExhaustedError run_over_budget()
                    # exactly three went out; the fourth was refused pre-network
                    @test length(log) == 3
                    @test requests_used() - used0 == 3
                    # the budget is scoped: requests are unrestricted again
                    IstatApi._fetch("https://example.invalid/budget/4"; cache = false)
                    @test length(log) == 4
                end
            end
        end
    end
end
