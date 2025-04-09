# I den här filen bygger ni modellen. Notera att det är skrivet som en modul, dvs ett paket. 
# Så när ni ska använda det, så skriver ni Using energisystemprojekt i er REPL, då får ni ut det ni
# exporterat. Se rad 9.

module energisystemprojekt


using JuMP, AxisArrays, Gurobi, UnPack

export runmodel

include("input_energisystemprojekt.jl")

function buildmodel(input)

    println("\nBuilding model...")
 
    @unpack REGION, PLANT, HOUR, numregions, load, maxcap, ic, rc, fc, lt, ac, wind_cf, pv_cf, inflow = input

    m = Model(Gurobi.Optimizer)

    @variables m begin

        Electricity[r in REGION, p in PLANT, h in HOUR]       >= 0        # MWh/h
        Capacity[r in REGION, p in PLANT]                     >= 0        # MW

        Systemcost[r in REGION]                               >= 0
        ReservoirLevel[h in HOUR]                             >= 0         #MW

        Co2[r in REGION]                                      >= 0

    end #variables


    #Variable bounds
    for r in REGION, p in PLANT
        set_upper_bound(Capacity[r, p], maxcap[r, p])
    end


    @constraints m begin
        GenerationGH[r in REGION, p in [:Gas, :Hydro], h in HOUR],
            Electricity[r, p, h] <= Capacity[r, p] # * capacity factor

        GenerationW[r in REGION, h in HOUR],
            Electricity[r, :Wind, h] <= Capacity[r, :Wind] * wind_cf[r, h]

        GenerationP[r in REGION, h in HOUR],
            Electricity[r, :PV, h] <= Capacity[r, :PV] * pv_cf[r, h]

        Load[r in REGION, h in HOUR],
            sum(Electricity[r, p, h] for p in PLANT) >= load[r,h]


        rescap[h in HOUR],
            ReservoirLevel[h] <= 33000000

        ReservoirLevel[1] == ReservoirLevel[length(HOUR)]

        resChange[h in 1:length(HOUR)-1],
            ReservoirLevel[h+1] == ReservoirLevel[h] + inflow[h]- Electricity[:SE, :Hydro, h]
        

        CO2[r in REGION, h in HOUR],
            Co2[r] >= sum(Electricity[r, :Gas, h]/0.4*0.202)
        
        SystemCost[r in REGION],
            Systemcost[r] >= sum(ac[p]*Capacity[r, p] for p in PLANT) +
                sum(rc[p]*Electricity[r, p, h] for p in PLANT, h in HOUR) # sum of all annualized costs
    
    end #constraints


    @objective m Min begin
        sum(Systemcost[r] for r in REGION)
    end # objective

    return (;m, Capacity, Co2, ReservoirLevel)

end # buildmodel

function runmodel() 

    input = read_input()

    model = buildmodel(input)

    @unpack m, Capacity, Co2, ReservoirLevel = model   
    
    println("\nSolving model...")
    
    status = optimize!(m)
    

    if termination_status(m) == MOI.OPTIMAL
        println("\nSolve status: Optimal")   
    elseif termination_status(m) == MOI.TIME_LIMIT && has_values(m)
        println("\nSolve status: Reached the time-limit")
    else
        error("The model was not solved correctly.")
    end

    Cost_result = objective_value(m)/1000000 # M€
    Capacity_result = value.(Capacity)

    println("\ncapacity: ", Capacity_result)
    println("\nReservoir level: ",value.(ReservoirLevel)[8760])
    println("\no2: ", value.(Co2))
    println("\nCost (M€): ", Cost_result)
   

    nothing

end #runmodel



end # module

