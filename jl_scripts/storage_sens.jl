# Run thermal storage sensitivity cases
# Note: the penalty for unmet loads should be L1 and not L2 for this file to produce expected results.
# An L1 norm will cause the algorithm to detect unfeasibility faster (because the unmet loads will all be on the same hour).

push!(LOAD_PATH, joinpath(ENV["REPO_PATH"], "Sesi.jl/src"))

using CSV
using JuMP
using IterTools
using JSON
using DataFrames

import Sesi # import vs using so I can reload this from the REPL

reload("Sesi")

include("jl_utils.jl")

save = true
verb = true

if verb
    println(repeat("#",80))
    println("Starting storage sensitivity")
    println(repeat("#",80))
end
folderIn = joinpath(ENV["REPO_PATH"], "data/jl_in/")
folderOut = joinpath(ENV["REPO_PATH"], "data/jl_out/")

results = Dict()

fileNm = folderIn * "jlInput_x0.csv"

# Increase resolution as needed here
hot_lst=linspace(0., 1100., 30)
cold_lst=linspace(0., 120.e3, 30)

results["hot_lst"] = hot_lst
results["cold_lst"] = cold_lst
results["cost"] = zeros(length(hot_lst), length(cold_lst))
results["feas"] = zeros(length(hot_lst), length(cold_lst))
results["peak"] = zeros(length(hot_lst), length(cold_lst))
results["demandCharge"] = zeros(length(hot_lst), length(cold_lst))
results["agg_dollar"] = zeros(length(hot_lst), length(cold_lst))
results["chillers"] = zeros(length(hot_lst), length(cold_lst))
results["umHot"] = zeros(length(hot_lst), length(cold_lst))
results["umCold"] = zeros(length(hot_lst), length(cold_lst))
results["bill"] = Dict()

for (ihot, hot) in enumerate(hot_lst)
for (icold, cold) in enumerate(cold_lst)
    nChiller = 4.
    umCost = 1e7
    while umCost > 1e-2
        if verb
            @printf("hot: %.1f mmbtu - cold: %.1f tons - chillers %.0f\n", hot,
                cold, nChiller)
        end
        sesi, p, f = build_model(fileNm; verb=false, startDate=Date(2016,1,1),
            endDate=Date(2016,12,31), hot_storage=hot, cold_storage=cold,
            nChiller=nChiller, umLoadsL2=false)
        status = solve(sesi)

        if status == :Optimal
            bill = Sesi.campus_bill(sesi, f, p, verb=0)
            results["feas"][ihot,icold] = 1.
            results["peak"][ihot,icold] = maximum(getvalue(sesi[:peak]))
            results["demandCharge"][ihot,icold] = bill["demandCharge"]
            results["agg_dollar"][ihot,icold] = bill["agg_dollar"]
            results["bill"][(ihot,icold)] = bill
            results["chillers"][ihot,icold] = nChiller-4.
            if nChiller == 4.
                results["umHot"][ihot,icold] = sum(getvalue(sesi[:umHot]))
                results["umCold"][ihot,icold] = sum(getvalue(sesi[:umCold]))
            end
            umCost = bill["umLoads"]
            @printf("unmet Load Cost: %.6f\n", umCost)
        else
            warn("Unknown status!")
            println(hot)
            println(cold)
        end

        nChiller += 1.
    end
end
end

if save
    json_data = json(results);
    open(folderOut * "storage_sens_json_data", "w") do fw
        write(fw, json_data)
    end
end
