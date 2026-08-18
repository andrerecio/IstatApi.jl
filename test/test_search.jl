@testset "search" begin
    @testset "search is local: zero requests" begin
        log = String[]
        with_transport(recording_transport(Dict{String,Any}(); log)) do
            res = search_dataflow("industrial production")
            @test nrow(res) > 0
        end
        @test isempty(log)
    end

    @testset "ranking" begin
        res = search_dataflow("industrial production")
        @test "115_333" in res.id
        @test issorted(res.score, rev = true)
        # the short aggregate flow outranks its long-named children
        @test findfirst(==("115_333"), res.id) <
              something(findfirst(==("115_333_DF_DCSC_INDXPRODIND_1_1"), res.id), nrow(res) + 1)
        # deterministic total order
        @test res.id == search_dataflow("industrial production").id

        # an exact id query dominates everything
        @test search_dataflow("115_333").id[1] == "115_333"

        # prefix matching: "industr prod" still finds it
        @test "115_333" in search_dataflow("industr prod").id

        # AND semantics: an impossible token kills the row
        @test nrow(search_dataflow("industrial zzzqx")) == 0
    end

    @testset "accents and languages" begin
        # Italian-only query finds the flow via name_it
        @test "115_333" in search_dataflow("produzione industriale").id
        @test "115_333" in search_dataflow("produzione industriale"; lang = :it).id
        # accent-insensitive: "attivita" must match "attività"
        @test nrow(search_dataflow("attivita"; lang = :it)) > 0
        # lang = :en must not see Italian-only matches
        res_en = search_dataflow("coltivazioni"; lang = :en)
        @test !("101_1015" in res_en.id)
        @test "101_1015" in search_dataflow("coltivazioni"; lang = :it).id
    end

    @testset "limit, must_contain, Regex" begin
        @test nrow(search_dataflow("data"; limit = 5)) <= 5
        res = search_dataflow("production"; must_contain = "ateco")
        @test nrow(res) > 0
        @test all(occursin("ateco", IstatApi._norm(string(r.id, r.name_en, r.name_it)))
                  for r in eachrow(res))

        res = search_dataflow(r"^115_333$")
        @test res.id == ["115_333"]
        @test nrow(search_dataflow(r"produzione industriale"; lang = :it)) > 0
    end

    @testset "bad input dies locally" begin
        @test_throws ArgumentError search_dataflow("")
        @test_throws ArgumentError search_dataflow("x"; lang = :de)
    end

    @testset "order is a total order: shuffled catalogue, same result" begin
        # the shipped snapshot is loaded by now
        name = "dataflows_IT1.csv"
        original = IstatApi._catalogue(name)
        expected = search_dataflow("production")
        try
            for seed in (1, 2, 3)
                perm = collect(1:nrow(original))
                # a deterministic, dependency-free shuffle
                for i in length(perm):-1:2
                    j = mod1(i * 7919 + seed * 104729, i)
                    perm[i], perm[j] = perm[j], perm[i]
                end
                IstatApi._CATALOGUE_CACHE[name] = original[perm, :]
                @test search_dataflow("production").id == expected.id
                @test search_dataflow("production").score == expected.score
            end
        finally
            IstatApi._CATALOGUE_CACHE[name] = original
        end
    end
end
